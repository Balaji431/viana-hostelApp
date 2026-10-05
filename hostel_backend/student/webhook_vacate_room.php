<?php
/**
 * Webhook Endpoint: Vacate Room & Lock Early Vacated Bed
 *
 * Real-time event from VStudy when a student completes their work and vacates the hostel early.
 * If the student's due date / renewal date has days remaining (e.g. 20 days remaining):
 * 1. The student is checked out and deallocated (`checkout_students`, `users.is_active = 0`, `profile.room_allocation = 'vacated'`)
 * 2. The room/bed is preserved as LOCKED and EMPTY until the due date expires (`vacated_room_locks`)
 * 3. `room_master` & `rooms_groups_details` inventory reflects the lock so nobody else can take that bed.
 * 4. Logged to `audit_logs`
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

if (empty($rollNumber)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Missing required field: rollNumber / registerNumber'
    ]);
    exit();
}

function parseDateGracefully($str, $fallback = null) {
    if (empty($str)) return $fallback;
    $s = trim($str);
    if (preg_match('/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/', $s, $m)) {
        return sprintf('%04d-%02d-%02d', (int)$m[3], (int)$m[2], (int)$m[1]);
    }
    $ts = strtotime($s);
    if ($ts !== false) {
        return date('Y-m-d', $ts);
    }
    return $fallback;
}

$today = date('Y-m-d');
$vacatedDate = parseDateGracefully($body['vacatedDate'] ?? $body['vacate_date'] ?? $body['checkOutDate'] ?? $today, $today);
$conduct     = trim($body['conduct'] ?? 'Good');
$remarks     = trim($body['reason'] ?? $body['remarks'] ?? 'Early vacate - Room locked until tenure expiry');

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    // Ensure vacated_room_locks table exists
    $db->exec("
        CREATE TABLE IF NOT EXISTS vacated_room_locks (
            id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            student_reg_no VARCHAR(50) NOT NULL,
            student_name VARCHAR(255) DEFAULT NULL,
            hostel_name VARCHAR(150) DEFAULT NULL,
            room_number VARCHAR(50) NOT NULL,
            vacated_date DATE NOT NULL,
            locked_until DATE NOT NULL,
            remaining_days INT DEFAULT 0,
            status ENUM('locked','released','expired') DEFAULT 'locked',
            reason TEXT,
            created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY uniq_student_room (student_reg_no, room_number),
            KEY idx_room_status (room_number, status, locked_until)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");

    $db->beginTransaction();

    // 1. Fetch student user and profile details
    $userStmt = $db->prepare("SELECT * FROM users WHERE username = ? LIMIT 1");
    $userStmt->execute([$rollNumber]);
    $userRow = $userStmt->fetch(PDO::FETCH_ASSOC);

    $profStmt = $db->prepare("SELECT * FROM profile WHERE reg_no = ? LIMIT 1");
    $profStmt->execute([$rollNumber]);
    $profRow = $profStmt->fetch(PDO::FETCH_ASSOC);

    if (!$userRow && !$profRow) {
        $db->rollBack();
        http_response_code(404);
        echo json_encode([
            'success' => false,
            'status'  => 'error',
            'message' => "Student with rollNumber '$rollNumber' not found in database."
        ]);
        exit();
    }

    $studentId   = $userRow['id'] ?? ($profRow['user_id'] ?? 0);
    $fullName    = $profRow['full_name'] ?? ($userRow['full_name'] ?? 'Student');
    $hostelName  = $profRow['hostel_name'] ?? ($userRow['HostelName'] ?? '');
    $roomNumber  = trim($body['roomNumber'] ?? $body['room_no'] ?? ($profRow['room_allocation'] ?? ($userRow['RoomId'] ?? '')));
    
    // 2. Determine Due Date & Locked Period
    $studentDueDate = $profRow['renewal_date'] ?? ($profRow['valid_to'] ?? $vacatedDate);
    $rawLockDate = $body['lockedUntil'] ?? $body['due_date'] ?? $body['valid_to'] ?? $studentDueDate;
    $lockedUntil = parseDateGracefully($rawLockDate, $studentDueDate);

    // Calculate days between vacate date and due date
    $remainingDays = max(0, (int)round((strtotime($lockedUntil) - strtotime($vacatedDate)) / 86400));
    $isRoomLocked = ($remainingDays > 0);

    // 3. Record in `checkout_students`
    $insCheckout = $db->prepare("
        INSERT INTO checkout_students (
            student_id, reg_no, full_name, hostel_name, room_code,
            conduct, conduct_remarks, checked_out_at, checked_out_by,
            profile_data, user_data
        ) VALUES (
            :student_id, :reg_no, :full_name, :hostel_name, :room_code,
            :conduct, :conduct_remarks, NOW(), 'VStudy Webhook',
            :profile_data, :user_data
        )
    ");
    $insCheckout->execute([
        ':student_id'       => $studentId,
        ':reg_no'           => $rollNumber,
        ':full_name'        => $fullName,
        ':hostel_name'      => $hostelName,
        ':room_code'        => $roomNumber,
        ':conduct'          => $conduct,
        ':conduct_remarks'  => $remarks . " (Locked until $lockedUntil, $remainingDays days left)",
        ':profile_data'     => json_encode($profRow),
        ':user_data'        => json_encode($userRow)
    ]);

    // 4. Update student profile and user status (mark inactive & vacated)
    $db->prepare("
        UPDATE profile SET 
            room_allocation = 'vacated',
            valid_to        = :vacated_date,
            remaining_days  = 0
        WHERE reg_no = :rollNumber
    ")->execute([
        ':vacated_date' => $vacatedDate,
        ':rollNumber'   => $rollNumber
    ]);

    $db->prepare("
        UPDATE users SET 
            Status    = '0',
            is_active = 0,
            RoomId    = 'vacated'
        WHERE username = :rollNumber
    ")->execute([
        ':rollNumber' => $rollNumber
    ]);

    // 5. Room Lock Management
    if (!empty($roomNumber) && $roomNumber !== 'vacated' && $roomNumber !== 'unallocated') {
        if ($isRoomLocked) {
            // Bed remains locked and empty until due date
            $db->prepare("
                INSERT INTO vacated_room_locks (
                    student_reg_no, student_name, hostel_name, room_number,
                    vacated_date, locked_until, remaining_days, status, reason
                ) VALUES (
                    :student_reg_no, :student_name, :hostel_name, :room_number,
                    :vacated_date, :locked_until, :remaining_days, 'locked', :reason
                ) ON DUPLICATE KEY UPDATE 
                    locked_until   = VALUES(locked_until),
                    remaining_days = VALUES(remaining_days),
                    status         = 'locked'
            ")->execute([
                ':student_reg_no' => $rollNumber,
                ':student_name'   => $fullName,
                ':hostel_name'    => $hostelName,
                ':room_number'    => $roomNumber,
                ':vacated_date'   => $vacatedDate,
                ':locked_until'   => $lockedUntil,
                ':remaining_days' => $remainingDays,
                ':reason'         => $remarks
            ]);

            // Count actual occupants in profile (excluding vacated)
            $occStmt = $db->prepare("SELECT COUNT(*) FROM profile WHERE room_allocation = ? AND room_allocation != 'vacated'");
            $occStmt->execute([$roomNumber]);
            $actualOccupants = (int)$occStmt->fetchColumn();

            // Count locked beds for this room
            $lockStmt = $db->prepare("SELECT COUNT(*) FROM vacated_room_locks WHERE room_number = ? AND status = 'locked' AND locked_until >= CURDATE()");
            $lockStmt->execute([$roomNumber]);
            $lockedBeds = (int)$lockStmt->fetchColumn();

            // Total unavailable beds = actual occupants + locked beds
            $totalBlocked = $actualOccupants + $lockedBeds;

            // In room_master: available_beds is reduced by locked bed, assigned_pending tracks the lock
            $db->prepare("
                UPDATE room_master 
                SET occupied_beds    = ?, 
                    assigned_pending = ?,
                    available_beds   = GREATEST(0, total_beds - ?) 
                WHERE room_no = ? OR room_code = ?
            ")->execute([$actualOccupants, $lockedBeds, $totalBlocked, $roomNumber, $roomNumber]);

            // In rooms_groups_details
            $db->prepare("
                UPDATE rooms_groups_details 
                SET occupied_beds    = ?, 
                    assigned_pending = ?,
                    available_beds   = GREATEST(0, total_beds - ?) 
                WHERE room_number = ?
            ")->execute([$actualOccupants, $lockedBeds, $totalBlocked, $roomNumber]);

        } else {
            // Normal vacate (due date is reached/passed) -> Bed becomes completely available immediately
            $occStmt = $db->prepare("SELECT COUNT(*) FROM profile WHERE room_allocation = ? AND room_allocation != 'vacated'");
            $occStmt->execute([$roomNumber]);
            $actualOccupants = (int)$occStmt->fetchColumn();

            $db->prepare("
                UPDATE room_master 
                SET occupied_beds  = ?, 
                    available_beds = GREATEST(0, total_beds - ?) 
                WHERE room_no = ? OR room_code = ?
            ")->execute([$actualOccupants, $actualOccupants, $roomNumber, $roomNumber]);

            $db->prepare("
                UPDATE rooms_groups_details 
                SET occupied_beds  = ?, 
                    available_beds = GREATEST(0, total_beds - ?) 
                WHERE room_number = ?
            ")->execute([$actualOccupants, $actualOccupants, $roomNumber]);
        }
    }

    // 6. Audit Logging
    $db->prepare("
        INSERT INTO audit_logs (username, role, action, module_name, new_value, ip_address) 
        VALUES (?, 'system', 'WEBHOOK_VACATE_ROOM', 'webhook', ?, ?)
    ")->execute([
        $rollNumber,
        json_encode([
            'room'           => $roomNumber,
            'hostel'         => $hostelName,
            'vacated_date'   => $vacatedDate,
            'locked_until'   => $lockedUntil,
            'locked_days'    => $remainingDays,
            'room_locked'    => $isRoomLocked
        ]),
        $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1'
    ]);

    $db->commit();

    http_response_code(200);
    echo json_encode([
        'success' => true,
        'status'  => 'success',
        'message' => $isRoomLocked 
            ? "Student $fullName vacated. Room $roomNumber is LOCKED & EMPTY until $lockedUntil ($remainingDays days remaining)."
            : "Student $fullName vacated. Room $roomNumber is now available.",
        'data'    => [
            'roll_number'     => $rollNumber,
            'student_name'    => $fullName,
            'hostel_name'     => $hostelName,
            'room_number'     => $roomNumber,
            'vacated_date'    => $vacatedDate,
            'locked_until'    => $lockedUntil,
            'locked_days'     => $remainingDays,
            'room_status'     => $isRoomLocked ? 'locked_and_empty' : 'available',
            'student_status'  => 'vacated'
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
