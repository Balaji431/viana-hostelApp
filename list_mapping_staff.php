<?php
$conn = new mysqli('127.0.0.1', 'user', 'vstay2026', 'stay_simats', 3307);
if ($conn->connect_error) die("Connect Error: " . $conn->connect_error);

$res = $conn->query("SELECT * FROM mapping_staff");
while($row = $res->fetch_assoc()) {
    print_r($row);
}
$conn->close();
?>
