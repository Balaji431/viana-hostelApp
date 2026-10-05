<?php
/**
 * Webhook Endpoint: Add / Upsert Room Group
 *
 * Real-time event from VStudy when a room group/floor is created or modified.
 * Updates:
 * 1. `external_room_groups` table
 * 2. Cascades warden assignments to `rooms_groups_details` if rooms belong to this group
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

$groupId = trim(
    $body['groupId'] ??
    $body['id'] ??
    $body['group_id'] ?? ''
);

$groupName = trim(
    $body['groupName'] ??
    $body['name'] ??
    $body['group_name'] ?? ''
);

$hostelName = trim(
    $body['hostelName'] ??
    $body['hostel_name'] ?? ''
);

if (empty($groupId)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Missing required field: groupId / id'
    ]);
    exit();
}

if (empty($groupName)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Missing required field: groupName / name'
    ]);
    exit();
}

if (empty($hostelName)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'status'  => 'error',
        'message' => 'Missing required field: hostelName'
    ]);
    exit();
}

$floorName = trim($body['floorName'] ?? $body['floor_name'] ?? '');
if (empty($floorName)) {
    if (stripos($groupName, 'ground') !== false) {
        $floorName = 'Ground';
    } elseif (preg_match('/(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|\d+)/i', $groupName, $m)) {
        $floorName = ucfirst($m[1]);
    } else {
        $floorName = 'Floor';
    }
}

$floorOrder = isset($body['floorOrder']) ? (int)$body['floorOrder'] : (isset($body['floor_order']) ? (int)$body['floor_order'] : 0);
if ($floorOrder === 0 && preg_match('/(\d+)/', $floorName, $m)) {
    $floorOrder = (int)$m[1];
}

$wardenName   = trim($body['wardenName'] ?? $body['warden_name'] ?? '');
$wardenUserId = trim($body['wardenUserId'] ?? $body['warden_user_id'] ?? '');
$wardenBioId  = trim($body['wardenBioId'] ?? $body['warden_bio_id'] ?? '');
$wardenEmail  = trim($body['wardenEmail'] ?? $body['warden_email'] ?? '');
$roomCount    = isset($body['roomCount']) ? (int)$body['roomCount'] : (isset($body['room_count']) ? (int)$body['room_count'] : 0);

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $db->beginTransaction();

    // 1. Check if group exists in `external_room_groups`
    $chkStmt = $db->prepare("SELECT s_no FROM external_room_groups WHERE id = ? LIMIT 1");
    $chkStmt->execute([$groupId]);
    $existing = $chkStmt->fetch(PDO::FETCH_ASSOC);

    if ($existing) {
        $db->prepare("
            UPDATE external_room_groups SET 
                name           = :name,
                hostel_name    = :hostel_name,
                floor_name     = :floor_name,
                floor_order    = :floor_order,
                warden_user_id = COALESCE(NULLIF(:warden_user_id, ''), warden_user_id),
                warden_name    = COALESCE(NULLIF(:warden_name, ''), warden_name),
                warden_bio_id  = COALESCE(NULLIF(:warden_bio_id, ''), warden_bio_id),
                warden_email   = COALESCE(NULLIF(:warden_email, ''), warden_email),
                room_count     = IF(:room_count > 0, :room_count, room_count),
                updated_at     = NOW()
            WHERE id = :id
        ")->execute([
            ':name'           => $groupName,
            ':hostel_name'    => $hostelName,
            ':floor_name'     => $floorName,
            ':floor_order'    => $floorOrder,
            ':warden_user_id' => $wardenUserId,
            ':warden_name'    => $wardenName,
            ':warden_bio_id'  => $wardenBioId,
            ':warden_email'   => $wardenEmail,
            ':room_count'     => $roomCount,
            ':id'             => $groupId
        ]);
        $action = 'updated';
    } else {
        $db->prepare("
            INSERT INTO external_room_groups (
                id, name, hostel_name, floor_name, floor_order,
                warden_user_id, warden_name, warden_bio_id, warden_email,
                room_count, created_at, updated_at
            ) VALUES (
                :id, :name, :hostel_name, :floor_name, :floor_order,
                :warden_user_id, :warden_name, :warden_bio_id, :warden_email,
                :room_count, NOW(), NOW()
            )
        ")->execute([
            ':id'             => $groupId,
            ':name'           => $groupName,
            ':hostel_name'    => $hostelName,
            ':floor_name'     => $floorName,
            ':floor_order'    => $floorOrder,
            ':warden_user_id' => $wardenUserId,
            ':warden_name'    => $wardenName,
            ':warden_bio_id'  => $wardenBioId,
            ':warden_email'   => $wardenEmail,
            ':room_count'     => $roomCount
        ]);
        $action = 'created';
    }

    // 2. Cascade warden to `rooms_groups_details` if warden is updated
    if (!empty($wardenName)) {
        $db->prepare("
            UPDATE rooms_groups_details SET 
                warden_name    = :warden_name,
                warden_user_id = COALESCE(NULLIF(:warden_user_id, ''), warden_user_id),
                warden_bio_id  = COALESCE(NULLIF(:warden_bio_id, ''), warden_bio_id),
                group_name     = :group_name,
                updated_at     = NOW()
            WHERE group_id = :group_id
        ")->execute([
            ':warden_name'    => $wardenName,
            ':warden_user_id' => $wardenUserId,
            ':warden_bio_id'  => $wardenBioId,
            ':group_name'     => $groupName,
            ':group_id'       => $groupId
        ]);
    }

    // 3. Audit Logging
    $db->prepare("
        INSERT INTO audit_logs (username, role, action, module_name, new_value, ip_address) 
        VALUES ('vstudy', 'system', 'WEBHOOK_ADD_GROUP', 'webhook', ?, ?)
    ")->execute([
        json_encode([
            'group_id'   => $groupId,
            'name'       => $groupName,
            'hostel'     => $hostelName,
            'warden'     => $wardenName,
            'action'     => $action
        ]),
        $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1'
    ]);

    $db->commit();

    http_response_code(200);
    echo json_encode([
        'success' => true,
        'status'  => 'success',
        'message' => "Group '$groupName' $action successfully.",
        'action'  => $action,
        'data'    => [
            'group_id'       => $groupId,
            'group_name'     => $groupName,
            'hostel_name'    => $hostelName,
            'floor_name'     => $floorName,
            'floor_order'    => $floorOrder,
            'warden_name'    => $wardenName ?: null,
            'warden_user_id' => $wardenUserId ?: null,
            'warden_bio_id'  => $wardenBioId ?: null,
            'warden_email'   => $wardenEmail ?: null,
            'room_count'     => $roomCount
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
