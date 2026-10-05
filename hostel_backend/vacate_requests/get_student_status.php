<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

if (!$conn) {
    echo json_encode(["status" => "error", "success" => false, "message" => "Database connection failed"]);
    exit();
}

$conn->query("
    CREATE TABLE IF NOT EXISTS vacate_requests (
        id INT AUTO_INCREMENT PRIMARY KEY,
        request_id VARCHAR(50) NOT NULL UNIQUE,
        student_id INT NOT NULL,
        student_reg_no VARCHAR(50) NOT NULL,
        student_name VARCHAR(255) NOT NULL,
        hostel_name VARCHAR(255) NULL,
        room_number VARCHAR(100) NOT NULL,
        renewal_date DATE NULL,
        expected_vacate_date DATE NOT NULL,
        reason TEXT NOT NULL,
        status ENUM('pending', 'approved', 'rejected', 'cancelled') DEFAULT 'pending',
        assigned_warden_username VARCHAR(100) NULL,
        assigned_warden_name VARCHAR(255) NULL,
        processed_by VARCHAR(100) NULL,
        processed_by_name VARCHAR(255) NULL,
        processed_at DATETIME NULL,
        remarks TEXT NULL,
        rejection_reason TEXT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_student_reg (student_reg_no),
        INDEX idx_student_id (student_id),
        INDEX idx_status (status),
        INDEX idx_room (room_number),
        INDEX idx_warden (assigned_warden_username)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
");

$student_id = $_GET['student_id'] ?? $_POST['student_id'] ?? null;
$reg_no = trim($_GET['reg_no'] ?? $_GET['student_reg_no'] ?? $_POST['reg_no'] ?? $_POST['student_reg_no'] ?? '');

if (empty($student_id) && empty($reg_no)) {
    $raw = file_get_contents("php://input");
    $body = json_decode($raw, true);
    if (is_array($body)) {
        $student_id = $body['student_id'] ?? null;
        $reg_no = trim($body['reg_no'] ?? $body['student_reg_no'] ?? '');
    }
}

if (empty($student_id) && empty($reg_no)) {
    echo json_encode(["status" => "error", "success" => false, "message" => "Student identifier is required."]);
    $conn->close();
    exit();
}

// Query latest vacate request
$stmt = null;
if (!empty($reg_no)) {
    $stmt = $conn->prepare("SELECT * FROM vacate_requests WHERE student_reg_no = ? ORDER BY id DESC LIMIT 1");
    $stmt->bind_param("s", $reg_no);
} else {
    $stmt = $conn->prepare("SELECT * FROM vacate_requests WHERE student_id = ? ORDER BY id DESC LIMIT 1");
    $stmt->bind_param("i", $student_id);
}

$stmt->execute();
$res = $stmt->get_result()->fetch_assoc();

if ($res) {
    echo json_encode([
        "status" => "success",
        "success" => true,
        "has_request" => true,
        "data" => [
            "id" => (int)$res['id'],
            "request_id" => $res['request_id'],
            "student_id" => (int)$res['student_id'],
            "student_reg_no" => $res['student_reg_no'],
            "student_name" => $res['student_name'],
            "hostel_name" => $res['hostel_name'],
            "room_number" => $res['room_number'],
            "renewal_date" => $res['renewal_date'],
            "expected_vacate_date" => $res['expected_vacate_date'],
            "reason" => $res['reason'],
            "status" => $res['status'],
            "rejection_reason" => $res['rejection_reason'],
            "assigned_warden_username" => $res['assigned_warden_username'],
            "assigned_warden_name" => $res['assigned_warden_name'],
            "processed_by_name" => $res['processed_by_name'],
            "processed_at" => $res['processed_at'],
            "remarks" => $res['remarks'],
            "created_at" => $res['created_at']
        ]
    ]);
} else {
    echo json_encode([
        "status" => "success",
        "success" => true,
        "has_request" => false,
        "data" => null
    ]);
}

$conn->close();
?>
