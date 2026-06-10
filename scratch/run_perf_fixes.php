<?php
require 'hostel_backend/config/database.php';

$db = new Database();
$conn = $db->getConnection();

if (!$conn) { echo "DB connection failed\n"; exit(1); }

// Check if index already exists, add only if missing
$check = $conn->query("SHOW INDEX FROM room_master WHERE Key_name = 'idx_rm_order'");
if ($check->rowCount() === 0) {
    $conn->exec("CREATE INDEX idx_rm_order ON room_master (building_code, floor_no, block_no, room_no)");
    echo "Created index idx_rm_order\n";
} else {
    echo "Index idx_rm_order already exists\n";
}

// Test query speed with new index
$start = microtime(true);
$r = $conn->query("SELECT * FROM room_master ORDER BY building_code, floor_no, block_no, room_no");
$rooms = $r->fetchAll(PDO::FETCH_ASSOC);
$elapsed = round((microtime(true) - $start) * 1000, 2);
echo "Query time: {$elapsed}ms for " . count($rooms) . " rows\n";
echo "Raw JSON: " . number_format(strlen(json_encode($rooms))) . " bytes\n";
echo "Gzipped:  " . number_format(strlen(gzencode(json_encode($rooms), 6))) . " bytes (" .
    round(strlen(gzencode(json_encode($rooms), 6)) / strlen(json_encode($rooms)) * 100) . "% of original)\n";

// Copy old cache to uploads/ if not already done
$oldCache = __DIR__ . '/hostel_backend/rooms/cache_locations.json';
$newCache = __DIR__ . '/hostel_backend/uploads/cache_locations.json';
if (file_exists($oldCache) && !file_exists($newCache)) {
    copy($oldCache, $newCache);
    echo "Migrated location cache to uploads/\n";
} elseif (file_exists($newCache)) {
    echo "Location cache already in uploads/\n";
}
echo "Done.\n";
?>
