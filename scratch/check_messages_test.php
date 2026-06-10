<?php
require_once 'hostel_backend/config/database.php';
$database = new Database();
$db = $database->getConnection();

echo "--- CHAT MESSAGES ---\n";
$stmt = $db->prepare("SELECT * FROM chat_messages ORDER BY id DESC LIMIT 20");
$stmt->execute();
print_r($stmt->fetchAll(PDO::FETCH_ASSOC));

echo "--- REQUESTS ---\n";
$stmt = $db->prepare("SELECT * FROM request1 ORDER BY id DESC LIMIT 10");
$stmt->execute();
print_r($stmt->fetchAll(PDO::FETCH_ASSOC));
?>
