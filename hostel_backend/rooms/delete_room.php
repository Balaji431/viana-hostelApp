<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once '../config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();

    $data = json_decode(file_get_contents("php://input"), true);

    if (isset($data['id'])) {
        $roomId = intval($data['id']);
        
        $stmt = $db->prepare("DELETE FROM rooms WHERE id = ?");
        $stmt->execute([$roomId]);
        
        echo json_encode([
            "status" => "success",
            "success" => true,
            "message" => "Room deleted successfully"
        ]);
    } else {
        echo json_encode([
            "status" => "error",
            "success" => false,
            "message" => "Room ID is required"
        ]);
    }
} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
