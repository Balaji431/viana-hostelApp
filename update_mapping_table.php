<?php
$conn = new mysqli('127.0.0.1', 'user', 'vstay2026', 'stay_simats', 3307);
if ($conn->connect_error) die("Connect Error: " . $conn->connect_error);

$sql = "ALTER TABLE mapping_staff 
        ADD COLUMN hostel_name VARCHAR(100) AFTER username, 
        ADD COLUMN floor_name VARCHAR(100) AFTER hostel_name, 
        ADD COLUMN wing_name VARCHAR(100) AFTER floor_name";

if ($conn->query($sql)) {
    echo "Columns added to mapping_staff successfully\n";
} else {
    echo "Error adding columns: " . $conn->error . "\n";
}

$conn->close();
?>
