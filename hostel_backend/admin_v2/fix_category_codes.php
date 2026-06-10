<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

include '../config/db_config.php';

// Fix category_codes table structure
echo "Checking category_codes table structure...\n";

// Drop and recreate category_codes table with proper auto-increment primary key
$conn->query("DROP TABLE IF EXISTS category_codes");

$createTable = "CREATE TABLE category_codes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    category_id INT NOT NULL,
    code_name VARCHAR(255) NOT NULL,
    FOREIGN KEY (category_id) REFERENCES request_categories(id) ON DELETE CASCADE,
    INDEX (category_id)
)";

if ($conn->query($createTable)) {
    echo "category_codes table recreated successfully\n";
} else {
    echo "Error creating table: " . $conn->error . "\n";
}

// Check request_categories table structure
$result = $conn->query("DESCRIBE request_categories");
if ($result) {
    echo "request_categories table structure:\n";
    while ($row = $result->fetch_assoc()) {
        echo "- " . $row['Field'] . " (" . $row['Type'] . ")\n";
    }
}

$conn->close();
?>
