<?php
require_once 'C:/xampp/htdocs/hostelapp/hostel_backend/config/database.php';
$db = (new Database())->getConnection();

echo "=== ALL IN room_change_requests ===\n";
$stmt = $db->query("SELECT * FROM room_change_requests");
while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
    print_r($row);
}

echo "\n=== ALL IN request1 ===\n";
$stmt = $db->query("SELECT * FROM request1");
while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
    print_r($row);
}
?>
