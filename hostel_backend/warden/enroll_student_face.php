<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/auth_helper.php';

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $raw_input = file_get_contents('php://input');
    $data = json_decode($raw_input, true) ?? [];

    $reg_no = trim($data['reg_no'] ?? $data['student_id'] ?? $_POST['reg_no'] ?? '');
    $warden_username = trim($data['warden_username'] ?? $_POST['warden_username'] ?? '');
    $face_image = $data['face_image'] ?? $data['image_data_url'] ?? '';
    $student_name = trim($data['student_name'] ?? '');

    if (empty($reg_no)) {
        echo json_encode([
            "success" => false,
            "status" => "error",
            "message" => "Register number is required."
        ]);
        exit();
    }

    // Check if biometric_enrollments table exists or create it
    $db->exec("
        CREATE TABLE IF NOT EXISTS biometric_enrollments (
            id INT AUTO_INCREMENT PRIMARY KEY,
            reg_no VARCHAR(100) NOT NULL UNIQUE,
            full_name VARCHAR(255) NULL,
            enrolled_by VARCHAR(100) NULL,
            enrolled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            is_active TINYINT(1) DEFAULT 1,
            reference_id VARCHAR(100) NULL,
            face_template_hash VARCHAR(255) NULL,
            INDEX idx_reg_no (reg_no)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");

    $ref_id = 'BIO-ENR-' . strtoupper(substr(uniqid(), -8));

    $stmt = $db->prepare("
        INSERT INTO biometric_enrollments (reg_no, full_name, enrolled_by, reference_id, is_active)
        VALUES (:reg_no, :full_name, :enrolled_by, :ref_id, 1)
        ON DUPLICATE KEY UPDATE
            full_name = VALUES(full_name),
            enrolled_by = VALUES(enrolled_by),
            reference_id = VALUES(reference_id),
            is_active = 1,
            updated_at = NOW()
    ");

    $stmt->execute([
        ':reg_no' => $reg_no,
        ':full_name' => $student_name,
        ':enrolled_by' => $warden_username,
        ':ref_id' => $ref_id
    ]);

    echo json_encode([
        "success" => true,
        "status" => "success",
        "message" => "Face biometric enrolled successfully for student $reg_no.",
        "reference_id" => $ref_id,
        "enrolled_at" => date('Y-m-d H:i:s')
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "success" => false,
        "status" => "error",
        "message" => "Enrollment failed: " . $e->getMessage()
    ]);
}
