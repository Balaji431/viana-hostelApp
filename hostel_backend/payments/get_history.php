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

    if (!$student_id) {
        echo json_encode(["status" => "error", "message" => "student_id is required"]);
        exit();
    }

    $query = "SELECT p.* FROM payment p 
              JOIN users u ON (TRIM(u.username) COLLATE utf8mb4_unicode_ci = TRIM(p.registerNumber) COLLATE utf8mb4_unicode_ci)
              WHERE u.id = ? 
              ORDER BY p.booking_date DESC";
              
    $stmt = $db->prepare($query);
    $stmt->execute([$student_id]);

    $results = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode(["status" => "success", "data" => $results]);

} catch (Exception $e) {
    echo json_encode(["status" => "error", "message" => $e->getMessage()]);
}
?>
