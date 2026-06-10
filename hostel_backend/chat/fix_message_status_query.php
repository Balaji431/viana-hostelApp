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
    // We use DESC here to get the LATEST 50 messages for the first page.
    $query = "SELECT m.*, m.status AS message_status, u.full_name as sender_name, u.username as sender_username, 
                     r.request_id as req_id, r.request_type, r.status AS request_status, r.departure_date, 
                     r.return_date, r.purpose as reason, r.destination, r.room_number, 
                     r.department, stu.full_name as student_name, r.created_at as req_created_at
              FROM request1 r
              JOIN users stu ON r.student_id = stu.id
              LEFT JOIN chat_messages m ON r.request_id = m.request_id
              LEFT JOIN users u ON (m.sender_id = u.username OR m.sender_id = u.id)
              WHERE r.student_id = ? AND r.department = ?
              ORDER BY COALESCE(m.timestamp, r.created_at) DESC
              LIMIT ? OFFSET ?";

    $stmt = $db->prepare($query);
    $stmt->bindValue(1, $student_id);
    $stmt->bindValue(2, $department);
    $stmt->bindValue(3, $limit, PDO::PARAM_INT);
    $stmt->bindValue(4, $offset, PDO::PARAM_INT);
    $stmt->execute();

    $messages = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $formatted_data = [];
    foreach ($messages as $msg) {
        if ($msg['message'] === null) {
            $msg['message_type'] = 'request';
            $msg['message'] = "New Request: " . $msg['request_type'];
            $msg['timestamp'] = $msg['timestamp'] ?? $msg['req_created_at'];
            $msg['status'] = 'sent'; // Default status for request messages
        } else {
            // Use message_status from chat_messages table
            $msg['status'] = $msg['message_status'] ?? 'sent';
        }
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
        "message" => "Database error: " . $e->getMessage()
    ]);
}
?>