<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

echo "=== Searching rooms_groups_details for Second Floor Vaigai Hostel ===\n";
$stmt = $db->query("SELECT * FROM rooms_groups_details WHERE group_id = '33469c74-9ac9-45b9-adca-c36000e73fd5' OR room_number LIKE '%F02%R16%' OR room_number LIKE '%F02%' AND hostel_name LIKE '%Vaigai%'");
print_r($stmt->fetchAll(PDO::FETCH_ASSOC));
