<?php
require_once 'c:\xampp\htdocs\hostelapp\hostel_backend\config\database.php';
$db = new Database();
$conn = $db->getConnection();
$sql = "CREATE TABLE IF NOT EXISTS app_errors (
    id INT AUTO_INCREMENT PRIMARY KEY,
    error_message TEXT,
    stack_trace TEXT,
    user VARCHAR(255),
    device VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)";
$conn->exec($sql);
echo "Table created successfully.";
?>
