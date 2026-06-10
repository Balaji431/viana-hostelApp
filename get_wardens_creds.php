<?php
$conn = new mysqli('127.0.0.1', 'user', 'vstay2026', 'stay_simats', 3307);
if ($conn->connect_error) die("Connect Error: " . $conn->connect_error);
$res = $conn->query("SELECT id, username, full_name, role, password FROM users WHERE LOWER(role) = 'warden'");
$wardens = [];
while($row = $res->fetch_assoc()) {
    $wardens[] = $row;
}
echo json_encode($wardens, JSON_PRETTY_PRINT);
?>
