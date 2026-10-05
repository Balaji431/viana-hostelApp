<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

function ensureBiometricAuditTables($db) {
    // 1. Table for Students WITH confirmed biometric sync
    $sqlSynced = "
    CREATE TABLE IF NOT EXISTS biometric_synced_students (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NULL,
        register_no VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
        full_name VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
        email VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL,
        hostel_name VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL,
        room_allocation VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL,
        records_found INT NOT NULL DEFAULT 1,
        last_attendance_date DATETIME NULL,
        last_checked_at DATETIME NOT NULL,
        biometric_id VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL,
        notes TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_synced_reg_no (register_no),
        INDEX idx_synced_hostel (hostel_name),
        INDEX idx_synced_checked (last_checked_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
    ";

    // 2. Table for Students WITHOUT biometric sync
    $sqlNotSynced = "
    CREATE TABLE IF NOT EXISTS biometric_not_synced_students (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NULL,
        register_no VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
        full_name VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
        email VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL,
        hostel_name VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL,
        room_allocation VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL,
        last_checked_at DATETIME NOT NULL,
        biometric_id VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL,
        notes TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_notsynced_reg_no (register_no),
        INDEX idx_notsynced_hostel (hostel_name),
        INDEX idx_notsynced_checked (last_checked_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
    ";

    try {
        $db->exec($sqlSynced);
        $db->exec($sqlNotSynced);
    } catch (Exception $e) {}
}

// Backward compatibility alias
function ensureBiometricAuditTable($db) {
    ensureBiometricAuditTables($db);
}
