<?php
/**
 * set_app_version.php
 * Administrative endpoint to update the active Google Play release requirements.
 * Used when deploying a new AAB to Google Play Console.
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, x-client-id, x-client-secret');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/api_config.php';
require_once __DIR__ . '/../config/database.php';

function getRequestHeader($name) {
    $serverKey = 'HTTP_' . strtoupper(str_replace('-', '_', $name));
    if (!empty($_SERVER[$serverKey])) return trim($_SERVER[$serverKey]);
    if (function_exists('getallheaders')) {
        foreach (getallheaders() as $k => $v) {
            if (strcasecmp($k, $name) === 0) return trim($v);
        }
    }
    return '';
}

$expectedClientId     = defined('VSTUDY_CLIENT_ID') ? VSTUDY_CLIENT_ID : '';
$expectedClientSecret = defined('VSTUDY_CLIENT_SECRET') ? VSTUDY_CLIENT_SECRET : '';

$incomingClientId     = getRequestHeader('x-client-id');
$incomingClientSecret = getRequestHeader('x-client-secret');

$rawInput = file_get_contents('php://input');
$data = json_decode($rawInput, true) ?: $_POST;

$cId = !empty($incomingClientId) ? $incomingClientId : ($data['client_id'] ?? '');
$cSec = !empty($incomingClientSecret) ? $incomingClientSecret : ($data['client_secret'] ?? '');

$valid = (!empty($cId) && !empty($cSec) && !empty($expectedClientId) && !empty($expectedClientSecret) &&
          hash_equals($expectedClientId, $cId) && hash_equals($expectedClientSecret, $cSec));

if (!$valid) {
    http_response_code(401);
    echo json_encode(['success' => false, 'message' => 'Unauthorized: Invalid credentials']);
    exit();
}

$database = new Database();
$db = $database->getConnection();

try {
    $platform = strtolower(trim($data['platform'] ?? 'android'));
    $latestVersionName = trim($data['latest_version_name'] ?? '1.0.2');
    $latestVersionCode = (int)($data['latest_version_code'] ?? 27);
    $minVersionCode    = (int)($data['minimum_required_version_code'] ?? $latestVersionCode);
    $forceUpdate       = isset($data['force_update']) ? ((int)$data['force_update'] ? 1 : 0) : 1;
    $title             = trim($data['title'] ?? 'Mandatory Update Available');
    $message           = trim($data['message'] ?? 'A new version of VStay is available on Google Play Store. Please update to continue.');
    $playStoreUrl      = trim($data['play_store_url'] ?? 'https://play.google.com/store/apps/details?id=com.vianasoft.stay');

    $releaseNotes = $data['release_notes'] ?? null;
    if (is_array($releaseNotes)) {
        $releaseNotes = json_encode($releaseNotes);
    }

    $stmt = $db->prepare("
        INSERT INTO app_version_control 
        (platform, latest_version_name, latest_version_code, minimum_required_version_code, force_update, title, message, play_store_url, release_notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            latest_version_name = VALUES(latest_version_name),
            latest_version_code = VALUES(latest_version_code),
            minimum_required_version_code = VALUES(minimum_required_version_code),
            force_update = VALUES(force_update),
            title = VALUES(title),
            message = VALUES(message),
            play_store_url = VALUES(play_store_url),
            release_notes = VALUES(release_notes),
            updated_at = NOW()
    ");

    $stmt->execute([
        $platform,
        $latestVersionName,
        $latestVersionCode,
        $minVersionCode,
        $forceUpdate,
        $title,
        $message,
        $playStoreUrl,
        $releaseNotes
    ]);

    echo json_encode([
        'success' => true,
        'message' => 'App version control updated successfully!',
        'active_config' => [
            'platform' => $platform,
            'latest_version_name' => $latestVersionName,
            'latest_version_code' => $latestVersionCode,
            'minimum_required_version_code' => $minVersionCode,
            'force_update' => $forceUpdate === 1,
            'title' => $title,
            'message' => $message,
            'play_store_url' => $playStoreUrl,
        ]
    ], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}
