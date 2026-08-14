<?php
require_once 'c:\xampp\htdocs\hostelapp\hostel_backend\config\database.php';
$db = new Database();
$conn = $db->getConnection();
if (!$conn) {
    echo "Connection failed\n";
    exit;
}
$stmt = $conn->query("SELECT * FROM app_errors ORDER BY id DESC LIMIT 10");
$errors = $stmt->fetchAll(PDO::FETCH_ASSOC);
print_r($errors);
?>
