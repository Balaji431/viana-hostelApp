<?php
require_once 'config/database.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

$queries = [
    "CREATE TABLE IF NOT EXISTS room_preferences (
      id BIGINT AUTO_INCREMENT PRIMARY KEY,
      student_id INT NOT NULL,
      room_id INT NOT NULL,
      priority_order TINYINT NOT NULL,
      status ENUM('draft','submitted','cancelled') DEFAULT 'draft',
      submitted_at DATETIME NULL,
      UNIQUE KEY uniq_student_room (student_id, room_id),
      UNIQUE KEY uniq_student_priority (student_id, priority_order),
      FOREIGN KEY (student_id) REFERENCES users(id),
      FOREIGN KEY (room_id) REFERENCES hostel_rooms(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;",

    "CREATE TABLE IF NOT EXISTS room_allocations (
      id BIGINT AUTO_INCREMENT PRIMARY KEY,
      student_id INT NOT NULL UNIQUE,
      allocated_room_id INT NULL,
      allocation_status ENUM('draft','submitted','under_review','auto_matched','approved','rejected','waitlisted') DEFAULT 'draft',
      queue_position INT NULL,
      allocation_score INT DEFAULT 0,
      approved_by INT NULL,
      approved_at DATETIME NULL,
      submitted_at DATETIME NULL,
      FOREIGN KEY (student_id) REFERENCES users(id),
      FOREIGN KEY (allocated_room_id) REFERENCES hostel_rooms(id),
      FOREIGN KEY (approved_by) REFERENCES users(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;"
];

foreach ($queries as $query) {
    if ($conn->query($query)) {
        echo "Success: Table created/verified.\n";
    } else {
        echo "Error: " . $conn->error . "\n";
    }
}
?>
