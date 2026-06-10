<?php
require_once __DIR__ . '/../config/database.php';
$database = new Database();
$db = $database->getConnection();

echo "<h2>User bharat1:</h2>";
$stmt = $db->query("SELECT * FROM users WHERE username = 'bharat1'");
if ($stmt) {
    while($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        echo "<pre>"; print_r($row); echo "</pre>";
    }
}

echo "<h2>User with ID 1137:</h2>";
$stmt2 = $db->query("SELECT * FROM users WHERE id = 1137");
if ($stmt2) {
    while($row = $stmt2->fetch(PDO::FETCH_ASSOC)) {
        echo "<pre>"; print_r($row); echo "</pre>";
    }
}

echo "<h2>User rajesh1:</h2>";
$stmt3 = $db->query("SELECT * FROM users WHERE username = 'rajesh1'");
if ($stmt3) {
    while($row = $stmt3->fetch(PDO::FETCH_ASSOC)) {
        echo "<pre>"; print_r($row); echo "</pre>";
    }
}

echo "<h2>User with ID 1159:</h2>";
$stmt4 = $db->query("SELECT * FROM users WHERE id = 1159");
if ($stmt4) {
    while($row = $stmt4->fetch(PDO::FETCH_ASSOC)) {
        echo "<pre>"; print_r($row); echo "</pre>";
    }
}
?>
