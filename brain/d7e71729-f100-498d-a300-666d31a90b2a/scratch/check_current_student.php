<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

echo "=== CHECKING CURRENT DB DATA FOR 192511250 ===\n";

$stmtP = $db->query("SELECT id, full_name, reg_no, email, room_allocation, warden, hostel_name FROM profile WHERE reg_no = '192511250'");
$p = $stmtP->fetch(PDO::FETCH_ASSOC);
echo "Profile Table:\n";
print_r($p);

$stmtU = $db->query("SELECT id, username, full_name, role, RoomId, HostelName FROM users WHERE username = '192511250'");
$u = $stmtU->fetch(PDO::FETCH_ASSOC);
echo "Users Table:\n";
print_r($u);

$stmtR = $db->query("SELECT room_number, group_name, warden_name, hostel_name FROM rooms_groups_details WHERE REPLACE(REPLACE(TRIM(room_number), ' ', ''), '-', '') = 'T32F02W0R16' LIMIT 1");
$r = $stmtR->fetch(PDO::FETCH_ASSOC);
echo "rooms_groups_details Table:\n";
print_r($r);
