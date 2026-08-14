<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';
$db = (new Database())->getConnection();

echo "=== mapping_staff entries for Kanita K (29617) ===\n";
$r = $db->query("SELECT id, name, floor_name, hostel_name, role FROM mapping_staff WHERE username = '29617' OR staff_bio_id = '29617' ORDER BY id")->fetchAll(PDO::FETCH_ASSOC);
foreach ($r as $row) {
    echo "  id={$row['id']} | floor: [{$row['floor_name']}] | hostel: [{$row['hostel_name']}] | role: {$row['role']}\n";
}

echo "\n=== All rooms Kanita K would get in get_system_stats (warden_username=29617) ===\n";
$stmt = $db->prepare("
    SELECT rgd.room_number, rgd.group_name, rgd.total_beds, rgd.occupied_beds, rgd.available_beds
    FROM rooms_groups_details rgd
    JOIN mapping_staff ms ON (
        LOWER(TRIM(rgd.hostel_name)) = LOWER(TRIM(ms.hostel_name))
        AND LOWER(rgd.group_name) LIKE CONCAT('%', LOWER(ms.floor_name), '%')
    )
    WHERE ms.username = '29617' OR ms.staff_bio_id = '29617'
       OR rgd.warden_user_id = '29617'
    ORDER BY rgd.group_name, rgd.room_number
");
$stmt->execute();
$rooms = $stmt->fetchAll(PDO::FETCH_ASSOC);

$totalBeds = 0; $totalOcc = 0; $totalAvail = 0;
foreach ($rooms as $room) {
    echo "  Room: {$room['room_number']} | Floor: {$room['group_name']} | Total:{$room['total_beds']} Occ:{$room['occupied_beds']} Avail:{$room['available_beds']}\n";
    $totalBeds += $room['total_beds'];
    $totalOcc += $room['occupied_beds'];
    $totalAvail += $room['available_beds'];
}
echo "\nTOTAL: beds=$totalBeds | occupied=$totalOcc | available=$totalAvail | rooms=" . count($rooms) . "\n";
