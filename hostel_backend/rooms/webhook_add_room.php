<?php
/**
 * Webhook Endpoint: Add / Upsert Room
 *
 * Real-time event from VStudy when a room is created or modified.
 * Updates:
 * 1. `room_master` table (physical master record)
 * 2. `rooms_groups_details` table (allocation & group mapping)
 * 3. `audit_logs`
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

$roomNumber = trim(
    $body['roomNumber'] ??
    $body['room_no'] ??
    $body['room_number'] ??
    $body['roomNo'] ?? ''
);

$hostelName = trim(
    $body['hostelName'] ??
    $body['building_code'] ??
    $body['hostel_name'] ?? ''
);

$roomType = trim(
    $body['roomType'] ??
    $body['room_type'] ?? ''
);

if (empty($roomNumber)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Missing required field: roomNumber / room_no'
    ]);
    exit();
}

if (empty($hostelName)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Missing required field: hostelName / building_code'
    ]);
    exit();
}

// Capacity calculation
function extractCapacity($type, $default = 1) {
    $t = strtoupper($type);
    if (preg_match('/(\d+)\s*IN\s*1/', $t, $m)) {
        return (int)$m[1];
    }
    if (stripos($t, 'double') !== false || stripos($t, '2 sharing') !== false || stripos($t, '2-sharing') !== false) {
        return 2;
    }
    if (stripos($t, 'single') !== false || stripos($t, '1 sharing') !== false) {
        return 1;
    }
    if (stripos($t, 'triple') !== false || stripos($t, '3 sharing') !== false || stripos($t, '3-sharing') !== false) {
        return 3;
    }
    if (stripos($t, 'four') !== false || stripos($t, '4 sharing') !== false || stripos($t, '4-sharing') !== false) {
        return 4;
    }
    if (preg_match('/(\d+)\s*sharing/i', $t, $m)) {
        return (int)$m[1];
    }
    return $default;
}

$explicitCapacity = isset($body['totalBeds']) ? (int)$body['totalBeds'] : (isset($body['roomCapacity']) ? (int)$body['roomCapacity'] : (isset($body['total_beds']) ? (int)$body['total_beds'] : 0));
$totalBeds = $explicitCapacity > 0 ? $explicitCapacity : extractCapacity($roomType, 1);

$roomCode = trim($body['roomCode'] ?? $body['room_code'] ?? $roomNumber);
$campus = trim($body['campus'] ?? $body['location_name'] ?? '');
if (empty($campus)) {
    if (stripos($hostelName, 'Radiance') !== false || stripos($hostelName, 'Stunner') !== false || strpos($roomNumber, 'P-') === 0 || strpos($roomNumber, 'P0') === 0) {
        $campus = 'Poonamallee Campus';
    } else {
        $campus = 'Thandalam Campus';
    }
}

// Floor and Block parsing
$floorNo = trim($body['floorNo'] ?? $body['floor_no'] ?? '');
if (empty($floorNo)) {
    if (preg_match('/F0?(\d+)/i', $roomNumber, $m)) {
        $floorNo = $m[1];
    } else {
        $floorNo = '1';
    }
}

$blockNo = trim($body['blockNo'] ?? $body['block_no'] ?? '');
if (empty($blockNo)) {
    if (preg_match('/W0?([A-Z0-9]+)/i', $roomNumber, $m)) {
        $blockNo = 'W' . $m[1];
    } else {
        $blockNo = 'Main';
    }
}

$gender = strtolower(trim($body['gender'] ?? ''));
if (empty($gender)) {
    $gender = (stripos($hostelName, 'girls') !== false || stripos($hostelName, 'ponni') !== false || stripos($hostelName, 'vaigai') !== false || stripos($hostelName, 'siruvani') !== false) ? 'female' : 'male';
}

$amount = isset($body['amount']) ? (float)$body['amount'] : (isset($body['monthlyFee']) ? (float)$body['monthlyFee'] : 0.00);
$groupId = trim($body['groupId'] ?? $body['group_id'] ?? '');
$groupName = trim($body['groupName'] ?? $body['group_name'] ?? '');

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $db->beginTransaction();

    // 1. Check existing occupancy in profile
    $occStmt = $db->prepare("SELECT COUNT(*) FROM profile WHERE room_allocation = ?");
    $occStmt->execute([$roomNumber]);
    $currentOccupied = (int)$occStmt->fetchColumn();
    $availableBeds = max(0, $totalBeds - $currentOccupied);

    // 2. Lookup Warden for this group or hostel
    $wardenName = null;
    $wardenUserId = null;
    $wardenBioId = null;

    if (!empty($groupId)) {
        $grpStmt = $db->prepare("SELECT warden_name, warden_user_id, warden_bio_id FROM external_room_groups WHERE id = ? LIMIT 1");
        $grpStmt->execute([$groupId]);
        $grpRow = $grpStmt->fetch(PDO::FETCH_ASSOC);
        if ($grpRow) {
            $wardenName   = $grpRow['warden_name'];
            $wardenUserId = $grpRow['warden_user_id'];
            $wardenBioId  = $grpRow['warden_bio_id'];
        }
    }

    if (!$wardenName && !empty($hostelName)) {
        $stfStmt = $db->prepare("SELECT name, biometric_id FROM mapping_staff WHERE LOWER(role) = 'warden' AND (LOWER(hostel_name) = LOWER(?) OR LOWER(?) LIKE CONCAT('%', LOWER(hostel_name), '%')) LIMIT 1");
        $stfStmt->execute([$hostelName, $hostelName]);
        $stfRow = $stfStmt->fetch(PDO::FETCH_ASSOC);
        if ($stfRow) {
            $wardenName  = $stfRow['name'];
            $wardenBioId = $stfRow['biometric_id'];
        }
    }

    // 3. Upsert `room_master`
    $rmCheck = $db->prepare("SELECT id FROM room_master WHERE room_no = ? OR room_code = ? LIMIT 1");
    $rmCheck->execute([$roomNumber, $roomCode]);
    $existingRm = $rmCheck->fetch(PDO::FETCH_ASSOC);

    if ($existingRm) {
        $db->prepare("
            UPDATE room_master SET 
                location_name  = :location_name,
                building_code  = :building_code,
                floor_no       = :floor_no,
                block_no       = :block_no,
                room_type      = :room_type,
                total_beds     = :total_beds,
                room_capacity  = :room_capacity,
                occupied_beds  = :occupied_beds,
                available_beds = :available_beds,
                gender         = :gender,
                amount         = IF(:amount > 0, :amount, amount),
                active         = 1,
                updated_at     = NOW()
            WHERE id = :id
        ")->execute([
            ':location_name'  => $campus,
            ':building_code'  => $hostelName,
            ':floor_no'       => $floorNo,
            ':block_no'       => $blockNo,
            ':room_type'      => $roomType,
            ':total_beds'     => $totalBeds,
            ':room_capacity'  => $totalBeds,
            ':occupied_beds'  => $currentOccupied,
            ':available_beds' => $availableBeds,
            ':gender'         => $gender,
            ':amount'         => $amount,
            ':id'             => $existingRm['id']
        ]);
        $action = 'updated';
    } else {
        $db->prepare("
            INSERT INTO room_master (
                location_name, building_code, floor_no, block_no, room_no, room_code,
                room_type, total_beds, room_capacity, occupied_beds, available_beds,
                gender, amount, active, created_at, updated_at
            ) VALUES (
                :location_name, :building_code, :floor_no, :block_no, :room_no, :room_code,
                :room_type, :total_beds, :room_capacity, :occupied_beds, :available_beds,
                :gender, :amount, 1, NOW(), NOW()
            )
        ")->execute([
            ':location_name'  => $campus,
            ':building_code'  => $hostelName,
            ':floor_no'       => $floorNo,
            ':block_no'       => $blockNo,
            ':room_no'        => $roomNumber,
            ':room_code'      => $roomCode,
            ':room_type'      => $roomType,
            ':total_beds'     => $totalBeds,
            ':room_capacity'  => $totalBeds,
            ':occupied_beds'  => $currentOccupied,
            ':available_beds' => $availableBeds,
            ':gender'         => $gender,
            ':amount'         => $amount
        ]);
        $action = 'created';
    }

    // 4. Upsert `rooms_groups_details`
    $rgdCheck = $db->prepare("SELECT s_no FROM rooms_groups_details WHERE room_number = ? LIMIT 1");
    $rgdCheck->execute([$roomNumber]);
    $existingRgd = $rgdCheck->fetch(PDO::FETCH_ASSOC);

    if ($existingRgd) {
        $db->prepare("
            UPDATE rooms_groups_details SET 
                hostel_name    = :hostel_name,
                campus         = :campus,
                room_type      = :room_type,
                total_beds     = :total_beds,
                occupied_beds  = :occupied_beds,
                available_beds = :available_beds,
                gender         = :gender,
                amount         = IF(:amount > 0, :amount, amount),
                active         = 1,
                group_id       = COALESCE(NULLIF(:group_id, ''), group_id),
                group_name     = COALESCE(NULLIF(:group_name, ''), group_name),
                warden_name    = COALESCE(NULLIF(:warden_name, ''), warden_name),
                warden_user_id = COALESCE(NULLIF(:warden_user_id, ''), warden_user_id),
                warden_bio_id  = COALESCE(NULLIF(:warden_bio_id, ''), warden_bio_id),
                updated_at     = NOW()
            WHERE s_no = :s_no
        ")->execute([
            ':hostel_name'    => $hostelName,
            ':campus'         => $campus,
            ':room_type'      => $roomType,
            ':total_beds'     => $totalBeds,
            ':occupied_beds'  => $currentOccupied,
            ':available_beds' => $availableBeds,
            ':gender'         => $gender,
            ':amount'         => $amount,
            ':group_id'       => $groupId,
            ':group_name'     => $groupName,
            ':warden_name'    => $wardenName,
            ':warden_user_id' => $wardenUserId,
            ':warden_bio_id'  => $wardenBioId,
            ':s_no'           => $existingRgd['s_no']
        ]);
    } else {
        $extRoomId = trim($body['id'] ?? $body['roomId'] ?? $body['room_id'] ?? $body['hostel_room_id'] ?? '');
        if (empty($extRoomId)) {
            $extRoomId = 'RMD-' . strtoupper(substr(md5(uniqid((string)mt_rand(), true)), 0, 16));
        }

        $db->prepare("
            INSERT INTO rooms_groups_details (
                id, hostel_name, campus, room_type, room_number, total_beds,
                occupied_beds, available_beds, gender, active, amount,
                group_id, group_name, warden_name, warden_user_id, warden_bio_id,
                created_at, updated_at
            ) VALUES (
                :id, :hostel_name, :campus, :room_type, :room_number, :total_beds,
                :occupied_beds, :available_beds, :gender, 1, :amount,
                :group_id, :group_name, :warden_name, :warden_user_id, :warden_bio_id,
                NOW(), NOW()
            )
        ")->execute([
            ':id'             => $extRoomId,
            ':hostel_name'    => $hostelName,
            ':campus'         => $campus,
            ':room_type'      => $roomType,
            ':room_number'    => $roomNumber,
            ':total_beds'     => $totalBeds,
            ':occupied_beds'  => $currentOccupied,
            ':available_beds' => $availableBeds,
            ':gender'         => $gender,
            ':amount'         => $amount,
            ':group_id'       => $groupId,
            ':group_name'     => $groupName,
            ':warden_name'    => $wardenName,
            ':warden_user_id' => $wardenUserId,
            ':warden_bio_id'  => $wardenBioId
        ]);
    }

    // 5. Audit Logging
    $db->prepare("
        INSERT INTO audit_logs (username, role, action, module_name, new_value, ip_address) 
        VALUES ('vstudy', 'system', 'WEBHOOK_ADD_ROOM', 'webhook', ?, ?)
    ")->execute([
        json_encode([
            'room'      => $roomNumber,
            'hostel'    => $hostelName,
            'room_type' => $roomType,
            'beds'      => $totalBeds,
            'action'    => $action
        ]),
        $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1'
    ]);

    $db->commit();

    http_response_code(200);
    echo json_encode([
        'success' => true,
        'status'  => 'success',
        'message' => "Room $roomNumber $action successfully.",
        'action'  => $action,
        'data'    => [
            'room_number'    => $roomNumber,
            'room_code'      => $roomCode,
            'hostel_name'    => $hostelName,
            'campus'         => $campus,
            'room_type'      => $roomType,
            'total_beds'     => $totalBeds,
            'occupied_beds'  => $currentOccupied,
            'available_beds' => $availableBeds,
            'gender'         => $gender,
            'warden_name'    => $wardenName,
            'group_id'       => $groupId ?: null,
            'group_name'     => $groupName ?: null
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
