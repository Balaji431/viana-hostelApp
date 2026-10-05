<?php
/**
 * Webhook Endpoint: Student Renewal Date Modification
 *
 * Real-time event from VStudy when an administrator changes/corrects a student's renewal date
 * without triggering a payment renewal workflow.
 * Updates:
 * 1. `profile` table (renewal_date, valid_to, remaining_days)
 * 2. `audit_logs`
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
    $headers = function_exists('getallheaders') ? getallheaders() : [];
    $norm = [];
    if (is_array($headers)) {
        foreach ($headers as $k => $v) {
            $norm[strtolower(str_replace('_', '-', $k))] = trim($v);
        }
    }
    foreach (['x-api-key', 'x-client-secret', 'apikey', 'secret'] as $h) {
        if (!empty($norm[$h])) {
            return $norm[$h];
        }
    }
    $auth = $norm['authorization'] ?? ($_SERVER['HTTP_AUTHORIZATION'] ?? '');
    if (preg_match('/Bearer\s+(.*)$/i', $auth, $matches)) {
        return trim($matches[1]);
    }
    foreach (['HTTP_X_API_KEY', 'HTTP_X_CLIENT_SECRET', 'HTTP_APIKEY', 'HTTP_SECRET'] as $s) {
        if (!empty($_SERVER[$s])) {
            return trim($_SERVER[$s]);
        }
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
        'success'        => false,
        'status'         => 'error',
        'message'        => 'Invalid or missing authentication API key in header.',
        'provided_key'   => $providedKey,
        'server_headers' => array_keys(function_exists('getallheaders') ? getallheaders() : [])
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

$rawDate = trim(
    $body['renewalDate'] ??
    $body['newRenewalDate'] ??
    $body['renewal_date'] ??
    $body['valid_to'] ??
    $body['date'] ?? ''
);

$reason = trim($body['reason'] ?? $body['remarks'] ?? 'Renewal date modified via VStudy webhook');

if (empty($rollNumber)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Missing required field: rollNumber / registerNumber'
    ]);
    exit();
}

if (empty($rawDate)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Missing required field: renewalDate / newRenewalDate'
    ]);
    exit();
}

function parseDateGracefully($str) {
    if (empty($str)) return null;
    $s = trim($str);
    if (preg_match('/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/', $s, $m)) {
        return sprintf('%04d-%02d-%02d', (int)$m[3], (int)$m[2], (int)$m[1]);
    }
    $ts = strtotime($s);
    if ($ts !== false) {
        return date('Y-m-d', $ts);
    }
    return null;
}

$newRenewal = parseDateGracefully($rawDate);
if (!$newRenewal) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => "Invalid date format for renewal date: '$rawDate'. Please use YYYY-MM-DD."
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
    $oldRenewal = $currentProfile['renewal_date'] ?? $today;
    $remainingDays = max(0, (int)floor((strtotime($newRenewal) - strtotime($today)) / 86400));
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

    // 2b. Synchronize `users` table DOL
    try {
        $db->prepare("UPDATE users SET DOL = ? WHERE username = ? OR RegisterNumber = ?")
           ->execute([$newRenewal, $rollNumber, $rollNumber]);
    } catch (Exception $eUser) {}

    // 2c. Synchronize `vstudy_payments` table
    try {
        $db->prepare("UPDATE vstudy_payments SET renewal_date = ?, remaining_days = ? WHERE roll_number = ?")
           ->execute([$newRenewal, $remainingDays, $rollNumber]);
    } catch (Exception $ePay) {}

    // 3. Audit Logging
    $db->prepare("
        INSERT INTO audit_logs (username, role, action, module_name, old_value, new_value, ip_address) 
        VALUES (?, 'system', 'WEBHOOK_RENEWAL_DATE_CHANGE', 'webhook', ?, ?, ?)
    ")->execute([
        $rollNumber,
        json_encode(['old_renewal_date' => $oldRenewal]),
        json_encode(['new_renewal_date' => $newRenewal, 'remaining_days' => $remainingDays, 'reason' => $reason]),
        $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1'
    ]);

    $db->commit();

    http_response_code(200);
    echo json_encode([
        'success' => true,
        'status'  => 'success',
        'message' => "Student renewal date updated successfully to $newRenewal.",
        'data'    => [
            'roll_number'      => $rollNumber,
            'student_name'     => $studentName,
            'room_number'      => $roomNumber,
            'old_renewal_date' => $oldRenewal,
            'new_renewal_date' => $newRenewal,
            'valid_to'         => $newRenewal,
            'remaining_days'   => $remainingDays,
            'reason'           => $reason
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
