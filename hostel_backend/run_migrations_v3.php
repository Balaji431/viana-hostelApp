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

// 1. Update hostel_rooms
if (!columnExists($conn, 'hostel_rooms', 'blocked_by')) {
    $conn->query("ALTER TABLE hostel_rooms ADD COLUMN blocked_by INT NULL");
}
if (!columnExists($conn, 'hostel_rooms', 'blocked_until')) {
    $conn->query("ALTER TABLE hostel_rooms ADD COLUMN blocked_until DATETIME NULL");
    $conn->query("ALTER TABLE hostel_rooms ADD INDEX idx_blocked_until (blocked_until)");
}

// 2. Update room_allocations
$conn->query("ALTER TABLE room_allocations MODIFY COLUMN allocation_status ENUM('draft','submitted','under_review','auto_matched','payment_pending','approved','rejected','waitlisted','payment_expired','cancelled') DEFAULT 'draft'");

if (!columnExists($conn, 'room_allocations', 'payment_deadline')) {
    $conn->query("ALTER TABLE room_allocations ADD COLUMN payment_deadline DATETIME NULL");
}
if (!columnExists($conn, 'room_allocations', 'paid_at')) {
    $conn->query("ALTER TABLE room_allocations ADD COLUMN paid_at DATETIME NULL");
}

// 3. Create payments table
$conn->query("CREATE TABLE IF NOT EXISTS payments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    student_id INT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    receipt_number VARCHAR(40) NOT NULL UNIQUE,
    status ENUM('paid','pending','failed') DEFAULT 'pending',
    description VARCHAR(200),
    paid_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (student_id) REFERENCES users(id)
)");

echo "Migration finished successfully.";
?>
