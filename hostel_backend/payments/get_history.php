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

try {
    $database = new Database();
    $db = $database->getConnection();

    $student_id = $_GET['student_id'] ?? null;
    $reg_no = $_GET['reg_no'] ?? null;

    if (!$student_id && !$reg_no) {
        echo json_encode(["status" => "error", "message" => "student_id or reg_no is required"]);
        exit();
    }

    $query = "SELECT DISTINCT p.* FROM payment p 
              LEFT JOIN users u ON (p.user_id = u.id OR TRIM(u.username) COLLATE utf8mb4_unicode_ci = TRIM(p.registerNumber) COLLATE utf8mb4_unicode_ci)
              WHERE u.id = ? OR p.user_id = ? OR p.registerNumber = ?
              ORDER BY COALESCE(p.paid_at, p.created_at, p.booking_date) ASC";
              
    $stmt = $db->prepare($query);
    $stmt->execute([$student_id, $student_id, $reg_no ?: $student_id]);

    $results = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode(["status" => "success", "data" => $results]);

} catch (Exception $e) {
    echo json_encode(["status" => "error", "message" => $e->getMessage()]);
}
?>
