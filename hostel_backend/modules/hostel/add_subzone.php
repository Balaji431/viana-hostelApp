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
        $zoneId = $input['zone_id'] ?? '';
        $name = $input['name'] ?? '';
        
        if (empty($zoneId) || empty($name)) {
            echo json_encode([
                "success" => false,
                "error" => "Zone ID and sub-zone name are required"
            ]);
            exit;
        }
        
        $stmt = $conn->prepare("INSERT INTO sub_zones (zone_id, name) VALUES (?, ?)");
        $stmt->execute([$zoneId, $name]);
        
        echo json_encode([
            "success" => true,
            "message" => "Sub-zone created successfully",
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
