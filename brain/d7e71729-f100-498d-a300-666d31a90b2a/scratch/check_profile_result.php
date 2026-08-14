<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

echo "=== CHECKING PROFILE AFTER SYNC ===\n";
$stmt = $db->prepare("SELECT * FROM profile WHERE reg_no = '192511250'");
$stmt->execute();
$p = $stmt->fetch(PDO::FETCH_ASSOC);
print_r($p);

echo "\n=== CHECKING USERS AFTER SYNC ===\n";
$stmt2 = $db->prepare("SELECT id, username, full_name, RoomId, HostelName FROM users WHERE username = '192511250'");
$stmt2->execute();
$u = $stmt2->fetch(PDO::FETCH_ASSOC);
print_r($u);
