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

$data = json_decode(file_get_contents("php://input"));

$request_id = $data->request_id;
$user_input = $data->user_id; // Can be ID or username

try {
    // Resolve username - Check BOTH users table and parent_users table
    $user_query = $db->prepare("SELECT username FROM users WHERE id = ? OR username = ? LIMIT 1");
    $user_query->execute([$user_input, $user_input]);
    $user_row = $user_query->fetch(PDO::FETCH_ASSOC);
    
    if ($user_row) {
        $username = $user_row['username'];
    } else {
        // Check parent_users table
        $parent_query = $db->prepare("SELECT parent_id as username FROM parent_users WHERE id = ? OR parent_id = ? LIMIT 1");
        $parent_query->execute([$user_input, $user_input]);
        $parent_row = $parent_query->fetch(PDO::FETCH_ASSOC);
        $username = $parent_row ? $parent_row['username'] : $user_input;
    }

    // Use receiver_id = username
    $query = "UPDATE chat_messages 
              SET status = 'delivered' 
              WHERE request_id = ? 
              AND receiver_id = ? 
              AND status = 'sent'";

    $stmt = $db->prepare($query);

    if($stmt->execute([$request_id, $username])) {
        echo json_encode(["success" => true]);
    } else {
        echo json_encode(["success" => false]);
    }
} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Database error: " . $e->getMessage()
    ]);
}
?>