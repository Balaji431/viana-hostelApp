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



/**
 * Recreates the attendance and attendance_tracking tables.
 * Access via browser: http://192.168.137.1/hostel_management_app/hostel_backend/attendance/setup_attendance_tables.php
 */
include_once '../config/database.php';
$db = (new Database())->getConnection();

echo "=== Attendance Tables Setup ===\n\n";

try {
    // 1. attendance table — used by both student self-mark and warden manual marking
    $db->exec("CREATE TABLE IF NOT EXISTS `attendance` (
        `id`         INT(11)      NOT NULL AUTO_INCREMENT,
        `student_id` INT(11)      NOT NULL,
        `status`     VARCHAR(10)  NOT NULL COMMENT 'IN or OUT (self) | present, absent, half_day (warden)',
        `log_time`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `source`     VARCHAR(20)  NOT NULL DEFAULT 'manual' COMMENT 'manual | warden',
        PRIMARY KEY (`id`),
        KEY `idx_student_date` (`student_id`, `log_time`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;");
    echo "✅ Table 'attendance' created (or already exists).\n";

    // 2. attendance_tracking — tracks how many times warden edited attendance for a date
    $db->exec("CREATE TABLE IF NOT EXISTS `attendance_tracking` (
        `id`              INT(11)  NOT NULL AUTO_INCREMENT,
        `attendance_date` DATE     NOT NULL UNIQUE,
        `edit_count`      INT(11)  NOT NULL DEFAULT 0,
        `last_edited_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;");
    echo "✅ Table 'attendance_tracking' created (or already exists).\n";

    echo "\n=== Both tables are ready. ===\n";
    echo "Students can now mark IN/OUT manually.\n";
    echo "Wardens can now mark attendance via the warden panel.\n";

} catch (PDOException $e) {
    echo "❌ Error: " . $e->getMessage() . "\n";
}
?>
