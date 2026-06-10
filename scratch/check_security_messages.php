<?php
require_once 'hostel_backend/config/database.php';
$database = new Database();
$db = $database->getConnection();

echo "--- SECURITY CHAT MESSAGES ---\n";
$stmt = $db->prepare("SELECT * FROM chat_messages WHERE request_id LIKE 'SEC%' ORDER BY id DESC LIMIT 20");
$stmt->execute();
print_r($stmt->fetchAll(PDO::FETCH_ASSOC));
?>
