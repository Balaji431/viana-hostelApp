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

if (!isset($data['hostel_id']) || !isset($data['staff'])) {
    echo json_encode(["success" => false, "message" => "Missing required fields"]);
    exit();
}

try {
    $pdo->beginTransaction();
    
    $mappingId = $data['id'] ?? null;
    $hostelId = $data['hostel_id'];
    $zoneId = !empty($data['zone_id']) ? $data['zone_id'] : null;
    $subZoneId = !empty($data['sub_zone_id']) ? $data['sub_zone_id'] : null;
    
    if ($mappingId) {
        // Update existing mapping location
        $stmt = $pdo->prepare("UPDATE location_mappings SET hostel_id = ?, zone_id = ?, sub_zone_id = ? WHERE id = ?");
        $stmt->execute([$hostelId, $zoneId, $subZoneId, $mappingId]);
        
        // Clear old staff
        $stmt = $pdo->prepare("DELETE FROM mapping_staff WHERE mapping_id = ?");
        $stmt->execute([$mappingId]);
    } else {
        // Create new mapping location
        $stmt = $pdo->prepare("INSERT INTO location_mappings (hostel_id, zone_id, sub_zone_id) VALUES (?, ?, ?)");
        $stmt->execute([$hostelId, $zoneId, $subZoneId]);
        $mappingId = $pdo->lastInsertId();
    }
    
    // Insert new staff members with location details
    $stmt = $pdo->prepare("INSERT INTO mapping_staff (mapping_id, name, role, phone, username, hostel_name, floor_name, wing_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
    foreach ($data['staff'] as $staff) {
        $stmt->execute([
            $mappingId, 
            $staff['name'], 
            $staff['role'], 
            $staff['phone'], 
            $staff['username'] ?? '',
            $staff['hostel_name'] ?? '',
            $staff['floor_name'] ?? '',
            $staff['wing_name'] ?? ''
        ]);
    }
    
    $pdo->commit();
    echo json_encode(["status" => "success", "id" => $mappingId]);

} catch (Exception $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
}
?>
