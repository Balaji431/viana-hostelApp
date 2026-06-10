<?php
require_once 'C:/xampp/htdocs/hostelapp/hostel_backend/config/database.php';
$db = (new Database())->getConnection();

echo "=== PENDING IN room_change_requests ===\n";
$stmt = $db->query("SELECT * FROM room_change_requests WHERE status = 'pending'");
while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
    print_r($row);
}

echo "\n=== PENDING IN request1 ===\n";
$stmt = $db->query("SELECT * FROM request1 WHERE status = 'pending'");
while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
    print_r($row);
}
?>
