<?php
ini_set('display_errors', 1);
error_reporting(E_ALL);
require_once 'config/database.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

if (!$conn) {
    die("Connection failed");
}

function columnExists($conn, $table, $column) {
    $result = $conn->query("SHOW COLUMNS FROM `$table` LIKE '$column'");
    return $result->num_rows > 0;
}

echo "Starting Migration V5...\n";

// Add room_code to room_master if it doesn't exist
if (!columnExists($conn, 'room_master', 'room_code')) {
    $conn->query("ALTER TABLE room_master ADD COLUMN room_code VARCHAR(255) DEFAULT NULL AFTER room_no");
    echo "Added room_code to room_master table\n";
} else {
    echo "room_code already exists in room_master table\n";
}

echo "Migration finished successfully.";
?>
