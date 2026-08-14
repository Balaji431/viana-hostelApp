<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

$reg_no = '192511250';
$room_no = 'T32-F02-W0-R16';
$warden = 'Kanita K';

$db->exec("UPDATE profile SET room_allocation = '$room_no', warden = '$warden' WHERE reg_no = '$reg_no'");
$db->exec("UPDATE users SET RoomId = '$room_no' WHERE username = '$reg_no'");

echo "Updated profile and users for 192511250.\n";
