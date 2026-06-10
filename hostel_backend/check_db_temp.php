<?php
require_once 'config/database.php';
$dbClass = new DatabaseMysqli();
$conn = $dbClass->getConnection();

if (!$conn) {
    die("Connection failed\n");
}

echo "=== MAPPING STAFF RECORDS ===\n";
$res = $conn->query("SELECT * FROM mapping_staff");
while ($row = $res->fetch_assoc()) {
    print_r($row);
}
?>
