<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

try {
    // We use DatabaseMysqli or Database based on what's available
    // Based on previous files, let's use the Database class with PDO
    $database = new Database();
    $db = $database->getConnection();

    $query = "SELECT l.id, l.admin_id, l.action, l.details, l.created_at, 
                     COALESCE(u.full_name, 'System') as admin_name
              FROM admin_activity_logs l
              LEFT JOIN users u ON l.admin_id = u.id
              ORDER BY l.created_at DESC
              LIMIT 100";

    $stmt = $db->prepare($query);
    $stmt->execute();
    $logs = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "success" => true,
        "data" => $logs
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Error: " . $e->getMessage()
    ]);
}
?>
