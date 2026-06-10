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
$department = isset($_GET['department']) ? $_GET['department'] : null;

if (!$student_id || !$department) {
    echo json_encode(["success" => false, "message" => "Missing student_id or department"]);
    exit;
}

try {
    // 1. Resolve student_id (could be username/Reg No) to integer ID with Universal Translation
    $user_stmt = $db->prepare("SELECT id FROM users WHERE (CONVERT(username USING utf8mb4) = CONVERT(? USING utf8mb4)) OR id = ? LIMIT 1");
    $user_stmt->execute([$student_id, $student_id]);
    $user_row = $user_stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user_row) {
        echo json_encode(["success" => false, "message" => "Student not found"]);
        exit;
    }
    $real_student_id = $user_row['id'];

    // 2. Get latest request with Universal Translation
    $query = "SELECT request_id 
              FROM request1 
              WHERE student_id = ? AND (CONVERT(department USING utf8mb4) = CONVERT(? USING utf8mb4)) 
              ORDER BY updated_at DESC LIMIT 1";

    $stmt = $db->prepare($query);
    $stmt->execute([$real_student_id, $department]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if($row){
        echo json_encode([
            "success" => true,
            "request_id" => $row['request_id']
        ]);
    } else {
        echo json_encode([
            "success" => false,
            "message" => "No previous requests found"
        ]);
    }
} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Database error: " . $e->getMessage()
    ]);
}
?>
