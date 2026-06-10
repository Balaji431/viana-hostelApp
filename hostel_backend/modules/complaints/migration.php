<?php
ini_set('display_errors', 1);
error_reporting(E_ALL);
require_once __DIR__ . '/../../config/database.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

if (!$conn) {
    die(json_encode(["success" => false, "message" => "Database connection failed"]));
}

echo "Starting Complaints & Feedback migration...\n";

// 1. Create complaints table
$q1 = "CREATE TABLE IF NOT EXISTS complaints (
    id INT AUTO_INCREMENT PRIMARY KEY,
    student_id INT NOT NULL,
    staff_username VARCHAR(100) NOT NULL,
    staff_role VARCHAR(50) NOT NULL,
    message TEXT NOT NULL,
    status ENUM('Pending', 'Under Review', 'Resolved') DEFAULT 'Pending',
    admin_reply TEXT NULL,
    admin_replied_at DATETIME NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (student_id) REFERENCES users(id),
    INDEX idx_student (student_id),
    INDEX idx_staff (staff_username),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";

if ($conn->query($q1)) {
    echo "Complaints table created or already exists.\n";
} else {
    echo "Error creating complaints table: " . $conn->error . "\n";
}

// 2. Create feedbacks table
$q2 = "CREATE TABLE IF NOT EXISTS feedbacks (
    id INT AUTO_INCREMENT PRIMARY KEY,
    student_id INT NOT NULL,
    staff_username VARCHAR(100) NOT NULL,
    staff_role VARCHAR(50) NOT NULL,
    rating INT NOT NULL,
    message TEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (student_id) REFERENCES users(id),
    INDEX idx_feedback_student (student_id),
    INDEX idx_feedback_staff (staff_username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";

if ($conn->query($q2)) {
    echo "Feedbacks table created or already exists.\n";
} else {
    echo "Error creating feedbacks table: " . $conn->error . "\n";
}

echo "Migration complete.\n";
?>
