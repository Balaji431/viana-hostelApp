<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

echo "=== CHECKING USER & PROFILE FOR 192511250 ===\n";
$stmt = $db->prepare("SELECT * FROM users WHERE username = '192511250'");
$stmt->execute();
$u = $stmt->fetch(PDO::FETCH_ASSOC);
echo "USERS table:\n";
print_r($u);

$stmt2 = $db->prepare("SELECT * FROM profile WHERE reg_no = '192511250'");
$stmt2->execute();
$p = $stmt2->fetch(PDO::FETCH_ASSOC);
echo "PROFILE table:\n";
print_r($p);

echo "\n=== CHECKING ROOMS IN rooms_groups_details MATCHING Vaigai Hostel / Second Floor ===\n";
$stmt3 = $db->query("SELECT * FROM rooms_groups_details WHERE hostel_name LIKE '%Vaigai%' OR group_name LIKE '%Second%' OR room_number LIKE '%T-32%' LIMIT 10");
$rgd = $stmt3->fetchAll(PDO::FETCH_ASSOC);
print_r($rgd);

echo "\n=== CHECKING IF ROOM VALUE 'T-32 F02- W0-R16' EXISTS IN ANY TABLE ===\n";
$stmt4 = $db->query("SELECT * FROM rooms_groups_details WHERE room_number = 'T-32 F02- W0-R16' OR room_number LIKE '%R16%'");
print_r($stmt4->fetchAll(PDO::FETCH_ASSOC));

echo "\n=== CHECKING vstudy_payments FOR 192511250 ===\n";
$stmt5 = $db->query("SELECT * FROM vstudy_payments WHERE roll_number = '192511250'");
print_r($stmt5->fetchAll(PDO::FETCH_ASSOC));
