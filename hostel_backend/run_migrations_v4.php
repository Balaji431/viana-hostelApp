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

function tableExists($conn, $table) {
    $result = $conn->query("SHOW TABLES LIKE '$table'");
    return $result->num_rows > 0;
}

echo "Starting Migration V4...\n";

// 1. Update rooms / hostel_rooms
// The prompt says 'rooms', but the app uses 'hostel_rooms'. I'll update 'hostel_rooms' to match app logic.
if (!columnExists($conn, 'hostel_rooms', 'blocked_by')) {
    $conn->query("ALTER TABLE hostel_rooms ADD COLUMN blocked_by VARCHAR(20) NULL");
    echo "Added blocked_by to hostel_rooms\n";
}
if (!columnExists($conn, 'hostel_rooms', 'blocked_until')) {
    $conn->query("ALTER TABLE hostel_rooms ADD COLUMN blocked_until DATETIME NULL");
    $conn->query("ALTER TABLE hostel_rooms ADD INDEX idx_blocked_until (blocked_until)");
    echo "Added blocked_until to hostel_rooms\n";
}

// 2. Update room_allocations
// Modify Enum to include new statuses
$conn->query("ALTER TABLE room_allocations MODIFY COLUMN allocation_status ENUM(
    'draft','submitted','under_review','auto_matched',
    'payment_pending','approved','rejected','waitlisted','payment_expired','cancelled'
) DEFAULT 'draft'");
echo "Updated room_allocations.allocation_status ENUM\n";

if (!columnExists($conn, 'room_allocations', 'payment_deadline')) {
    $conn->query("ALTER TABLE room_allocations ADD COLUMN payment_deadline DATETIME NULL");
    echo "Added payment_deadline to room_allocations\n";
}
if (!columnExists($conn, 'room_allocations', 'paid_at')) {
    $conn->query("ALTER TABLE room_allocations ADD COLUMN paid_at DATETIME NULL");
    echo "Added paid_at to room_allocations\n";
}

// 3. Create/Update students table
// Since students table might not exist but user requested ALTER, I'll CREATE it if missing.
// It should probably link to users.id
if (!tableExists($conn, 'students')) {
    $conn->query("CREATE TABLE students (
        id VARCHAR(20) PRIMARY KEY,
        user_id INT NOT NULL,
        current_room_id INT NULL,
        check_in_date DATE NULL,
        renewal_date DATE NULL,
        FOREIGN KEY (user_id) REFERENCES users(id),
        FOREIGN KEY (current_room_id) REFERENCES hostel_rooms(id)
    )");
    echo "Created students table\n";
} else {
    if (!columnExists($conn, 'students', 'current_room_id')) {
        $conn->query("ALTER TABLE students ADD COLUMN current_room_id INT NULL");
        $conn->query("ALTER TABLE students ADD FOREIGN KEY (current_room_id) REFERENCES hostel_rooms(id)");
    }
    if (!columnExists($conn, 'students', 'check_in_date')) {
        $conn->query("ALTER TABLE students ADD COLUMN check_in_date DATE NULL");
    }
    if (!columnExists($conn, 'students', 'renewal_date')) {
        $conn->query("ALTER TABLE students ADD COLUMN renewal_date DATE NULL");
    }
    echo "Updated students table\n";
}

// 4. Create payments table
$conn->query("CREATE TABLE IF NOT EXISTS payments (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  student_id VARCHAR(20) NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  receipt_number VARCHAR(40) NOT NULL UNIQUE,
  status ENUM('paid','pending','failed') DEFAULT 'pending',
  description VARCHAR(200),
  paid_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (student_id) REFERENCES students(id)
)");
echo "Ensured payments table exists\n";

echo "Migration finished successfully.";
?>
