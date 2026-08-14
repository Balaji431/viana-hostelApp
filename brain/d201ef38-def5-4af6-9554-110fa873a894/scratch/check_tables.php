<?php
require_once 'c:\xampp\htdocs\hostelapp\hostel_backend\config\database.php';
$db = new Database();
$conn = $db->getConnection();
$stmt = $conn->query("SHOW TABLES");
$tables = $stmt->fetchAll(PDO::FETCH_COLUMN);
print_r($tables);
?>
