<?php
require '/var/www/html/config/database.php';
$db = (new Database())->getConnection();

$stmt = $db->query("SELECT COUNT(*) as total_rows, COUNT(DISTINCT room_number) as total_distinct_rooms FROM rooms_groups_details WHERE group_name LIKE '%Krishna Hostel(New) First Floor%'");
print_r($stmt->fetch(PDO::FETCH_ASSOC));
