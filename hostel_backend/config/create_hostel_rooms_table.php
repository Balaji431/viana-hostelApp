<?php
require_once __DIR__ . '/database.php';

$tableSql = "CREATE TABLE IF NOT EXISTS hostel_rooms (
    id INT AUTO_INCREMENT PRIMARY KEY,
    hostel_id INT NULL,
    campus VARCHAR(255) NULL,
    campus_code VARCHAR(50) NULL,
    hostel_name VARCHAR(255) NOT NULL,
    building_code VARCHAR(50) NULL,
    hostel_type VARCHAR(50) NULL DEFAULT 'Girls',
    room_type VARCHAR(100) NULL,
    location_name VARCHAR(255) NULL,
    floor_code VARCHAR(50) NULL,
    floor VARCHAR(100) NULL,
    room_no VARCHAR(50) NOT NULL,
    wing_code VARCHAR(50) NULL,
    room_code VARCHAR(100) NULL,
    facility VARCHAR(100) NULL,
    bath_attached VARCHAR(10) NULL DEFAULT 'No',
    amount DECIMAL(10,2) DEFAULT 0.00,
    caution_dept DECIMAL(10,2) DEFAULT 5000.00,
    total_capacity INT DEFAULT 4,
    available_rooms INT DEFAULT 4,
    occupied_rooms INT DEFAULT 0,
    blocked_by VARCHAR(100) NULL,
    blocked_until DATETIME NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_hostel_name (hostel_name),
    INDEX idx_building_code (building_code),
    INDEX idx_room_code (room_code),
    INDEX idx_floor_code (floor_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;";

if ($conn->query($tableSql)) {
    echo "Successfully created or verified table 'hostel_rooms'.\n";
} else {
    echo "Error creating table: " . $conn->error . "\n";
}
