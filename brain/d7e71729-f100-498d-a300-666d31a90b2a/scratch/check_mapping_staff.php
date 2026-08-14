<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

echo "=== CHECKING mapping_staff FOR Vaigai Hostel Second Floor ===\n";
$stmt = $db->query("SELECT * FROM mapping_staff WHERE floor_name LIKE '%Vaigai%' OR hostel_name LIKE '%Vaigai%' OR name LIKE '%Kanita%' OR name LIKE '%Gomathy%'");
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
print_r($rows);

echo "\n=== CHECKING rooms_groups_details FOR Vaigai Hostel Second Floor ===\n";
$stmt2 = $db->query("SELECT DISTINCT group_name, warden_name, warden_bio_id, hostel_name FROM rooms_groups_details WHERE hostel_name LIKE '%Vaigai%' AND (group_name LIKE '%Second%' OR group_name LIKE '%2nd%')");
$rows2 = $stmt2->fetchAll(PDO::FETCH_ASSOC);
print_r($rows2);
