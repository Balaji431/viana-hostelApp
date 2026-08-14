<?php
// Simulate exactly what sync_new_students.php does for student 192511250
// using the local DB to trace the warden lookup step by step

require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

$roomNo = 'T-32 F02- W0-R16';  // exactly what the booked-rooms API returns

echo "=== Step 1: Room lookup in rooms_groups_details ===\n";
echo "Input roomNo: [$roomNo]\n";

$wStmt = $db->prepare("
    SELECT room_number, warden_name, group_name 
    FROM rooms_groups_details 
    WHERE (room_number = :rn 
        OR REPLACE(REPLACE(TRIM(room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(:rn2), ' ', ''), '-', ''))
      AND warden_name IS NOT NULL AND warden_name != ''
    LIMIT 1
");
$wStmt->execute([':rn' => $roomNo, ':rn2' => $roomNo]);
$row = $wStmt->fetch(PDO::FETCH_ASSOC);

if ($row) {
    echo "Found room: {$row['room_number']} | group: {$row['group_name']} | warden_name: {$row['warden_name']}\n";
} else {
    echo "❌ No match found in rooms_groups_details\n";
    
    // Show what rooms_groups_details actually has for Second Floor
    echo "\n=== rooms_groups_details for Second Floor (raw data) ===\n";
    $dbgStmt = $db->query("SELECT DISTINCT room_number, group_name, warden_name FROM rooms_groups_details WHERE group_name LIKE '%Second%' LIMIT 5");
    foreach ($dbgStmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
        echo "  room: [{$r['room_number']}] | group: {$r['group_name']} | warden: [{$r['warden_name']}]\n";
        echo "  Normalized room: [" . str_replace([' ','-'], '', trim($r['room_number'])) . "]\n";
    }
    
    echo "\n  Normalized input: [" . str_replace([' ','-'], '', trim($roomNo)) . "]\n";
}

echo "\n=== Step 2: Fallback - mapping_staff by hostel (the bug) ===\n";
$fallback = $db->prepare("
    SELECT name FROM mapping_staff 
    WHERE LOWER(role) = 'warden' 
      AND (LOWER(hostel_name) = LOWER(:hn) OR LOWER(:hn2) LIKE CONCAT('%', LOWER(hostel_name), '%')) 
    LIMIT 1
");
$fallback->execute([':hn' => 'Vaigai Hostel', ':hn2' => 'Vaigai Hostel']);
$fallbackWarden = $fallback->fetchColumn();
echo "Fallback would give: [$fallbackWarden]\n";

echo "\n=== Current profile.warden for student 192511250 ===\n";
$p = $db->query("SELECT warden, room_allocation FROM profile WHERE reg_no = '192511250'")->fetch(PDO::FETCH_ASSOC);
print_r($p);
