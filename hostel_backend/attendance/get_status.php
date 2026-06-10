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
    echo json_encode(["success" => false, "status" => "error", "message" => "Student ID required"]);
    exit();
}

try {
    $query = "SELECT status, log_time FROM attendance WHERE student_id = ? ORDER BY log_time DESC LIMIT 1";
    $stmt = $db->prepare($query);
    $stmt->execute([$student_id]);

    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if($row) {
        echo json_encode(["success" => true, "status" => "success", "current_status" => $row['status'], "last_time" => $row['log_time']]);
    } else {
        // Default to IN if no logs found
        echo json_encode(["success" => true, "status" => "success", "current_status" => "IN", "last_time" => null]);
    }
} catch (Exception $e) {
    echo json_encode(["success" => false, "status" => "error", "message" => $e->getMessage()]);
}
?>
