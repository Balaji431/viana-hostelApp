<?php
header('Content-Type: application/json');
require_once '../config/database.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

try {
    // Check if column already exists
    $check = $db->query("SHOW COLUMNS FROM mapping_staff LIKE 'username'");
    $exists = $check->fetch(PDO::FETCH_ASSOC);

    if ($exists) {
        echo json_encode([
            "success" => true,
            "message" => "Username column already exists in mapping_staff"
        ]);
        exit();
    }

    // Add username column
    $db->exec("ALTER TABLE mapping_staff ADD COLUMN username VARCHAR(100) AFTER phone");

    echo json_encode([
        "success" => true,
        "message" => "Username column added successfully to mapping_staff"
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Error: " . $e->getMessage()
    ]);
}
?>
