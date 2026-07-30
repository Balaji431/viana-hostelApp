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
              ORDER BY CASE WHEN LOWER(h.hostel_name) LIKE '%kaveri%' THEN 0 ELSE 1 END ASC,
                       h.hostel_name ASC,
                       CASE 
                          WHEN LOWER(m.zone_id) LIKE '%ground%' OR LOWER(m.zone_id) LIKE '%g0%' THEN 0
                          WHEN LOWER(m.zone_id) LIKE '%first%'  OR LOWER(m.zone_id) LIKE '%1st%' THEN 1
                          WHEN LOWER(m.zone_id) LIKE '%second%' OR LOWER(m.zone_id) LIKE '%2nd%' THEN 2
                          WHEN LOWER(m.zone_id) LIKE '%third%'  OR LOWER(m.zone_id) LIKE '%3rd%' THEN 3
                          WHEN LOWER(m.zone_id) LIKE '%fourth%' OR LOWER(m.zone_id) LIKE '%4th%' THEN 4
                          WHEN LOWER(m.zone_id) LIKE '%fifth%'  OR LOWER(m.zone_id) LIKE '%5th%' THEN 5
                          WHEN LOWER(m.zone_id) LIKE '%sixth%'  OR LOWER(m.zone_id) LIKE '%6th%' THEN 6
                          WHEN LOWER(m.zone_id) LIKE '%seventh%' OR LOWER(m.zone_id) LIKE '%7th%' THEN 7
                          WHEN LOWER(m.zone_id) LIKE '%eighth%' OR LOWER(m.zone_id) LIKE '%8th%' THEN 8
                          WHEN LOWER(m.zone_id) LIKE '%ninth%'  OR LOWER(m.zone_id) LIKE '%9th%' THEN 9
                          WHEN LOWER(m.zone_id) LIKE '%tenth%'  OR LOWER(m.zone_id) LIKE '%10th%' THEN 10
                          ELSE 99
                       END ASC,
                       m.sub_zone_id ASC,
                       m.id ASC";
              
    $stmt = $pdo->query($query);
    $mappings = $stmt->fetchAll(PDO::FETCH_ASSOC);

    foreach ($mappings as &$m) {
        // Fetch staff for each mapping including location details
        $staffStmt = $pdo->prepare("SELECT COALESCE(su.name, ms.name) as name, ms.role, COALESCE(su.phone, ms.phone) as phone, COALESCE(ms.staff_bio_id, ms.username) as username, ms.hostel_name, ms.floor_name, ms.wing_name 
                                    FROM mapping_staff ms 
                                    LEFT JOIN staff_users su ON ms.staff_bio_id COLLATE utf8mb4_general_ci = su.bio_id COLLATE utf8mb4_general_ci
                                    WHERE ms.mapping_id = ?");
        $staffStmt->execute([$m['id']]);
        $m['staff'] = $staffStmt->fetchAll(PDO::FETCH_ASSOC);

        // Calculate room count for this mapping
        $h_id = $m['hostel_id'];
        $z_id = $m['zone_id'];
        $sz_id = $m['sub_zone_id'];

        $roomCountStmt = $pdo->prepare("
            SELECT COUNT(*) FROM rooms_groups_details 
            WHERE (TRIM(hostel_name) LIKE CONCAT('%', TRIM(?), '%')) 
              AND (TRIM(group_name) LIKE CONCAT('%', TRIM(?), '%'))
              AND (room_number LIKE CONCAT('%-', TRIM(?), '-%') OR ? = 'W0' OR ? = 'N/A' OR group_name LIKE CONCAT('%', TRIM(?), '%'))
        ");
        $roomCountStmt->execute([$m['hostel_name'], $m['zone_id'], $m['sub_zone_id'], $m['sub_zone_id'], $m['sub_zone_id'], $m['sub_zone_id']]);
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
