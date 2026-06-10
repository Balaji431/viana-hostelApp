<?php
require 'hostel_backend/config/database.php';
$db = new DatabaseMysqli();
$conn = $db->getConnection();
$res = $conn->query("SELECT room_no, building_code, room_type, facility, total_capacity FROM hostel_rooms WHERE room_no IN ('318', '334', '410', '411')");
while($row = $res->fetch_assoc()) {
    echo "Room: {$row['room_no']} | Building: {$row['building_code']} | RoomType: [{$row['room_type']}] | Facility: [{$row['facility']}] | Capacity: {$row['total_capacity']}\n";
}
