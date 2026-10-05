<?php
/**
 * check_app_version.php
 * Endpoint called by the Flutter application to check if an update is available on Google Play Store
 * and whether a mandatory (force) update is required before the student can use the app.
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, x-client-id, x-client-secret');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo json_encode([
        'success' => false,
        'update_available' => false,
        'force_update' => false,
        'message' => 'Database connection failed'
    ]);
    exit();
}

try {
    $platform = strtolower(trim($_GET['platform'] ?? $_POST['platform'] ?? 'android'));
    if (!in_array($platform, ['android', 'ios'])) {
        $platform = 'android';
    }

    $clientVersionCode = (int)($_GET['version_code'] ?? $_POST['version_code'] ?? 0);
    $clientVersionName = trim($_GET['version_name'] ?? $_POST['version_name'] ?? '');

    $stmt = $db->prepare("SELECT * FROM app_version_control WHERE platform = ? LIMIT 1");
    $stmt->execute([$platform]);
    $cfg = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$cfg) {
        echo json_encode([
            'success' => true,
            'update_available' => false,
            'force_update' => false,
            'message' => 'No version restrictions configured for platform.'
        ]);
        exit();
    }

    $latestVersionName = $cfg['latest_version_name'];
    $latestVersionCode = (int)$cfg['latest_version_code'];
    $minRequiredCode   = (int)$cfg['minimum_required_version_code'];
    $forceFlag         = (int)$cfg['force_update'] === 1;

    $isUpdateAvailable = ($clientVersionCode > 0 && $clientVersionCode < $latestVersionCode);
    $isForceUpdate     = false;

    if ($clientVersionCode > 0) {
        if ($clientVersionCode < $minRequiredCode) {
            $isForceUpdate = true;
            $isUpdateAvailable = true;
        } elseif ($forceFlag && $clientVersionCode < $latestVersionCode) {
            $isForceUpdate = true;
            $isUpdateAvailable = true;
        }
    }

    $releaseNotes = [];
    if (!empty($cfg['release_notes'])) {
        $decoded = json_decode($cfg['release_notes'], true);
        if (is_array($decoded)) {
            $releaseNotes = $decoded;
        } else {
            $releaseNotes = array_filter(array_map('trim', explode("\n", $cfg['release_notes'])));
        }
    }

    echo json_encode([
        'success' => true,
        'update_available' => $isUpdateAvailable,
        'force_update' => $isForceUpdate,
        'platform' => $platform,
        'client_version_code' => $clientVersionCode,
        'client_version_name' => $clientVersionName,
        'latest_version_name' => $latestVersionName,
        'latest_version_code' => $latestVersionCode,
        'minimum_required_version_code' => $minRequiredCode,
        'title' => $cfg['title'] ?: 'New Update Available',
        'message' => $cfg['message'] ?: 'A new version of VStay is available. Please update from Google Play Store to continue.',
        'play_store_url' => $cfg['play_store_url'] ?: 'https://play.google.com/store/apps/details?id=com.vianasoft.stay',
        'release_notes' => array_values($releaseNotes),
    ], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'update_available' => false,
        'force_update' => false,
        'error' => $e->getMessage()
    ]);
}
