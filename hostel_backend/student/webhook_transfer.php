<?php
/**
 * Webhook Endpoint: Student Room & Hostel Transfer
 *
 * Real-time event from VStudy when a student transfers room/hostel.
 * Updates:
 * 1. `profile` table (room_allocation, hostel_name, dynamic warden)
 * 2. `users` table (RoomId, HostelName, RoomType)
 * 3. `room_change_requests` table (approved change log)
 * 4. `room_master` & `rooms_groups_details` (atomic occupancy recalculation for both old & new rooms)
 * 5. `audit_logs`
 *
 * Security: Requires 'X-API-Key' header or 'Authorization: Bearer <key>'.
 */

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-API-Key, X-Api-Key, x-api-key, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(200);
    exit(0);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Method Not Allowed. Only POST is accepted.'
    ]);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/api_config.php';

// --- 1. AUTHENTICATION ---
function getProvidedApiKey() {
    $headers = getallheaders();
    foreach (['X-API-Key', 'X-Api-Key', 'x-api-key', 'X-API-KEY'] as $h) {
        if (!empty($headers[$h])) {
            return trim($headers[$h]);
        }
    }
    $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    if (preg_match('/Bearer\s+(.*)$/i', $auth, $matches)) {
        return trim($matches[1]);
    }
    if (!empty($_SERVER['HTTP_X_API_KEY'])) {
        return trim($_SERVER['HTTP_X_API_KEY']);
    }
    return '';
}

$providedKey = getProvidedApiKey();
$expectedKey = defined('VSTAAY_API_KEY') ? VSTAAY_API_KEY : '';
$fallbackKey = defined('VSTUDY_CLIENT_SECRET') ? VSTUDY_CLIENT_SECRET : '';

$keyMatches = (!empty($providedKey) && (
    (!empty($expectedKey) && hash_equals($expectedKey, $providedKey)) ||
    (!empty($fallbackKey) && hash_equals($fallbackKey, $providedKey))
));

if (!$keyMatches) {
    http_response_code(401);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Invalid or missing authentication API key in header.'
    ]);
    exit();
}

// --- 2. PARSE REQUEST PAYLOAD ---
$rawBody = file_get_contents('php://input');
$body = json_decode($rawBody, true);

if (!is_array($body)) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Invalid JSON body in request.'
    ]);
    exit();
}

$rollNumber = trim(
    $body['rollNumber'] ??
    $body['registerNumber'] ??
    $body['reg_no'] ??
    $body['roll_no'] ??
    $body['student_id'] ?? ''
);

$toRoomNumber = trim(
    $body['toRoomNumber'] ??
    $body['newRoomNumber'] ??
    $body['roomNumber'] ??
    $body['room_number'] ??
    $body['room_no'] ??
    $body['to_room'] ?? ''
);

$toHostelName = trim(
    $body['toHostelName'] ??
    $body['newHostelName'] ??
    $body['hostelName'] ??
    $body['hostel_name'] ??
    $body['to_hostel'] ?? ''
);

$toRoomType = trim(
    $body['toRoomType'] ??
    $body['newRoomType'] ??
    $body['roomType'] ??
    $body['room_type'] ?? ''
);

$reason = trim($body['reason'] ?? $body['remarks'] ?? 'Transferred via VStudy webhook');

if (empty($rollNumber)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Missing required field: rollNumber / registerNumber'
    ]);
    exit();
}

