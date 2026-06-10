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

require_once 'config.php';

try {
    $database = new RoomChangeDB();
    $db = $database->getConnection();
    
    // Create the room_change_requests table
    $sql = "
    CREATE TABLE IF NOT EXISTS `room_change_requests` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `request_id` varchar(50) NOT NULL,
      `student_id` int(11) NOT NULL,
      `student_name` varchar(100) NOT NULL,
      `student_reg_no` varchar(50) NOT NULL,
      `current_room` varchar(50) NOT NULL,
      `requested_room` varchar(50) NOT NULL,
      `reason` text NOT NULL,
      `status` enum('pending','approved','rejected','completed') NOT NULL DEFAULT 'pending',
      `processed_by` int(11) DEFAULT NULL,
      `processed_by_name` varchar(100) DEFAULT NULL,
      `remarks` text DEFAULT NULL,
      `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
      `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
      PRIMARY KEY (`id`),
      UNIQUE KEY `request_id` (`request_id`),
      KEY `student_id` (`student_id`),
      KEY `status` (`status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    
    CREATE TABLE IF NOT EXISTS `room_change_logs` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `request_id` varchar(50) NOT NULL,
      `student_id` int(11) NOT NULL,
      `action` varchar(50) NOT NULL,
      `performed_by` int(11) NOT NULL,
      `notes` text,
      `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
      PRIMARY KEY (`id`),
      KEY `request_id` (`request_id`),
      KEY `student_id` (`student_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ";
    
    $db->exec($sql);
    
    // Add columns one by one if they don't exist (using raw SQL)
    $db->exec("ALTER TABLE room_change_requests ADD COLUMN IF NOT EXISTS student_name varchar(100) NOT NULL AFTER student_id");
    $db->exec("ALTER TABLE room_change_requests ADD COLUMN IF NOT EXISTS student_reg_no varchar(50) NOT NULL AFTER student_name");
    $db->exec("ALTER TABLE room_change_requests ADD COLUMN IF NOT EXISTS processed_by_name varchar(100) DEFAULT NULL AFTER processed_by");

    echo json_encode([
        'status' => 'success',
        'message' => 'Database tables and columns verified/created successfully'
    ]);
    
} catch(PDOException $e) {
    echo json_encode([
        'status' => 'error',
        'message' => 'Database error: ' . $e->getMessage()
    ]);
} catch(Exception $e) {
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}
?>
