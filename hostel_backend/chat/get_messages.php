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
require_once '../utils/auth_helper.php';

$authUser = requireAuth();

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));
$request_id = isset($data->request_id) ? $data->request_id : 
              (isset($_GET['request_id']) ? $_GET['request_id'] : null);

if (!$request_id) {
    echo json_encode(["success"=>false,"message"=>"Request ID required"]);
    exit;
}

// Universal Translation (CONVERT) to handle mixed character sets
$query = "SELECT m.*, 
                 COALESCE(u.full_name, p.parent_id, m.sender_id) as sender_name, 
                 COALESCE(u.username, p.parent_id, m.sender_id) as sender_username
          FROM chat_messages m
          LEFT JOIN users u ON (CONVERT(m.sender_id USING utf8mb4) = CONVERT(u.username USING utf8mb4))
          LEFT JOIN parent_users p ON (CONVERT(m.sender_id USING utf8mb4) = CONVERT(p.parent_id USING utf8mb4) AND u.username IS NULL)
          WHERE CONVERT(m.request_id USING utf8mb4) = CONVERT(? USING utf8mb4) 
          ORDER BY m.timestamp ASC";

try {
    $stmt = $db->prepare($query);
    $stmt->execute([$request_id]);
    $messages = $stmt->fetchAll(PDO::FETCH_ASSOC);

    foreach($messages as &$msg) {
        $msg['created_at'] = $msg['timestamp'];
        $msg['message_status'] = $msg['status'] ?? 'sent'; 
    }

    echo json_encode([
        "success" => true,
        "data" => $messages,
        "status" => "success"
    ]);
} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Database error: " . $e->getMessage()
    ]);
}
?>