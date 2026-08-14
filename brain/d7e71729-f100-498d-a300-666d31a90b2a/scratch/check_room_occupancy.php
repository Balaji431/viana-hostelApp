<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';
$db = (new Database())->getConnection();

// Check local rooms_groups_details for room T32-F02-W0-R16
$r = $db->query("
    SELECT room_number, group_name, total_beds, occupied_beds, assigned_pending, available_beds, warden_name 
    FROM rooms_groups_details 
    WHERE REPLACE(REPLACE(TRIM(room_number),' ',''),'-','') = 'T32F02W0R16'
")->fetch(PDO::FETCH_ASSOC);

echo "=== LOCAL rooms_groups_details for T32-F02-W0-R16 ===\n";
print_r($r);

echo "\n=== EXTERNAL API says ===\n";
echo "occupiedBeds:  3\n";
echo "availableBeds: 1\n";
echo "assignedPending: 0\n";

echo "\n=== GAP ===\n";
if ($r) {
    $gap = $r['occupied_beds'] - 3;
    echo "Local occupied_beds:  {$r['occupied_beds']}  (External says 3) → diff: $gap\n";
    echo "Local available_beds: {$r['available_beds']} (External says 1)\n";
}

// Check how warden stats are calculated for Kanita K
echo "\n=== Warden stats query for Kanita K (username 29617) ===\n";
$stmt = $db->prepare("
    SELECT SUM(total_beds) as total, SUM(occupied_beds) as occupied, 
           SUM(available_beds) as available, COUNT(*) as rooms
    FROM rooms_groups_details 
    WHERE warden_name = 'Kanita K'
      AND group_name = 'Vaigai Hostel Second Floor'
");
$stmt->execute();
$stats = $stmt->fetch(PDO::FETCH_ASSOC);
print_r($stats);
