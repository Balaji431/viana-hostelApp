<?php
require_once __DIR__ . '/../config/database.php';
$database = new Database();
$db = $database->getConnection();

echo "<h2>User 1111111111:</h2>";
$stmt = $db->query("SELECT * FROM users WHERE username = '1111111111' OR id = '1111111111'");
if ($stmt) {
    while($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        echo "<pre>"; print_r($row); echo "</pre>";
    }
}

echo "<h2>Parent User 1111111111:</h2>";
$stmt2 = $db->query("SELECT * FROM parent_users WHERE parent_id = '1111111111' OR id = '1111111111'");
if ($stmt2) {
    while($row = $stmt2->fetch(PDO::FETCH_ASSOC)) {
        echo "<pre>"; print_r($row); echo "</pre>";
    }
}
?>
