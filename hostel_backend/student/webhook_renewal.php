<?php
/**
 * Webhook Endpoint: Student Hostel Renewal
 *
 * Real-time event from VStudy when a student renews their hostel stay / pays renewal fee.
 * Updates:
 * 1. `profile` table (renewal_date, valid_to, remaining_days)
 * 2. `renewal_requests` table (approved renewal record)
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

$rawDate = $body['renewalDate'] ?? $body['newRenewalDate'] ?? $body['renewal_date'] ?? $body['valid_to'] ?? '';
$passedRenewal = parseDateGracefully($rawDate, null);
$amount = isset($body['amount']) ? (float)$body['amount'] : null;
$txnId = trim($body['paymentTxnId'] ?? $body['transaction_id'] ?? $body['txn_id'] ?? '');
$reason = trim($body['reason'] ?? $body['remarks'] ?? 'Renewed via VStudy webhook');

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
        $db->rollBack();
        http_response_code(404);
        echo json_encode([
            'success' => false,
            'status'  => 'error',
            'message' => "Student with rollNumber '$rollNumber' not found in database."
        ]);
        exit();
    }

    $today = date('Y-m-d');
    $oldRenewal = $currentProfile['renewal_date'] ?? ($currentProfile['valid_to'] ?? '');

    // Strict Renewal Deadline: Must be renewed on or before renewal due date at 11:59:59 PM
    if (!empty($oldRenewal)) {
        $deadlineTs = strtotime($oldRenewal . ' 23:59:59');
        if (time() > $deadlineTs) {
            $db->rollBack();
            http_response_code(422);
            echo json_encode([
                'success' => false,
                'status'  => 'error',
                'message' => "Renewal deadline expired on " . date('d M Y', strtotime($oldRenewal)) . " at 11:59 PM. Room renewal is strictly not permitted after expiration. The room has been released for new bookings. The student must apply freshly as a new student via the VStudy portal."
            ]);
            exit();
        }
    }

    // Extend 1 year from existing renewal date (or explicitly provided date)
    if ($passedRenewal) {
        $newRenewal = $passedRenewal;
    } else {
        $baseDate = !empty($oldRenewal) ? $oldRenewal : $today;
        $newRenewal = date('Y-m-d', strtotime('+1 year', strtotime($baseDate)));
    }

    $remainingDays = max(0, (int)floor((strtotime($newRenewal) - strtotime($today)) / 86400));
    $userId = (int)($currentProfile['user_id'] ?? 0);
    if ($userId === 0) {
        $uStmt = $db->prepare("SELECT id FROM users WHERE username = ? LIMIT 1");
        $uStmt->execute([$rollNumber]);
        $userId = (int)($uStmt->fetchColumn() ?: 0);
    }
    if ($userId === 0) {
        $userId = (int)($currentProfile['id'] ?? 1);
    }
    $studentName = $currentProfile['full_name'] ?? 'Student';
    $roomNumber = $currentProfile['room_allocation'] ?? '';

    // 2. Update `profile`
    $updProfile = $db->prepare("
        UPDATE profile SET 
            renewal_date   = :renewal_date,
            valid_to       = :valid_to,
            remaining_days = :remaining_days
        WHERE reg_no = :rollNumber
    ");
    $updProfile->execute([
        ':renewal_date'   => $newRenewal,
        ':valid_to'       => $newRenewal,
        ':remaining_days' => $remainingDays,
        ':rollNumber'     => $rollNumber
    ]);

    // Update `users` table DOL and ensure active
    $db->prepare("
        UPDATE users SET 
            DOL = ?,
            Status = '1',
            is_active = 1
        WHERE username = ? OR id = ?
    ")->execute([$newRenewal, $rollNumber, $userId]);

    // Update `vstudy_payments` table for ERP accounting records
    $db->prepare("
        UPDATE vstudy_payments SET 
            renewal_date = ?, 
            remaining_days = ?,
            paid_amount = IF(? > 0, ?, paid_amount)
        WHERE roll_number = ?
    ")->execute([$newRenewal, $remainingDays, (float)$amount, (float)$amount, $rollNumber]);

    // 3. Record in `renewal_requests`
    $insRen = $db->prepare("
        INSERT INTO renewal_requests (
            student_id, student_name, student_reg_no, room_number,
            reason, status, requested_at, processed_by, processed_by_name,
            processed_at, remarks
        ) VALUES (
            :student_id, :student_name, :student_reg_no, :room_number,
            :reason, 'approved', NOW(), 1, 'VStudy Webhook',
            NOW(), :remarks
        )
    ");
    $insRen->execute([
        ':student_id'     => $userId,
        ':student_name'   => $studentName,
        ':student_reg_no' => $rollNumber,
        ':room_number'    => $roomNumber,
        ':reason'         => $reason,
        ':remarks'        => $txnId ? "Transaction ID: $txnId | Amount: $amount" : "Tenure extended to $newRenewal"
    ]);

    // 4. Record into `vstudy_renewal_syncs` table
    try {
        if (!function_exists('generateUuidV4')) {
            function generateUuidV4() {
                $data = random_bytes(16);
                $data[6] = chr(ord($data[6]) & 0x0f | 0x40);
                $data[8] = chr(ord($data[8]) & 0x3f | 0x80);
                return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
            }
        }
        $vEventId = (preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', (string)$txnId)) ? $txnId : generateUuidV4();
        $insSync = $db->prepare("
            INSERT INTO vstudy_renewal_syncs (
                external_event_id, roll_number, student_name,
                amount, previous_renewal_date, new_renewal_date,
                status, sync_status, request_payload
            ) VALUES (?, ?, ?, ?, ?, ?, 'PAID', 'inbound_synced', ?)
            ON DUPLICATE KEY UPDATE 
                new_renewal_date = VALUES(new_renewal_date),
                status = VALUES(status),
                sync_status = 'inbound_synced'
        ");
        $insSync->execute([
            $vEventId,
            $rollNumber,
            $studentName,
            (float)($amount ?? 0),
            !empty($oldRenewal) ? $oldRenewal : null,
            $newRenewal,
            $rawBody
        ]);
    } catch (Exception $ign) {}

    // 5. Audit Logging
    $db->prepare("
        INSERT INTO audit_logs (username, role, action, module_name, old_value, new_value, ip_address) 
        VALUES (?, 'system', 'WEBHOOK_STUDENT_RENEWAL', 'webhook', ?, ?, ?)
    ")->execute([
        $rollNumber,
        json_encode(['old_renewal_date' => $oldRenewal]),
        json_encode(['new_renewal_date' => $newRenewal, 'remaining_days' => $remainingDays, 'txn_id' => $txnId, 'amount' => $amount]),
        $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1'
    ]);

    $db->commit();

    http_response_code(200);
    echo json_encode([
        'success' => true,
        'status'  => 'success',
        'message' => "Student renewal processed successfully. Valid until $newRenewal.",
        'data'    => [
            'roll_number'      => $rollNumber,
            'student_name'     => $studentName,
            'room_number'      => $roomNumber,
            'old_renewal_date' => $oldRenewal,
            'new_renewal_date' => $newRenewal,
            'valid_to'         => $newRenewal,
            'remaining_days'   => $remainingDays,
            'payment_txn_id'   => $txnId ?: null,
            'amount'           => $amount
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
