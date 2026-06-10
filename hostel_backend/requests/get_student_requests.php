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

$database = new Database();
$db = $database->getConnection();

$student_id = isset($_GET['student_id']) ? $_GET['student_id'] : null;

if (!$student_id) {
    echo json_encode([
        "success" => false,
        "status" => "error",
        "message" => "Student ID is required"
    ]);
    exit();
}

try {
    $query = "SELECT r.*, stu.full_name as student_name, p.room_allocation
              FROM request1 r
              LEFT JOIN users stu ON r.student_id = stu.id
              LEFT JOIN profile p ON stu.username = p.reg_no
              WHERE r.student_id = ?
              ORDER BY r.updated_at DESC";

    $stmt = $db->prepare($query);
    $stmt->execute([$student_id]);

    $requests = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "success" => true,
        "status" => "success",
        "data" => $requests
    ]);
} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "status" => "error",
        "message" => "Database error: " . $e->getMessage()
    ]);
}
?>
