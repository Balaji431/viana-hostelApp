<?php
require_once __DIR__ . '/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();
    
    if ($db === null) {
        die(json_encode(["success" => false, "message" => "Database connection failed"]));
    }
    
    $sql = "CREATE TABLE IF NOT EXISTS activity_logs (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NULL,
        username VARCHAR(100) NULL,
        role VARCHAR(50) NULL,
        action VARCHAR(255) NOT NULL,
        target_table VARCHAR(100) NULL,
        previous TEXT NULL,
        after TEXT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";
    
    $db->exec($sql);
    echo json_encode(["success" => true, "message" => "Table activity_logs created successfully!"]);
} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Error creating table: " . $e->getMessage()]);
}
?>
