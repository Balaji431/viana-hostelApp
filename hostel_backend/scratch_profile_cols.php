<?php
require_once __DIR__ . '/config/database.php';
$database = new DatabaseMysqli();
$conn = $database->getConnection();

$res = $conn->query("DESCRIBE profile");
if ($res) {
    echo "=== Profile Table Columns ===\n";
    while ($row = $res->fetch_assoc()) {
        print_r($row);
    }
} else {
    echo "Error: " . $conn->error . "\n";
}
?>
