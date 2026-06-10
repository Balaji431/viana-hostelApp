<?php
require_once 'config/database.php';
$database = new Database();
$db = $database->getConnection();

try {
    // Modify the role column to include security and maintenance
    // We use VARCHAR(50) to be flexible and avoid ENUM truncation errors
    $sql = "ALTER TABLE users MODIFY COLUMN role VARCHAR(50) NOT NULL DEFAULT 'student'";
    $db->exec($sql);
    
    echo "Success: 'role' column updated to allow any staff role.";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage();
}
?>
