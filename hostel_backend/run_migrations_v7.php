<?php
require_once 'config/database.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

if (!$conn) {
    die("Database connection failed");
}

function columnExists($conn, $table, $column) {
    $result = $conn->query("SHOW COLUMNS FROM `$table` LIKE '$column'");
    return $result && $result->num_rows > 0;
}

echo "Starting Migration v7...\n";

// 1. Alter payments table
$payments_cols = [
    'student_name' => "ALTER TABLE payments ADD COLUMN student_name VARCHAR(100) NULL",
    'reg_number' => "ALTER TABLE payments ADD COLUMN reg_number VARCHAR(50) NULL",
    'gateway_response' => "ALTER TABLE payments ADD COLUMN gateway_response TEXT NULL",
    'user_id' => "ALTER TABLE payments ADD COLUMN user_id INT NULL",
    'ip_address' => "ALTER TABLE payments ADD COLUMN ip_address VARCHAR(45) NULL"
];

foreach ($payments_cols as $col => $sql) {
    if (!columnExists($conn, 'payments', $col)) {
        if ($conn->query($sql)) {
            echo "Added column '$col' to payments table\n";
        } else {
            echo "Error adding column '$col' to payments: " . $conn->error . "\n";
        }
    } else {
        echo "Column '$col' already exists in payments table\n";
    }
}

// 2. Alter payment table
$payment_cols = [
    'gateway_response' => "ALTER TABLE payment ADD COLUMN gateway_response TEXT NULL",
    'user_id' => "ALTER TABLE payment ADD COLUMN user_id INT NULL",
    'ip_address' => "ALTER TABLE payment ADD COLUMN ip_address VARCHAR(45) NULL",
    'paid_at' => "ALTER TABLE payment ADD COLUMN paid_at DATETIME DEFAULT CURRENT_TIMESTAMP NULL"
];

foreach ($payment_cols as $col => $sql) {
    if (!columnExists($conn, 'payment', $col)) {
        if ($conn->query($sql)) {
            echo "Added column '$col' to payment table\n";
        } else {
            echo "Error adding column '$col' to payment: " . $conn->error . "\n";
        }
    } else {
        echo "Column '$col' already exists in payment table\n";
    }
}

// 3. Create app_errors table
$create_errors_table = "CREATE TABLE IF NOT EXISTS app_errors (
    id INT AUTO_INCREMENT PRIMARY KEY,
    error_message TEXT,
    stack_trace TEXT,
    user VARCHAR(100),
    device VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;";

if ($conn->query($create_errors_table)) {
    echo "Ensured app_errors table exists\n";
} else {
    echo "Error creating app_errors table: " . $conn->error . "\n";
}

echo "Migration finished successfully.";
?>
