<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json");
header("Cache-Control: no-store, no-cache, must-revalidate, max-age=0");
header("Cache-Control: post-check=0, pre-check=0", false);
header("Pragma: no-cache");

if (isset($_SERVER['REQUEST_METHOD']) && $_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once dirname(__DIR__) . '/config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();

    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $stmt = $db->query("
        SELECT DISTINCT room_type 
        FROM room_master 
        WHERE room_type IS NOT NULL AND room_type != '' AND room_type != 'Not Assigned'
        ORDER BY room_type
    ");
    
    $list = [];
    while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $list[] = [
            'id' => $row['room_type'],
            'name' => $row['room_type']
        ];
    }

    echo json_encode([
        "status" => "success",
        "success" => true,
        "data" => $list
    ]);
} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
