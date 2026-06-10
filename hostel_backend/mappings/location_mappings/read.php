<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../../config/database.php';

try {
    // Fetch mappings with location names (stored directly in location_mappings)
    $query = "SELECT m.id, m.hostel_id, 
                     m.zone_id as zone_id, m.sub_zone_id as sub_zone_id,
                     h.hostel_name as hostel_name,
                     m.zone_id as zone_name,
                     m.sub_zone_id as sub_zone_name
              FROM location_mappings m
              JOIN hostel_type h ON m.hostel_id = h.id
              ORDER BY h.hostel_name, m.zone_id, m.sub_zone_id";
              
    $stmt = $pdo->query($query);
    $mappings = $stmt->fetchAll(PDO::FETCH_ASSOC);

    foreach ($mappings as &$m) {
        // Fetch staff for each mapping including location details
        $staffStmt = $pdo->prepare("SELECT name, role, phone, username, hostel_name, floor_name, wing_name FROM mapping_staff WHERE mapping_id = ?");
        $staffStmt->execute([$m['id']]);
        $m['staff'] = $staffStmt->fetchAll(PDO::FETCH_ASSOC);

        // Calculate room count for this mapping
        $h_id = $m['hostel_id'];
        $z_id = $m['zone_id'];
        $sz_id = $m['sub_zone_id'];

        $roomCountStmt = $pdo->prepare("SELECT COUNT(*) FROM hostel_rooms 
                                        WHERE hostel_id = ? 
                                        AND (floor = ? OR ? IS NULL OR ? = '') 
                                        AND (wing_code = ? OR ? IS NULL OR ? = '')");
        $roomCountStmt->execute([$h_id, $z_id, $z_id, $z_id, $sz_id, $sz_id, $sz_id]);
        $m['room_count'] = (int)$roomCountStmt->fetchColumn();
    }

    echo json_encode([
        "status" => "success",
        "data" => $mappings
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Error: " . $e->getMessage()
    ]);
}
?>
