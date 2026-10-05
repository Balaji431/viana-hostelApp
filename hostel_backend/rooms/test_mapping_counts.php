<?php
if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    echo json_encode(["status" => "error", "message" => "Forbidden: CLI access only"]);
    exit();
}
require_once __DIR__ . '/../config/database.php';
$db = (new Database())->getConnection();

$query = "SELECT m.id, m.hostel_id, m.zone_id, m.sub_zone_id, h.hostel_name 
          FROM location_mappings m 
          JOIN hostel_type h ON m.hostel_id = h.id";
$mappings = $db->query($query)->fetchAll(PDO::FETCH_ASSOC);

foreach ($mappings as $m) {
    $sz = trim($m['sub_zone_id']);
    $sz_lower = strtolower($sz);

    if (empty($sz) || $sz_lower === 'all' || $sz_lower === 'w0' || $sz_lower === 'n/a') {
        $stmt = $db->prepare("
            SELECT COUNT(*) FROM rooms_groups_details 
            WHERE (
                LOWER(TRIM(group_name)) = LOWER(TRIM(:zone))
                OR LOWER(TRIM(group_name)) LIKE CONCAT('%', LOWER(TRIM(:zone)), '%')
                OR LOWER(TRIM(:zone)) LIKE CONCAT('%', LOWER(TRIM(group_name)), '%')
            )
        ");
        $stmt->execute([':zone' => $m['zone_id']]);
    } else {
        $stmt = $db->prepare("
            SELECT COUNT(*) FROM rooms_groups_details 
            WHERE (
                LOWER(TRIM(group_name)) = LOWER(TRIM(:zone))
                OR LOWER(TRIM(group_name)) LIKE CONCAT('%', LOWER(TRIM(:zone)), '%')
                OR LOWER(TRIM(:zone)) LIKE CONCAT('%', LOWER(TRIM(group_name)), '%')
            )
            AND (
                room_number LIKE CONCAT('%-', :sz, '-%')
                OR room_number LIKE CONCAT('%', :sz, '%')
            )
        ");
        $stmt->execute([':zone' => $m['zone_id'], ':sz' => $sz]);
    }

    $count = (int)$stmt->fetchColumn();
    echo "ID: {$m['id']} | Hostel: {$m['hostel_name']} | Zone: {$m['zone_id']} | SubZone: {$m['sub_zone_id']} => RoomCount: $count\n";
}
