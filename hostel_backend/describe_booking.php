<?php
require_once 'config/database.php';
$database = new Database();
$db = $database->getConnection();
$stmt = $db->query("DESCRIBE new_room_booking");
$columns = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo json_encode($columns, JSON_PRETTY_PRINT);
?>
