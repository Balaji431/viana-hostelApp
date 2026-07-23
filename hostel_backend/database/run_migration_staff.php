<?php
require_once __DIR__ . '/../config/database.php';
$database = new Database();
$db = $database->getConnection();

echo "Starting migration...\n";

// 1. Create staff_users table
$sql1 = "
CREATE TABLE IF NOT EXISTS staff_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    bio_id VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    name VARCHAR(255),
    email VARCHAR(255) NULL,
    phone VARCHAR(50) NULL,
    department VARCHAR(100) NULL,
    designation VARCHAR(100) NULL,
    role VARCHAR(50) NULL,
    raw_api_data JSON NULL,
    is_active TINYINT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_staff_bio_id (bio_id)
)";
try {
    $db->exec($sql1);
    echo "Table staff_users created or already exists.\n";
} catch (Exception $e) {
    echo "Error creating staff_users: " . $e->getMessage() . "\n";
}

// 2. Add staff_bio_id to mapping_staff
try {
    $check = $db->query("SHOW COLUMNS FROM mapping_staff LIKE 'staff_bio_id'");
    if ($check->rowCount() == 0) {
        $db->exec("ALTER TABLE mapping_staff ADD COLUMN staff_bio_id VARCHAR(50) NULL AFTER username");
        echo "Column staff_bio_id added to mapping_staff.\n";
    } else {
        echo "Column staff_bio_id already exists in mapping_staff.\n";
    }
} catch (Exception $e) {
    echo "Error altering mapping_staff: " . $e->getMessage() . "\n";
}

echo "Migration complete.\n";
?>
