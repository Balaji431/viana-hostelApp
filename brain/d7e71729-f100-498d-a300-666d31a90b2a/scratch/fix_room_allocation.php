<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo "DB Connection failed\n";
    exit(1);
}

$reg_no = '192511250';
$room_number = 'T-32-F02-W0-R16';

echo "=== FIXING ROOM ALLOCATION FOR STUDENT $reg_no ===\n";

// 1. Update users table RoomId
$stmt1 = $db->prepare("UPDATE users SET RoomId = :room WHERE username = :reg OR email = :reg_email");
$stmt1->execute([
    ':room' => $room_number,
    ':reg' => $reg_no,
    ':reg_email' => '192511250.simats@saveetha.com'
]);
echo "Updated users table RoomId to '$room_number' (rows affected: " . $stmt1->rowCount() . ")\n";

// 2. Fetch warden from rooms_groups_details for this room
$stmtWarden = $db->prepare("
    SELECT warden_name, hostel_name, group_name 
    FROM rooms_groups_details 
    WHERE REPLACE(REPLACE(TRIM(room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(:room), ' ', ''), '-', '')
    LIMIT 1
");
$stmtWarden->execute([':room' => $room_number]);
$wardenRow = $stmtWarden->fetch(PDO::FETCH_ASSOC);

$wardenName = $wardenRow['warden_name'] ?? 'Kanita K';
$hostelName = $wardenRow['hostel_name'] ?? 'Vaigai Hostel';
echo "Matched room in rooms_groups_details: Hostel = '$hostelName', Warden = '$wardenName'\n";

// 3. Update profile table
$stmt2 = $db->prepare("
    UPDATE profile 
    SET room_allocation = :room, warden = :warden, hostel_name = :hostel
    WHERE reg_no = :reg OR email = :reg_email
");
$stmt2->execute([
    ':room' => $room_number,
    ':warden' => $wardenName,
    ':hostel' => $hostelName,
    ':reg' => $reg_no,
    ':reg_email' => '192511250.simats@saveetha.com'
]);
echo "Updated profile table room_allocation to '$room_number' and warden to '$wardenName' (rows affected: " . $stmt2->rowCount() . ")\n";

// 4. Also check for any other student profiles where room_allocation is missing but RoomId exists in users
$stmtSync = $db->exec("
    UPDATE profile p
    JOIN users u ON TRIM(p.reg_no) = TRIM(u.username)
    SET p.room_allocation = u.RoomId
    WHERE (p.room_allocation IS NULL OR TRIM(p.room_allocation) = '' OR LOWER(TRIM(p.room_allocation)) = 'unallocated')
      AND u.RoomId IS NOT NULL AND TRIM(u.RoomId) != '' AND LOWER(TRIM(u.RoomId)) != 'unallocated'
");
echo "General sync: Updated $stmtSync missing profile room allocations from users table.\n";

// 5. Sync wardens based on room numbers
$stmtWardenSync = $db->exec("
    UPDATE profile p
    JOIN rooms_groups_details rgd ON REPLACE(REPLACE(TRIM(p.room_allocation), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(rgd.room_number), ' ', ''), '-', '')
    SET p.warden = rgd.warden_name
    WHERE rgd.warden_name IS NOT NULL AND TRIM(rgd.warden_name) != '' AND (p.warden IS NULL OR p.warden = '' OR p.warden != rgd.warden_name)
");
echo "General sync: Updated $stmtWardenSync profile wardens from rooms_groups_details.\n";

echo "\n=== VERIFYING FINAL RECORD FOR $reg_no ===\n";
$stmtVerP = $db->prepare("SELECT id, full_name, reg_no, email, room_allocation, warden, hostel_name FROM profile WHERE reg_no = :reg");
$stmtVerP->execute([':reg' => $reg_no]);
print_r($stmtVerP->fetch(PDO::FETCH_ASSOC));

$stmtVerU = $db->prepare("SELECT id, username, full_name, RoomId, HostelName FROM users WHERE username = :reg");
$stmtVerU->execute([':reg' => $reg_no]);
print_r($stmtVerU->fetch(PDO::FETCH_ASSOC));
