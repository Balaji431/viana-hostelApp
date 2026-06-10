<?php
$conn = new mysqli('127.0.0.1', 'user', 'vstay2026', 'stay_simats', 3307);
if ($conn->connect_error) die("Connect Error: " . $conn->connect_error);

$conn->query("UPDATE mapping_staff SET username = 'warden1' WHERE id = 22");
echo "Venkatesh updated with username 'warden1'\n";
$conn->close();
?>
