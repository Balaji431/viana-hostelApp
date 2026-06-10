<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../../config/database.php';

$data = json_decode(file_get_contents("php://input"), true);

if (!isset($data['hostelId']) || !isset($data['assignedStaff'])) {
    echo json_encode(["success" => false, "message" => "Missing required fields"]);
    exit();
}

try {
    $pdo->beginTransaction();
    
    $hostelId = $data['hostelId'];
    $wing = $data['zoneId'] ?? null;
    $floor = $data['subZoneId'] ?? null;
    $roomId = $data['roomId'] ?? null;
    
    foreach ($data['assignedStaff'] as $staff) {
        $staffId = $staff['id'];
        
        // Check if already exists
        $check = $pdo->prepare("SELECT id FROM location_mappings WHERE user_id = ? AND hostel_id = ? AND (wing_code = ? OR (wing_code IS NULL AND ? IS NULL))");
        $check->execute([$staffId, $hostelId, $wing, $wing]);
        
        if (!$check->fetch()) {
            $stmt = $pdo->prepare("INSERT INTO location_mappings (user_id, hostel_id, wing_code, floor, room_id) VALUES (?, ?, ?, ?, ?)");
            $stmt->execute([$staffId, $hostelId, $wing, $floor, $roomId]);
        }
    }
    
    $pdo->commit();
    echo json_encode(["success" => true]);

} catch (Exception $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
}
?>
