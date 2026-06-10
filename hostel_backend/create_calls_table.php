<?php
$host = "localhost";
$db_name = "stay_simats";
$username = "root";
$password = "vstay2026";
$port = 3307;

try {
    $conn = new mysqli($host, $username, $password, $db_name, $port);
    if ($conn->connect_error) {
        die("Connection failed: " . $conn->connect_error);
    }

    $sql = "CREATE TABLE IF NOT EXISTS active_calls (
        id INT AUTO_INCREMENT PRIMARY KEY,
        caller_id INT NOT NULL,
        caller_name VARCHAR(255) NOT NULL,
        target_id INT NOT NULL,
        channel_name VARCHAR(255) NOT NULL,
        status ENUM('ringing', 'accepted', 'rejected', 'ended') DEFAULT 'ringing',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )";

    if ($conn->query($sql) === TRUE) {
        echo "Success: active_calls table created.\n";
    } else {
        echo "Error: " . $conn->error . "\n";
    }
} catch (Exception $e) {
    echo "Fatal Error: " . $e->getMessage() . "\n";
}
?>
