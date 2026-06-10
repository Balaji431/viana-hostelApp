<?php
require_once 'config/database.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

echo "--- ROOM CHANGE REQUESTS ---\n";
$res1 = $conn->query("SELECT * FROM room_change_requests");
if ($res1) {
    while ($row = $res1->fetch_assoc()) {
        print_r($row);
    }
} else {
    echo "Error querying room_change_requests: " . $conn->error . "\n";
}

echo "\n--- REQUEST1 (Last 10 rows) ---\n";
$res2 = $conn->query("SELECT * FROM request1 ORDER BY id DESC LIMIT 10");
if ($res2) {
    while ($row = $res2->fetch_assoc()) {
        print_r($row);
    }
} else {
    echo "Error querying request1: " . $conn->error . "\n";
}
?>
