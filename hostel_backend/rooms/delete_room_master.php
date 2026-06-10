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

    $json = file_get_contents('php://input');
    $data = json_decode($json, true);

    if (empty($data) || !isset($data['id'])) {
        echo json_encode([
            "status" => "error",
            "success" => false,
            "message" => "Room ID is required"
        ]);
        exit();
    }

    $id = intval($data['id']);

    $sql = "DELETE FROM room_master WHERE id = ?";
    $stmt = $db->prepare($sql);
    $stmt->execute([$id]);

    echo json_encode([
        "status" => "success",
        "success" => true,
        "message" => "Room deleted successfully"
    ]);

} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
