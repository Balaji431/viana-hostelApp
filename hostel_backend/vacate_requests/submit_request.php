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
require_once __DIR__ . '/../utils/warden_resolver.php';
require_once __DIR__ . '/../utils/auth_helper.php';

$authUser = requireAuth();

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

$raw = file_get_contents("php://input");
$data = json_decode($raw, true) ?? [];

$student_id = $data['student_id'] ?? ($_POST['student_id'] ?? null);
$reg_no = trim($data['reg_no'] ?? $data['student_reg_no'] ?? ($_POST['reg_no'] ?? ''));

// If caller is student, bind strictly to authenticated account
if (strtolower($authUser['role'] ?? '') === 'student') {
    $student_id = $authUser['id'];
    $reg_no = $authUser['username'];
}

$expected_vacate_date = trim($data['expected_vacate_date'] ?? $data['vacate_date'] ?? ($_POST['expected_vacate_date'] ?? ''));
$reason = trim($data['reason'] ?? ($_POST['reason'] ?? ''));

if (empty($expected_vacate_date)) {
    echo json_encode(["status" => "error", "success" => false, "message" => "Expected vacate date is required."]);
    $conn->close();
    exit();
}

if (empty($reason)) {
    echo json_encode(["status" => "error", "success" => false, "message" => "Please provide a reason for vacating."]);
    $conn->close();
    exit();
}

// 1. Fetch student user and profile details
$user_row = null;
if (!empty($student_id)) {
    $u_stmt = $conn->prepare("SELECT * FROM users WHERE id = ? LIMIT 1");
    $u_stmt->bind_param("i", $student_id);
    $u_stmt->execute();
    $user_row = $u_stmt->get_result()->fetch_assoc();
}
if (!$user_row && !empty($reg_no)) {
    $u_stmt = $conn->prepare("SELECT * FROM users WHERE username = ? LIMIT 1");
    $u_stmt->bind_param("s", $reg_no);
    $u_stmt->execute();
    $user_row = $u_stmt->get_result()->fetch_assoc();
}

if (!$user_row) {
    echo json_encode(["status" => "error", "success" => false, "message" => "Student record not found."]);
    $conn->close();
    exit();
}

$student_id = (int)$user_row['id'];
$reg_no = $user_row['username'];

$p_stmt = $conn->prepare("SELECT * FROM profile WHERE reg_no = ? LIMIT 1");
$p_stmt->bind_param("s", $reg_no);
$p_stmt->execute();
$prof_row = $p_stmt->get_result()->fetch_assoc();

$student_name = $prof_row['full_name'] ?? $user_row['name'] ?? $user_row['full_name'] ?? $reg_no;
$current_room = trim($prof_row['room_allocation'] ?? $user_row['RoomId'] ?? '');
$hostel_name = trim($prof_row['hostel_name'] ?? $user_row['HostelName'] ?? '');
$renewal_date = $prof_row['renewal_date'] ?? $prof_row['valid_to'] ?? null;

if (empty($current_room) || $current_room === 'unallocated' || $current_room === 'vacated') {
    echo json_encode(["status" => "error", "success" => false, "message" => "You do not have an active allocated room to vacate."]);
    $conn->close();
    exit();
}

// 2. Check for active pending vacate request
$chk_stmt = $conn->prepare("SELECT id, request_id, assigned_warden_name, expected_vacate_date FROM vacate_requests WHERE student_reg_no = ? AND status = 'pending' LIMIT 1");
$chk_stmt->bind_param("s", $reg_no);
$chk_stmt->execute();
$existing = $chk_stmt->get_result()->fetch_assoc();

if ($existing) {
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => "You already have a pending vacate request under review by " . ($existing['assigned_warden_name'] ?? 'your Hostel Warden') . ".",
        "data" => $existing
    ]);
    $conn->close();
    exit();
}

// 3. Resolve assigned warden
$warden_info = getWardenDetailsForRequestedRoom($conn, $current_room, $hostel_name);
$assigned_warden_username = $warden_info['username'] ?? 'warden1';
$assigned_warden_name = $warden_info['name'] ?? 'Hostel Warden';

// 4. Generate unique request_id
$request_id = 'VAC-' . strtoupper(substr(md5(uniqid(mt_rand(), true)), 0, 6));

// 5. Insert vacate request
$ins_stmt = $conn->prepare("
    INSERT INTO vacate_requests (
        request_id, student_id, student_reg_no, student_name, hostel_name, room_number,
        renewal_date, expected_vacate_date, reason, status,
        assigned_warden_username, assigned_warden_name
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)
");

$ins_stmt->bind_param(
    "sisssssssss",
    $request_id,
    $student_id,
    $reg_no,
    $student_name,
    $hostel_name,
    $current_room,
    $renewal_date,
    $expected_vacate_date,
    $reason,
    $assigned_warden_username,
    $assigned_warden_name
);

if ($ins_stmt->execute()) {
    echo json_encode([
        "status" => "success",
        "success" => true,
        "message" => "Your vacate request has been submitted successfully to $assigned_warden_name for review and clearance.",
        "data" => [
            "request_id" => $request_id,
            "student_reg_no" => $reg_no,
            "student_name" => $student_name,
            "room_number" => $current_room,
            "expected_vacate_date" => $expected_vacate_date,
            "renewal_date" => $renewal_date,
            "assigned_warden_name" => $assigned_warden_name,
            "assigned_warden_username" => $assigned_warden_username,
            "status" => "pending"
        ]
    ]);
} else {
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => "Failed to submit vacate request: " . $conn->error
    ]);
}

$conn->close();
?>