if (empty($toRoomNumber)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Missing required field: toRoomNumber / newRoomNumber'
    ]);
    exit();
}

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $db->beginTransaction();

    // 1. Fetch existing student profile
    $profStmt = $db->prepare("SELECT * FROM profile WHERE reg_no = ? LIMIT 1");
    $profStmt->execute([$rollNumber]);
    $currentProfile = $profStmt->fetch(PDO::FETCH_ASSOC);

    if (!$currentProfile) {
        // Fallback: check users table
        $uStmt = $db->prepare("SELECT * FROM users WHERE username = ? LIMIT 1");
        $uStmt->execute([$rollNumber]);
        $currentUser = $uStmt->fetch(PDO::FETCH_ASSOC);

        if (!$currentUser) {
            $db->rollBack();
            http_response_code(404);
            echo json_encode([
                'success' => false,
                'status'  => 'error',
                'message' => "Student with rollNumber '$rollNumber' not found in database."
            ]);
            exit();
        }
    }

    $oldRoom   = $currentProfile['room_allocation'] ?? ($currentUser['RoomId'] ?? '');
    $oldHostel = $currentProfile['hostel_name'] ?? ($currentUser['HostelName'] ?? '');
    $studentId = $currentProfile['user_id'] ?? ($currentUser['id'] ?? null);
    $studentName = $currentProfile['full_name'] ?? ($currentUser['full_name'] ?? 'Student');

    // 2. Resolve target hostel & roomType if not explicitly passed
    if (empty($toHostelName) || empty($toRoomType)) {
        $rgdLookup = $db->prepare("
            SELECT hostel_name, room_type FROM rooms_groups_details 
            WHERE room_number = ? OR REPLACE(REPLACE(TRIM(room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(?), ' ', ''), '-', '')
            LIMIT 1
        ");
        $rgdLookup->execute([$toRoomNumber, $toRoomNumber]);
        $rgdRow = $rgdLookup->fetch(PDO::FETCH_ASSOC);

        if ($rgdRow) {
            if (empty($toHostelName)) $toHostelName = $rgdRow['hostel_name'] ?? '';
            if (empty($toRoomType))   $toRoomType   = $rgdRow['room_type'] ?? '';
        }

        if (empty($toHostelName)) {
            $rmLookup = $db->prepare("SELECT building_code, room_type FROM room_master WHERE room_no = ? OR room_code = ? LIMIT 1");
            $rmLookup->execute([$toRoomNumber, $toRoomNumber]);
            $rmRow = $rmLookup->fetch(PDO::FETCH_ASSOC);
            if ($rmRow) {
                if (empty($toHostelName)) $toHostelName = $rmRow['building_code'] ?? '';
                if (empty($toRoomType))   $toRoomType   = $rmRow['room_type'] ?? '';
            }
        }
    }

    if (empty($toHostelName)) {
        $toHostelName = $oldHostel;
    }

    // 3. Dynamic Warden Assignment for target room
    $newWarden = null;
    $wardenStmt = $db->prepare("
        SELECT warden_name FROM rooms_groups_details 
        WHERE (room_number = :rn OR REPLACE(REPLACE(TRIM(room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(:rn2), ' ', ''), '-', ''))
          AND warden_name IS NOT NULL AND warden_name != '' LIMIT 1
    ");
    $wardenStmt->execute([':rn' => $toRoomNumber, ':rn2' => $toRoomNumber]);
    $newWarden = $wardenStmt->fetchColumn() ?: null;

    if (!$newWarden && !empty($toHostelName)) {
        $staffStmt = $db->prepare("
            SELECT name FROM mapping_staff 
            WHERE LOWER(role) = 'warden' AND (LOWER(hostel_name) = LOWER(:hn) OR LOWER(:hn2) LIKE CONCAT('%', LOWER(hostel_name), '%')) LIMIT 1
        ");
        $staffStmt->execute([':hn' => $toHostelName, ':hn2' => $toHostelName]);
        $newWarden = $staffStmt->fetchColumn() ?: null;
    }

    // 4. Update `profile`
    $updProfile = $db->prepare("
        UPDATE profile SET 
            room_allocation = :new_room,
            hostel_name     = :new_hostel,
            warden          = COALESCE(:warden, warden)
        WHERE reg_no = :rollNumber
    ");
    $updProfile->execute([
        ':new_room'   => $toRoomNumber,
        ':new_hostel' => $toHostelName,
        ':warden'     => $newWarden,
        ':rollNumber' => $rollNumber
    ]);

    // 5. Update `users`
    $updUser = $db->prepare("
        UPDATE users SET 
            RoomId     = :new_room,
            HostelName = :new_hostel,
            RoomType   = COALESCE(NULLIF(:new_room_type, ''), RoomType)
        WHERE username = :rollNumber
    ");
    $updUser->execute([
        ':new_room'      => $toRoomNumber,
        ':new_hostel'    => $toHostelName,
        ':new_room_type' => $toRoomType,
        ':rollNumber'    => $rollNumber
    ]);

    // 6. Record in `room_change_requests`
    $requestId = 'RCR-' . strtoupper(substr(md5(uniqid((string)mt_rand(), true)), 0, 8));
    $insRcr = $db->prepare("
        INSERT INTO room_change_requests (
            request_id, student_id, student_name, student_reg_no,
            current_room, requested_room, requested_room_type,
            reason, status, payment_status, processed_by, processed_by_name,
            remarks, created_at, updated_at
        ) VALUES (
            :request_id, :student_id, :student_name, :student_reg_no,
            :current_room, :requested_room, :requested_room_type,
            :reason, 'approved', 'completed', 1, 'VStudy Webhook',
            'Transferred via VStudy real-time webhook', NOW(), NOW()
        )
    ");
    $insRcr->execute([
        ':request_id'          => $requestId,
        ':student_id'          => $studentId,
        ':student_name'        => $studentName,
        ':student_reg_no'      => $rollNumber,
        ':current_room'        => $oldRoom,
        ':requested_room'      => $toRoomNumber,
        ':requested_room_type' => $toRoomType,
        ':reason'              => $reason
    ]);

    // 7. Atomic Inventory Rebalance for BOTH old room and new room
    $roomsToRebalance = array_filter(array_unique([$oldRoom, $toRoomNumber]));
    foreach ($roomsToRebalance as $rNo) {
        $occStmt = $db->prepare("SELECT COUNT(*) FROM profile WHERE room_allocation = ?");
        $occStmt->execute([$rNo]);
        $occCount = (int)$occStmt->fetchColumn();

        $db->prepare("
            UPDATE room_master 
            SET occupied_beds = ?, 
                available_beds = GREATEST(0, total_beds - ?) 
            WHERE room_no = ? OR room_code = ?
        ")->execute([$occCount, $occCount, $rNo, $rNo]);

        $db->prepare("
            UPDATE rooms_groups_details 
            SET occupied_beds = ?, 
                available_beds = GREATEST(0, total_beds - ?) 
            WHERE room_number = ?
        ")->execute([$occCount, $occCount, $rNo]);
    }

    // 8. Audit Logging
    $db->prepare("
        INSERT INTO audit_logs (username, role, action, module_name, old_value, new_value, ip_address) 
        VALUES (?, 'system', 'WEBHOOK_STUDENT_TRANSFER', 'webhook', ?, ?, ?)
    ")->execute([
        $rollNumber,
        json_encode(['room' => $oldRoom, 'hostel' => $oldHostel]),
        json_encode(['room' => $toRoomNumber, 'hostel' => $toHostelName, 'warden' => $newWarden, 'request_id' => $requestId]),
        $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1'
    ]);

    $db->commit();

    http_response_code(200);
    echo json_encode([
        'success' => true,
        'status'  => 'success',
        'message' => "Student transferred successfully from $oldRoom to $toRoomNumber.",
        'data'    => [
            'request_id'      => $requestId,
            'roll_number'     => $rollNumber,
            'student_name'    => $studentName,
            'previous_room'   => $oldRoom,
            'previous_hostel' => $oldHostel,
            'new_room'        => $toRoomNumber,
            'new_hostel'      => $toHostelName,
            'new_room_type'   => $toRoomType,
            'warden_assigned' => $newWarden
        ]
    ]);

} catch (Exception $e) {
    if (isset($db) && $db->inTransaction()) {
        $db->rollBack();
    }
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Internal Server Error: ' . $e->getMessage()
    ]);
}
