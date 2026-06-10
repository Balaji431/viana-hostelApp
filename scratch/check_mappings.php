<?php
$conn = new mysqli('127.0.0.1', 'root', 'vstay2026', 'stay_simats', 3307);
if ($conn->connect_error) {
    die("Connection failed: " . $conn->connect_error);
}

$res = $conn->query("SELECT * FROM mapping_staff");
$mappings = [];
while ($row = $res->fetch_assoc()) {
    $mappings[] = $row;
}
echo json_encode($mappings, JSON_PRETTY_PRINT);
?>
