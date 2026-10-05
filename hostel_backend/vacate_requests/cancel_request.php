<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/auth_helper.php';

$authUser = requireAuth();

$database = new DatabaseMysqli();
$conn = $database->getConnection();

if (!$conn) {
    echo json_encode(["status" => "error", "success" => false, "message" => "Database connection failed"]);
    exit();
}

$raw = file_get_contents("php://input");
$data = json_decode($raw, true) ?? [];

$request_id = trim($data['request_id'] ?? ($_POST['request_id'] ?? ''));
$reg_no = trim($data['reg_no'] ?? $data['student_reg_no'] ?? ($_POST['reg_no'] ?? ''));

// If caller is student, bind cancellation to their own username
if (strtolower($authUser['role'] ?? '') === 'student') {
    $reg_no = $authUser['username'];
}

if (empty($request_id) && empty($reg_no)) {
    echo json_encode(["status" => "error", "success" => false, "message" => "Request ID or Student Reg No required."]);
    $conn->close();
    exit();
}

$stmt = null;
if (!empty($request_id)) {
    $stmt = $conn->prepare("UPDATE vacate_requests SET status = 'cancelled', updated_at = NOW() WHERE request_id = ? AND status = 'pending'");
    $stmt->bind_param("s", $request_id);
} else {
    $stmt = $conn->prepare("UPDATE vacate_requests SET status = 'cancelled', updated_at = NOW() WHERE student_reg_no = ? AND status = 'pending'");
    $stmt->bind_param("s", $reg_no);
}

$stmt->execute();

if ($stmt->affected_rows > 0) {
    echo json_encode(["status" => "success", "success" => true, "message" => "Vacate request cancelled successfully."]);
} else {
    echo json_encode(["status" => "error", "success" => false, "message" => "No pending vacate request found to cancel."]);
}

$conn->close();
?>
