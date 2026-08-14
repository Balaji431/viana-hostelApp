<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

$reg_no = '192511250';
$room_no = 'T32-F02-W0-R16';
$warden = 'Kanita K';
$hostel = 'Vaigai Hostel';

echo "=== PERMANENT FIX FOR STUDENT 192511250 ===\n";

// Update profile table
$stmt1 = $db->prepare("UPDATE profile SET room_allocation = :room, warden = :warden, hostel_name = :hostel WHERE reg_no = :reg OR email = :reg_email");
$stmt1->execute([':room' => $room_no, ':warden' => $warden, ':hostel' => $hostel, ':reg' => $reg_no, ':reg_email' => '192511250.simats@saveetha.com']);

// Update users table
$stmt2 = $db->prepare("UPDATE users SET RoomId = :room, HostelName = :hostel WHERE username = :reg OR email = :reg_email");
$stmt2->execute([':room' => $room_no, ':hostel' => $hostel, ':reg' => $reg_no, ':reg_email' => '192511250.simats@saveetha.com']);

// Update vstudy_payments table if needed
$stmt3 = $db->prepare("UPDATE vstudy_payments SET room_number = :room, hostel_name = :hostel WHERE roll_number = :reg OR email = :reg_email");
$stmt3->execute([':room' => $room_no, ':hostel' => $hostel, ':reg' => $reg_no, ':reg_email' => '192511250.simats@saveetha.com']);

echo "Database records updated successfully.\n\n";

echo "=== RUNNING MASTER SYNC TO VERIFY SYNC COMPATIBILITY ===\n";
require_once __DIR__ . '/../../../hostel_backend/rooms/sync_room_master.php';

echo "\n=== VERIFYING FINAL STUDENT DATA ===\n";
$stmtVerP = $db->query("SELECT id, full_name, reg_no, email, room_allocation, warden, hostel_name FROM profile WHERE reg_no = '192511250'");
print_r($stmtVerP->fetch(PDO::FETCH_ASSOC));

$stmtVerU = $db->query("SELECT id, username, full_name, role, RoomId, HostelName FROM users WHERE username = '192511250'");
print_r($stmtVerU->fetch(PDO::FETCH_ASSOC));
