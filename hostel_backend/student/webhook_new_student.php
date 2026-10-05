<?php
/**
 * Webhook Endpoint: Single Student Onboarding / Sync
 *
 * Receives real-time student creation events from VStudy and creates/updates:
 * 1. Student login user account (`users` table)
 * 2. Complete student profile with dynamic Warden mapping (`profile` table)
 * 3. Parent portal credentials & student mapping (`parent_users`, `parent_student_map`)
 * 4. Digital student wallet (`user_wallets`)
 * 5. Physical room occupancy & inventory (`room_master`, `rooms_groups_details`)
 *
 * Security:
 * Requires 'X-API-Key' header or 'Authorization: Bearer <key>'.
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
    // Check headers
    $headers = getallheaders();
    foreach (['X-API-Key', 'X-Api-Key', 'x-api-key', 'X-API-KEY', 'x-client-secret', 'X-Client-Secret', 'X-CLIENT-SECRET'] as $h) {
        if (!empty($headers[$h])) {
            return trim($headers[$h]);
        }
    }
    // Check Authorization: Bearer <token>
    $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    if (preg_match('/Bearer\s+(.*)$/i', $auth, $matches)) {
        return trim($matches[1]);
    }
    // Fallback: check $_SERVER
    if (!empty($_SERVER['HTTP_X_API_KEY'])) {
        return trim($_SERVER['HTTP_X_API_KEY']);
    }
    if (!empty($_SERVER['HTTP_X_CLIENT_SECRET'])) {
        return trim($_SERVER['HTTP_X_CLIENT_SECRET']);
    }
    return '';
}

$providedKey = getProvidedApiKey();
$expectedKey = defined('VSTAAY_API_KEY') ? VSTAAY_API_KEY : '';
$expectedSecret = defined('VSTUDY_CLIENT_SECRET') ? VSTUDY_CLIENT_SECRET : '';

$keyMatches = (!empty($providedKey) && (
    (!empty($expectedKey) && hash_equals($expectedKey, $providedKey)) ||
    (!empty($expectedSecret) && hash_equals($expectedSecret, $providedKey))
));

if (!$keyMatches) {
    http_response_code(401);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Unauthorized: Invalid or missing authentication API key in header.'
    ]);
    exit();
}

// --- 2. PARSE REQUEST BODY ---
$rawInput = file_get_contents('php://input');
$body = json_decode($rawInput, true);

if ((empty($body) || !is_array($body)) && !empty($_POST)) {
    $body = $_POST;
    if (empty($rawInput)) {
        $rawInput = json_encode($_POST);
    }
}

if (empty($body) || !is_array($body)) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Invalid JSON body in request.',
        'debug_raw' => $rawInput,
        'debug_len' => strlen((string)$rawInput),
        'debug_content_type' => $_SERVER['CONTENT_TYPE'] ?? ($_SERVER['HTTP_CONTENT_TYPE'] ?? '')
    ]);
    exit();
}

// Support both flat JSON and nested { "student": { ... }, "room": { ... } } structures
$studentData = $body['student'] ?? $body['data'] ?? $body;
$roomData    = $body['room'] ?? [];
$hostelData  = $body['hostel'] ?? [];

$rollNumber = trim(
    $studentData['registerNumber'] ??
    $studentData['rollNumber'] ??
    $studentData['reg_no'] ??
    $studentData['roll_no'] ??
    $studentData['regNo'] ??
    $body['registerNumber'] ??
    $body['rollNumber'] ??
    $body['reg_no'] ?? ''
);

if (empty($rollNumber)) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Validation Error: Register/Roll number is required.'
    ]);
    exit();
}

$fullName = trim(
    $studentData['name'] ??
    $studentData['student_name'] ??
    $studentData['full_name'] ??
    $body['name'] ?? 'Student'
);

$email = trim(
    $studentData['email'] ??
    $body['email'] ?? ''
);

$phone = trim(
    $studentData['phone'] ??
    $studentData['contact'] ??
    $studentData['personal_phone'] ??
    $studentData['phoneNumber'] ??
    $body['phone'] ?? ''
);

$gender = strtolower(trim(
    $studentData['gender'] ??
    $roomData['gender'] ??
    $body['gender'] ?? ''
));

$hostelName = trim(
    $studentData['hostelName'] ??
    $hostelData['name'] ??
    $body['hostel_name'] ??
    $body['hostelName'] ??
    $body['hostel'] ?? ''
);

$campus = trim(
    $studentData['campus'] ??
    $hostelData['campus'] ??
    $body['campus'] ?? ''
);

$roomNumber = trim(
    $studentData['roomNumber'] ??
    $roomData['roomNumber'] ??
    $body['room_no'] ??
    $body['roomNumber'] ??
    $body['room'] ?? ''
);

$roomType = trim(
    $studentData['roomType'] ??
    $roomData['roomType'] ??
    $body['room_type'] ??
    $body['roomType'] ?? ''
);

// Auto-determine Campus if not provided
if (empty($campus) || $campus === 'SIMATS') {
    if (stripos($hostelName, 'Radiance') !== false || stripos($hostelName, 'Stunner') !== false || strpos($roomNumber, 'P-') === 0 || strpos($roomNumber, 'P0') === 0) {
        $campus = 'Poonamallee Campus';
    } else {
        $campus = 'Thandalam Campus';
    }
}

// Auto-determine Hostel Type (Boys/Girls)
$hostelType = ($gender === 'female' || stripos($hostelName, 'girls') !== false || stripos($hostelName, 'ponni') !== false || stripos($hostelName, 'vaigai') !== false || stripos($hostelName, 'siruvani') !== false) ? 'Girls' : 'Boys';

// Extract Parent details (supports flat or VStudy parents array)
$parentsList = $studentData['parents'] ?? $body['parents'] ?? [];
$firstParent = (is_array($parentsList) && !empty($parentsList[0]) && is_array($parentsList[0])) ? $parentsList[0] : [];
$parentPhone = trim(
    $body['parentPhone'] ??
    $body['parent_phone'] ??
    $firstParent['phone'] ??
    $firstParent['contact'] ??
    ''
);
$parentName = trim(
    $body['parentName'] ??
    $body['parent_name'] ??
    $firstParent['name'] ??
    ''
);
$parentEmail = trim(
    $body['parentEmail'] ??
    $body['parent_email'] ??
    $firstParent['email'] ??
    ''
);
$parentRelation = trim(
    $body['parentRelation'] ??
    $body['parent_relation'] ??
    $body['relation'] ??
    $firstParent['relation'] ??
    'Parent'
);

// Parse Dates gracefully (support ISO, d.m.Y, d-m-Y, Y-m-d)
function parseDateGracefully($str, $fallback = null) {
    if (empty($str)) return $fallback;
    $s = trim($str);
    // Replace dots with hyphens if DD.MM.YYYY
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
$bookedRaw = $studentData['bookedAt'] ?? $studentData['paidAt'] ?? $body['check_in_date'] ?? $body['bookedAt'] ?? $today;
$checkInDate = parseDateGracefully($bookedRaw, $today);

$renewalRaw = $studentData['renewalDate'] ?? $studentData['renewal_date'] ?? $body['renewal_date'] ?? $body['renewalDate'] ?? '';
$calcRenewal = parseDateGracefully($renewalRaw, null);

$remainingDays = $calcRenewal ? max(0, (int)floor((strtotime($calcRenewal) - strtotime($today)) / 86400)) : null;

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    // Ensure dedicated sync table exists outside transaction (DDL causes implicit commit)
    $db->exec("
        CREATE TABLE IF NOT EXISTS vstudy_new_student_syncs (
            id INT AUTO_INCREMENT PRIMARY KEY,
            roll_number VARCHAR(100) NOT NULL,
            student_name VARCHAR(150) NULL,
            email VARCHAR(150) NULL,
            phone VARCHAR(50) NULL,
            gender VARCHAR(20) NULL,
            campus VARCHAR(100) NULL,
            hostel_name VARCHAR(150) NULL,
            room_number VARCHAR(50) NULL,
            room_type VARCHAR(100) NULL,
            action_type ENUM('CREATED', 'UPDATED') DEFAULT 'CREATED',
            status VARCHAR(50) DEFAULT 'SUCCESS',
            request_payload LONGTEXT NULL,
            response_payload LONGTEXT NULL,
            ip_address VARCHAR(50) NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_roll_number (roll_number),
            INDEX idx_status (status),
            INDEX idx_created_at (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ");

    $db->beginTransaction();

    // --- 3. UPSERT USER ACCOUNT (`users`) ---
    $userStmt = $db->prepare("SELECT id FROM users WHERE username = ? LIMIT 1");
    $userStmt->execute([$rollNumber]);
    $existingUser = $userStmt->fetch(PDO::FETCH_ASSOC);

    $isNewUser = empty($existingUser);
    $userId = $existingUser['id'] ?? null;
    $pwHash = password_hash('welcome123', PASSWORD_BCRYPT);

    if ($isNewUser) {
        $insUser = $db->prepare("
            INSERT INTO users (
                username, full_name, email, phone_number, role, password, Campus, Institution,
                HostelName, HostelType, RoomType, RoomId, Status, is_active,
                ParentContact, ParentName
            ) VALUES (
                :username, :full_name, :email, :phone_number, 'student', :password, :Campus, 'SIMATS',
                :HostelName, :HostelType, :RoomType, :RoomId, '1', 1,
                :ParentContact, :ParentName
            )
        ");
        $insUser->execute([
            ':username'      => $rollNumber,
            ':full_name'     => $fullName,
            ':email'         => $email,
            ':phone_number'  => $phone,
            ':password'      => $pwHash,
            ':Campus'        => $campus,
            ':HostelName'    => $hostelName,
            ':HostelType'    => $hostelType,
            ':RoomType'      => $roomType,
            ':RoomId'        => $roomNumber,
            ':ParentContact' => $parentPhone,
            ':ParentName'    => $parentName
        ]);
        $userId = $db->lastInsertId();
    } else {
        // Update details while respecting existing email overrides
        $updUser = $db->prepare("
            UPDATE users SET 
                full_name = :full_name,
                phone_number = COALESCE(NULLIF(:phone, ''), phone_number),
                Campus = :Campus, 
                HostelName = :HostelName, 
                HostelType = :HostelType, 
                RoomType = :RoomType, 
                RoomId = :RoomId,
                ParentContact = COALESCE(NULLIF(:ParentContact, ''), ParentContact),
                ParentName = COALESCE(NULLIF(:ParentName, ''), ParentName)
            WHERE username = :username AND role = 'student'
        ");
        $updUser->execute([
            ':full_name'     => $fullName,
            ':phone'         => $phone,
            ':Campus'        => $campus,
            ':HostelName'    => $hostelName,
            ':HostelType'    => $hostelType,
            ':RoomType'      => $roomType,
            ':RoomId'        => $roomNumber,
            ':ParentContact' => $parentPhone,
            ':ParentName'    => $parentName,
            ':username'      => $rollNumber
        ]);
    }

    // --- 4. DYNAMIC WARDEN MAPPING ---
    $assignedWarden = null;
    if (!empty($roomNumber)) {
        $wardenStmt = $db->prepare("
            SELECT warden_name FROM rooms_groups_details 
            WHERE (room_number = :rn OR REPLACE(REPLACE(TRIM(room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(:rn2), ' ', ''), '-', ''))
              AND warden_name IS NOT NULL AND warden_name != '' LIMIT 1
        ");
        $wardenStmt->execute([':rn' => $roomNumber, ':rn2' => $roomNumber]);
        $assignedWarden = $wardenStmt->fetchColumn() ?: null;
    }

    if (!$assignedWarden && !empty($hostelName)) {
        $staffStmt = $db->prepare("
            SELECT name FROM mapping_staff 
            WHERE LOWER(role) = 'warden' AND (LOWER(hostel_name) = LOWER(:hn) OR LOWER(:hn2) LIKE CONCAT('%', LOWER(hostel_name), '%')) LIMIT 1
        ");
        $staffStmt->execute([':hn' => $hostelName, ':hn2' => $hostelName]);
        $assignedWarden = $staffStmt->fetchColumn() ?: null;
    }

    // --- 5. UPSERT PROFILE (`profile`) ---
    $insProfile = $db->prepare("
        INSERT INTO profile (
            full_name, reg_no, user_id, email, personal_phone, room_allocation, warden,
            institution, hostel_name, address, renewal_date, remaining_days,
            check_in_date, valid_from, valid_to
        ) VALUES (
            :full_name, :reg_no, :user_id, :email, :personal_phone, :room_allocation, :warden,
            'SIMATS', :hostel_name, :address, :renewal_date, :remaining_days,
            :check_in_date, :valid_from, :valid_to
        ) ON DUPLICATE KEY UPDATE 
            full_name = VALUES(full_name),
            email = COALESCE(NULLIF(profile.email, ''), VALUES(email)),
            personal_phone = COALESCE(NULLIF(VALUES(personal_phone), ''), profile.personal_phone),
            room_allocation = VALUES(room_allocation),
            warden = COALESCE(NULLIF(VALUES(warden), ''), profile.warden),
            hostel_name = VALUES(hostel_name),
            renewal_date = VALUES(renewal_date),
            valid_to = VALUES(valid_to),
            check_in_date = VALUES(check_in_date),
            valid_from = VALUES(valid_from),
            remaining_days = VALUES(remaining_days)
    ");
    $insProfile->execute([
        ':full_name'       => $fullName,
        ':reg_no'          => $rollNumber,
        ':user_id'         => $userId,
        ':email'           => $email,
        ':personal_phone'  => $phone,
        ':room_allocation' => $roomNumber,
        ':warden'          => $assignedWarden,
        ':hostel_name'     => $hostelName,
        ':address'         => $campus . ', Chennai',
        ':renewal_date'   => $calcRenewal,
        ':remaining_days' => $remainingDays,
        ':check_in_date'   => $checkInDate,
        ':valid_from'      => $checkInDate,
        ':valid_to'        => $calcRenewal
    ]);

    // --- 6. PARENT ACCOUNT PROVISIONING ---
    $parentId = "P_" . $rollNumber;
    $parentContact = !empty($parentPhone) ? $parentPhone : $phone;
    $db->prepare("
        INSERT INTO parent_users (parent_id, email, name, password, contact) 
        VALUES (?, ?, ?, ?, ?) 
        ON DUPLICATE KEY UPDATE 
            email = COALESCE(NULLIF(VALUES(email), ''), email),
            name = COALESCE(NULLIF(VALUES(name), ''), name),
            contact = COALESCE(NULLIF(VALUES(contact), ''), contact)
    ")->execute([$parentId, $parentEmail, $parentName, $pwHash, $parentContact]);

    $db->prepare("
        INSERT INTO parent_student_map (parent_id, student_id) 
        VALUES (?, ?) 
        ON DUPLICATE KEY UPDATE 
            parent_id = VALUES(parent_id)
    ")->execute([$parentId, $rollNumber]);

    // --- 7. USER WALLET PROVISIONING ---
    $walletId = null;
    if (!empty($email)) {
        $wCheck = $db->prepare("SELECT id FROM user_wallets WHERE LOWER(email) = LOWER(?) LIMIT 1");
        $wCheck->execute([$email]);
        $walletId = $wCheck->fetchColumn();

        if (!$walletId) {
            $db->prepare("INSERT INTO user_wallets (email, balance) VALUES (?, 0.00)")->execute([$email]);
            $walletId = $db->lastInsertId();
        }
    }

    // --- 8. ROOM INVENTORY / OCCUPANCY ADJUSTMENT ---
    if (!empty($roomNumber)) {
        // Count actual occupants
        $occStmt = $db->prepare("SELECT COUNT(*) FROM profile WHERE room_allocation = ?");
        $occStmt->execute([$roomNumber]);
        $actualOccupancy = (int)$occStmt->fetchColumn();

        // Update room_master
        $db->prepare("
            UPDATE room_master 
            SET occupied_beds = ?, 
                available_beds = GREATEST(0, total_beds - ?) 
            WHERE room_no = ? OR room_code = ?
        ")->execute([$actualOccupancy, $actualOccupancy, $roomNumber, $roomNumber]);

        // Update rooms_groups_details
        $db->prepare("
            UPDATE rooms_groups_details 
            SET occupied_beds = ?, 
                available_beds = GREATEST(0, total_beds - ?) 
            WHERE room_number = ?
        ")->execute([$actualOccupancy, $actualOccupancy, $roomNumber]);
    }

    // --- 9. AUDIT LOGGING ---
    $db->prepare("
        INSERT INTO audit_logs (username, role, action, module_name, new_value, ip_address) 
        VALUES (?, 'system', 'WEBHOOK_NEW_STUDENT', 'webhook', ?, ?)
    ")->execute([
        $rollNumber,
        json_encode([
            'roll' => $rollNumber,
            'name' => $fullName,
            'hostel' => $hostelName,
            'room' => $roomNumber,
            'action' => $isNewUser ? 'created' : 'updated'
        ]),
        $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1'
    ]);

    // --- 10. RECORD IN DEDICATED vstudy_new_student_syncs TABLE ---
    try {
        $insSyncStmt = $db->prepare("
            INSERT INTO vstudy_new_student_syncs (
                roll_number, student_name, email, phone, gender, campus,
                hostel_name, room_number, room_type, action_type, status,
                request_payload, response_payload, ip_address
            ) VALUES (
                ?, ?, ?, ?, ?, ?,
                ?, ?, ?, ?, 'SUCCESS',
                ?, ?, ?
            )
        ");
        $respPayload = json_encode([
            'success'         => true,
            'action'          => $isNewUser ? 'created' : 'updated',
            'user_id'         => (int)$userId,
            'warden_assigned' => $assignedWarden
        ]);
        $insSyncStmt->execute([
            $rollNumber, $fullName, $email, $phone, $gender, $campus,
            $hostelName, $roomNumber, $roomType, $isNewUser ? 'CREATED' : 'UPDATED',
            $rawInput, $respPayload, $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1'
        ]);
    } catch (Exception $eSync) {
        error_log("Failed to log to vstudy_new_student_syncs: " . $eSync->getMessage());
    }

    if ($db->inTransaction()) {
        $db->commit();
    }

    http_response_code(200);
    echo json_encode([
        'success' => true,
        'status'  => 'success',
        'message' => $isNewUser ? 'Student onboarded successfully.' : 'Student profile updated successfully.',
        'action'  => $isNewUser ? 'created' : 'updated',
        'data'    => [
            'user_id'         => (int)$userId,
            'roll_number'     => $rollNumber,
            'full_name'       => $fullName,
            'email'           => $email,
            'hostel_name'     => $hostelName,
            'room_number'     => $roomNumber,
            'room_type'       => $roomType,
            'warden_assigned' => $assignedWarden,
            'check_in_date'   => $checkInDate,
            'renewal_date'    => $calcRenewal,
            'parent_id'       => $parentId,
            'parent_name'     => $parentName,
            'parent_relation' => $parentRelation,
            'parent_contact'  => $parentContact,
            'wallet_id'       => $walletId ? (int)$walletId : null
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
