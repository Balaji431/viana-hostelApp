<?php
require_once 'config/database.php';
$database = new Database();
$db = $database->getConnection();

try {
    // Attempt to add auto_increment to users.id as well
    $db->exec("ALTER TABLE users MODIFY id INT(11) AUTO_INCREMENT");
    echo json_encode(["success" => true, "message" => "Auto-increment verified/added to users.id"]);
} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
}
?>
