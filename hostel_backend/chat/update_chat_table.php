<?php
header('Content-Type: application/json');

require_once '../config/database.php';

$database = new Database();
$db = $database->getConnection();

try {
    // Check if column already exists
    $check = $db->query("SHOW COLUMNS FROM chat_messages LIKE 'status'");
    $exists = $check->fetch(PDO::FETCH_ASSOC);

    if ($exists) {
        echo json_encode([
            "success" => true,
            "message" => "Status column already exists"
        ]);
        exit();
    }

    // Add status column
    $sql = "ALTER TABLE chat_messages 
            ADD COLUMN status ENUM('sent','delivered','seen') DEFAULT 'sent'";

    $db->exec($sql);

    // Also add last_seen column to users table for online status
    $db->exec("ALTER TABLE users ADD COLUMN last_seen TIMESTAMP NULL DEFAULT NULL");

    echo json_encode([
        "success" => true,
        "message" => "Status column and last_seen column added successfully"
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Error: " . $e->getMessage()
    ]);
}
?>