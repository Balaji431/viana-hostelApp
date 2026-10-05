<?php
/**
 * Webhook Endpoint: Temporary Stay Allocation & Booking
 *
 * Real-time event from VStudy when a guest/temporary student stay is booked.
 * Updates:
 * 1. `temporary_stay_requests` table (allocated & confirmed booking)
 * 2. `room_master` & `rooms_groups_details` (inventory adjustment)
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

$fullName = trim(
    $body['name'] ??
    $body['fullName'] ??
    $body['full_name'] ?? ''
);

$email = trim(
    $body['email'] ?? ''
);

$phone = trim(
    $body['phone'] ??
    $body['contact'] ??
    $body['mobile'] ?? ''
);

$gender = trim(
    $body['gender'] ?? 'Male'
);

$hostelName = trim(
    $body['hostelName'] ??
    $body['hostel_name'] ?? ''
);

$roomNumber = trim(
    $body['roomNumber'] ??
    $body['room_no'] ??
    $body['room_number'] ?? ''
);

$roomType = trim(
    $body['roomType'] ??
    $body['room_type'] ?? ''
);

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
$fromDate = parseDateGracefully($body['fromDate'] ?? $body['from_date'] ?? $body['checkIn'] ?? $today, $today);
$toDate   = parseDateGracefully($body['toDate'] ?? $body['to_date'] ?? $body['checkOut'] ?? null, null);

if (empty($fullName)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'status' => 'error', 'message' => 'Missing required field: name / fullName']);
    exit();
}

if (empty($email)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'status' => 'error', 'message' => 'Missing required field: email']);
    exit();
}

if (empty($hostelName)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'status' => 'error', 'message' => 'Missing required field: hostelName']);
    exit();
}

if (empty($roomNumber)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'status' => 'error', 'message' => 'Missing required field: roomNumber']);
    exit();
}

if (empty($toDate)) {
    // Default 7 days if toDate is omitted
    $toDate = date('Y-m-d', strtotime('+7 days', strtotime($fromDate)));
}

$durationValue = max(1, (int)round((strtotime($toDate) - strtotime($fromDate)) / 86400));
$durationType  = 'days';
$amount        = isset($body['amount']) ? (float)$body['amount'] : 0.00;
$paymentStatus = trim($body['paymentStatus'] ?? $body['payment_status'] ?? 'paid');
$paymentTxnId  = trim($body['paymentTxnId'] ?? $body['txn_id'] ?? $body['transaction_id'] ?? ('TXN-TEMP-' . strtoupper(substr(md5(uniqid()), 0, 8))));
$purpose       = trim($body['purpose'] ?? $body['institution_purpose'] ?? 'Temporary Stay via VStudy');
$docType       = trim($body['docType'] ?? $body['doc_type'] ?? 'ID Proof');
$docNumber     = trim($body['docNumber'] ?? $body['doc_number'] ?? '');

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $db->beginTransaction();

    // 1. Dynamic Warden mapping
    $wardenName = null;
    $wardenId   = null;
    $wardenBioId = null;

    $wStmt = $db->prepare("
        SELECT warden_name, warden_user_id, warden_bio_id 
        FROM rooms_groups_details 
        WHERE room_number = :rn OR REPLACE(REPLACE(TRIM(room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(:rn2), ' ', ''), '-', '')
        LIMIT 1
    ");
    $wStmt->execute([':rn' => $roomNumber, ':rn2' => $roomNumber]);
    $wRow = $wStmt->fetch(PDO::FETCH_ASSOC);

    if ($wRow) {
        $wardenName  = $wRow['warden_name'];
        $wardenId    = $wRow['warden_user_id'];
        $wardenBioId = $wRow['warden_bio_id'];
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

    // 2. Generate unique request_id
    $requestId = 'TEMP-' . strtoupper(substr(md5(uniqid((string)mt_rand(), true)), 0, 8));

    // 3. Insert into `temporary_stay_requests`
    $insStmt = $db->prepare("
        INSERT INTO temporary_stay_requests (
            request_id, full_name, email, phone, gender,
            institution_purpose, doc_type, doc_number,
            hostel_name, room_type, room_no, room_code,
            from_date, to_date, duration_type, duration_value,
            amount, annual_fee, status, payment_status, payment_txn_id,
            warden_name, warden_id, warden_bio_id,
            hold_status, admin_notes, created_at, updated_at
        ) VALUES (
            :request_id, :full_name, :email, :phone, :gender,
            :institution_purpose, :doc_type, :doc_number,
            :hostel_name, :room_type, :room_no, :room_code,
            :from_date, :to_date, :duration_type, :duration_value,
            :amount, :annual_fee, 'allocated', :payment_status, :payment_txn_id,
            :warden_name, :warden_id, :warden_bio_id,
            'confirmed', 'Allocated via VStudy real-time webhook', NOW(), NOW()
        )
    ");

    $insStmt->execute([
        ':request_id'          => $requestId,
        ':full_name'           => $fullName,
        ':email'               => $email,
        ':phone'               => $phone,
        ':gender'              => $gender,
        ':institution_purpose' => $purpose,
        ':doc_type'            => $docType,
        ':doc_number'          => $docNumber,
        ':hostel_name'         => $hostelName,
        ':room_type'           => $roomType,
        ':room_no'             => $roomNumber,
        ':room_code'           => $roomNumber,
        ':from_date'           => $fromDate,
        ':to_date'             => $toDate,
        ':duration_type'       => $durationType,
        ':duration_value'      => $durationValue,
        ':amount'              => $amount,
        ':annual_fee'          => $amount,
        ':payment_status'      => $paymentStatus,
        ':payment_txn_id'      => $paymentTxnId,
        ':warden_name'         => $wardenName,
        ':warden_id'           => $wardenId,
        ':warden_bio_id'       => $wardenBioId
    ]);

    // 4. Update room occupancy if payment is complete
    if ($paymentStatus === 'paid') {
        $db->prepare("
            UPDATE room_master 
            SET occupied_beds = occupied_beds + 1,
                available_beds = GREATEST(0, available_beds - 1)
            WHERE room_no = ? OR room_code = ?
        ")->execute([$roomNumber, $roomNumber]);

        $db->prepare("
            UPDATE rooms_groups_details 
            SET occupied_beds = occupied_beds + 1,
                available_beds = GREATEST(0, available_beds - 1)
            WHERE room_number = ?
        ")->execute([$roomNumber]);
    }

    // 5. Audit Logging
    $db->prepare("
        INSERT INTO audit_logs (username, role, action, module_name, new_value, ip_address) 
        VALUES (?, 'system', 'WEBHOOK_TEMPORARY_STAY', 'webhook', ?, ?)
    ")->execute([
        $email,
        json_encode([
            'request_id' => $requestId,
            'name'       => $fullName,
            'room'       => $roomNumber,
            'from'       => $fromDate,
            'to'         => $toDate,
            'amount'     => $amount
        ]),
        $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1'
    ]);

    $db->commit();

    http_response_code(200);
    echo json_encode([
        'success' => true,
        'status'  => 'success',
        'message' => "Temporary stay allocated successfully for $fullName in Room $roomNumber.",
        'data'    => [
            'request_id'      => $requestId,
            'name'            => $fullName,
            'email'           => $email,
            'phone'           => $phone,
            'hostel_name'     => $hostelName,
            'room_number'     => $roomNumber,
            'room_type'       => $roomType,
            'from_date'       => $fromDate,
            'to_date'         => $toDate,
            'duration_days'   => $durationValue,
            'amount'          => $amount,
            'payment_status'  => $paymentStatus,
            'payment_txn_id'  => $paymentTxnId,
            'warden_assigned' => $wardenName
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
