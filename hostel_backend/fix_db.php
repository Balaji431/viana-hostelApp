<?php
require_once 'config/database.php';
$database = new Database();
$db = $database->getConnection();

try {
    // Attempt to add auto_increment to profile.id
    // We need to make sure it's the primary key first (already is, confirmed by subagent)
    $db->exec("ALTER TABLE profile MODIFY id INT(11) AUTO_INCREMENT");
    echo json_encode(["success" => true, "message" => "Auto-increment added to profile.id"]);
} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
}
?>
