<?php
require_once 'config/database.php';

$database = new Database();
$db = $database->getConnection();

try {
    $db->exec("ALTER TABLE chat_messages ADD COLUMN status ENUM('sent','delivered','seen') DEFAULT 'sent'");
    echo "? Status column added\n";
    
    $db->exec("ALTER TABLE users ADD COLUMN last_seen TIMESTAMP NULL DEFAULT NULL");
    echo "? Last seen column added\n";
    
} catch (Exception $e) {
    echo "? Error: " . $e->getMessage() . "\n";
}
?>