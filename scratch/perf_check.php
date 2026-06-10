<?php
require 'hostel_backend/config/database.php';
$db = new DatabaseMysqli();
$conn = $db->getConnection();

// Row count
$r = $conn->query("SELECT COUNT(*) as cnt FROM room_master");
$row = $r->fetch_assoc();
echo "room_master rows: " . $row['cnt'] . "\n";

// Check indexes on room_master
$r2 = $conn->query("SHOW INDEX FROM room_master");
echo "\nIndexes on room_master:\n";
while ($idx = $r2->fetch_assoc()) {
    echo " - " . $idx['Key_name'] . " on " . $idx['Column_name'] . "\n";
}

// Check hostel_rooms row count
$r3 = $conn->query("SELECT COUNT(*) as cnt FROM hostel_rooms");
$row3 = $r3->fetch_assoc();
echo "\nhostel_rooms rows: " . $row3['cnt'] . "\n";

// Check indexes on hostel_rooms
$r4 = $conn->query("SHOW INDEX FROM hostel_rooms");
echo "\nIndexes on hostel_rooms:\n";
while ($idx = $r4->fetch_assoc()) {
    echo " - " . $idx['Key_name'] . " on " . $idx['Column_name'] . "\n";
}

// Sample room_master row
$r5 = $conn->query("SELECT * FROM room_master LIMIT 1");
$sample = $r5->fetch_assoc();
if ($sample) {
    echo "\nSample room_master columns: " . implode(", ", array_keys($sample)) . "\n";
}

// Timing test
$start = microtime(true);
$r6 = $conn->query("SELECT * FROM room_master ORDER BY location_name, building_code, floor_no, block_no, room_no");
$all = $r6->fetch_all(MYSQLI_ASSOC);
$elapsed = round((microtime(true) - $start) * 1000, 2);
echo "\nQuery time for full room_master fetch: {$elapsed}ms\n";
echo "Result rows: " . count($all) . "\n";
echo "JSON size: " . strlen(json_encode($all)) . " bytes\n";
