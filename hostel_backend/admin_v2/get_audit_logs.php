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

try {
    $database = new Database();
    $db = $database->getConnection();

    if ($db === null) {
        sendResponse(false, "Database connection failed", null, 500);
        exit();
    }

    // Fetch logs ordered by created_at DESC
    $query = "SELECT id, user_id, username, role, action, module_name, old_value, new_value, ip_address, created_at 
              FROM audit_logs 
              ORDER BY created_at DESC 
              LIMIT 500";
    
    $stmt = $db->prepare($query);
    $stmt->execute();
    $logs = $stmt->fetchAll(PDO::FETCH_ASSOC);

    sendResponse(true, "Logs retrieved successfully", $logs);
} catch (Exception $e) {
    sendResponse(false, "Error: " . $e->getMessage(), null, 500);
}
?>
