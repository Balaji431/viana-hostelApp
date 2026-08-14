<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

$reg_no = '192511250';
$warden = 'Kanita K';
$room = 'T32-F02-W0-R16';

$stmt = $db->prepare("UPDATE profile SET warden = :warden, room_allocation = :room WHERE reg_no = :reg OR email = :email");
$stmt->execute([':warden' => $warden, ':room' => $room, ':reg' => $reg_no, ':email' => '192511250.simats@saveetha.com']);

echo "Updated profile table for $reg_no:\n";
$verify = $db->query("SELECT id, full_name, reg_no, warden, room_allocation FROM profile WHERE reg_no = '$reg_no'")->fetch(PDO::FETCH_ASSOC);
print_r($verify);
