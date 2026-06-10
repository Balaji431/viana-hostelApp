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
        $subZoneId = $input['sub_zone_id'] ?? '';
        $roomNumber = $input['room_number'] ?? '';
        $capacity = $input['capacity'] ?? '';
        $floorLabel = $input['floor_label'] ?? '';
        
        if (empty($subZoneId) || empty($roomNumber) || empty($capacity)) {
            echo json_encode([
                "success" => false,
                "error" => "Sub-zone ID, room number, and capacity are required"
            ]);
            exit;
        }
        
        $stmt = $conn->prepare("INSERT INTO rooms (sub_zone_id, room_number, capacity, floor_label) VALUES (?, ?, ?, ?)");
        $stmt->execute([$subZoneId, $roomNumber, $capacity, $floorLabel]);
        
        echo json_encode([
            "success" => true,
            "message" => "Room created successfully",
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
