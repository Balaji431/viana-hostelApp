<?php
header('Access-Control-Allow-Origin: *');
header("Content-Type: application/json");
error_reporting(0);
ini_set('display_errors', 0);

require_once("../../config/database.php");

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    try {
        $db = new Database();
        $conn = $db->getConnection();
        
        $input = json_decode(file_get_contents('php://input'), true);
        $hostelId = $input['hostel_id'] ?? '';
        $name = $input['name'] ?? '';
        
        if (empty($hostelId) || empty($name)) {
            echo json_encode([
                "success" => false,
                "error" => "Hostel ID and zone name are required"
            ]);
            exit;
        }
        
        $stmt = $conn->prepare("INSERT INTO zones (hostel_id, name) VALUES (?, ?)");
        $stmt->execute([$hostelId, $name]);
        
        echo json_encode([
            "success" => true,
            "message" => "Zone created successfully",
            "id" => $conn->lastInsertId()
        ]);
        
    } catch (Exception $e) {
        echo json_encode([
            "success" => false,
            "error" => $e->getMessage()
        ]);
    }
} else {
    echo json_encode([
        "success" => false,
        "error" => "Invalid request method"
    ]);
}
?>
