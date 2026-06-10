<?php
require_once __DIR__ . '/../config/database.php';
$database = new Database();
$db = $database->getConnection();

echo "<h2>Request WRD-1779077977:</h2>";
$stmt = $db->query("SELECT * FROM request1 WHERE request_id = 'WRD-1779077977'");
if ($stmt) {
    while($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        echo "<pre>"; print_r($row); echo "</pre>";
    }
}

echo "<h2>Request MNT-1778236261:</h2>";
$stmt2 = $db->query("SELECT * FROM request1 WHERE request_id = 'MNT-1778236261'");
if ($stmt2) {
    while($row = $stmt2->fetch(PDO::FETCH_ASSOC)) {
        echo "<pre>"; print_r($row); echo "</pre>";
    }
}
?>
