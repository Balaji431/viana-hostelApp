<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept, X-User-Id, X-User-Username, X-User-Role');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/response.php';
require_once __DIR__ . '/../utils/activity_logger.php';

// Try to get headers or post body
$userId = $_SERVER['HTTP_X_USER_ID'] ?? null;
$username = $_SERVER['HTTP_X_USER_USERNAME'] ?? null;
$role = $_SERVER['HTTP_X_USER_ROLE'] ?? null;

if (!$userId || !$username) {
    $raw_input = file_get_contents("php://input");
    $data = json_decode($raw_input);
    if ($data) {
        $userId = $data->user_id ?? null;
        $username = $data->username ?? null;
        $role = $data->role ?? null;
    }
}

if ($username) {
    logAudit($userId, $username, $role, 'LOGOUT', 'Authentication');
    sendResponse(true, "Logout logged successfully");
} else {
    sendResponse(false, "Invalid data", null, 400);
}
?>
