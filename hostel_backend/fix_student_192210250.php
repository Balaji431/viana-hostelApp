<?php
header('Content-Type: text/plain');
require_once 'config/database.php';
$database = new DatabaseMysqli();
$conn = $database->getConnection();

$reg_no = '192210250';
$today = date('Y-m-d');
$expiry = date('Y-m-d', strtotime('+12 months'));

echo "Fixing student $reg_no...\n";

// 1. Update Profile table
$stmt1 = $conn->prepare("UPDATE profile SET valid_from = ?, valid_to = ? WHERE reg_no = ?");
$stmt1->bind_param("sss", $today, $expiry, $reg_no);
$stmt1->execute();
echo "Profile updated: $today to $expiry\n";

// 2. Update new_room_booking table if it exists
$conn->query("UPDATE new_room_booking SET valid_from = '$today', valid_to = '$expiry' WHERE registerNumber = '$reg_no'");
echo "new_room_booking updated (if record existed).\n";

// 3. Ensure the room allocation is correct
$conn->query("UPDATE profile SET room_allocation = 'T32-F00-W01-R11' WHERE reg_no = '$reg_no'");

echo "\nVerification:\n";
$res = $conn->query("SELECT reg_no, room_allocation, valid_from, valid_to FROM profile WHERE reg_no = '$reg_no'");
print_r($res->fetch_assoc());

echo "\nDone. Please refresh the app.";
?>
