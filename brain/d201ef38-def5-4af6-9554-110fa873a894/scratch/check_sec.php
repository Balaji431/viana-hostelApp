<?php
require_once 'c:\xampp\htdocs\hostelapp\hostel_backend\config\database.php';
$db = new Database();
$conn = $db->getConnection();
$sec1 = $conn->query("SELECT count(*) FROM security_users")->fetchColumn();
$sec2 = $conn->query("SELECT count(*) FROM users WHERE LOWER(role) = 'security'")->fetchColumn();
$sec3 = $conn->query("SELECT count(*) FROM staff_users WHERE LOWER(role) = 'security'")->fetchColumn();
echo "security_users: $sec1, users: $sec2, staff_users: $sec3";
?>
