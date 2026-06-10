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
$limit = isset($_GET['limit']) ? (int)$_GET['limit'] : 50;
$offset = isset($_GET['offset']) ? (int)$_GET['offset'] : 0;

if (!$student_id || !$department) {
    echo json_encode([
        "success" => false,
        "status" => "error",
        "message" => "Missing student_id or department"
    ]);
    exit();
}

try {
    // 1. Resolve student_id (could be username/Reg No) to integer ID
    $user_stmt = $db->prepare("SELECT id FROM users WHERE (CONVERT(username USING utf8mb4) = CONVERT(? USING utf8mb4)) OR id = ? LIMIT 1");
    $user_stmt->execute([$student_id, $student_id]);
    $user_row = $user_stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user_row) {
        echo json_encode([
            "success" => false,
            "status" => "error",
            "message" => "Student not found ($student_id)"
        ]);
        exit;
    }
    $real_student_id = $user_row['id'];

    // 🔥 FIX: Message-centric query with Universal Translation (CONVERT)
    $query = "SELECT m.*, 
                     COALESCE(u.full_name, p.parent_id, m.sender_id) as sender_name, 
                     COALESCE(u.username, p.parent_id, m.sender_id) as sender_username,
                     r.request_type, r.status AS request_status, r.departure_date, 
                     r.return_date, r.purpose as reason, r.destination, r.room_number, 
                     r.department, stu.full_name as student_name
              FROM chat_messages m
              JOIN request1 r ON (CONVERT(m.request_id USING utf8mb4) = CONVERT(r.request_id USING utf8mb4))
              JOIN users stu ON r.student_id = stu.id
              LEFT JOIN users u ON (CONVERT(m.sender_id USING utf8mb4) = CONVERT(u.username USING utf8mb4))
              LEFT JOIN parent_users p ON (CONVERT(m.sender_id USING utf8mb4) = CONVERT(p.parent_id USING utf8mb4) AND u.username IS NULL)
              WHERE r.student_id = :student_id AND CONVERT(r.department USING utf8mb4) = CONVERT(:department USING utf8mb4)
              ORDER BY m.id DESC
              LIMIT :limit OFFSET :offset";

    $stmt = $db->prepare($query);
    $stmt->bindValue(':student_id', (int)$real_student_id, PDO::PARAM_INT);
    $stmt->bindValue(':department', $department, PDO::PARAM_STR);
    $stmt->bindValue(':limit', (int)$limit, PDO::PARAM_INT);
    $stmt->bindValue(':offset', (int)$offset, PDO::PARAM_INT);
    $stmt->execute();

    $messages = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $formatted_data = [];
    foreach ($messages as $msg) {
        $msg['status'] = $msg['status'] ?? 'sent';
        $msg['req_id'] = $msg['request_id'];
        $formatted_data[] = $msg;
    }

    echo json_encode([
        "success" => true,
        "status" => "success",
        "data" => $formatted_data
    ]);
} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "status" => "error",
        "message" => "Database error: " . $e->getMessage(),
        "trace" => $e->getTraceAsString()
    ]);
}
?>