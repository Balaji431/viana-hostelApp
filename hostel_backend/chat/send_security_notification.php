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



ob_clean();
ini_set('display_errors', 0);
error_reporting(E_ALL);
include_once '../config/database.php';
require_once '../send_notification.php';

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

if(!empty($data->request_id) && !empty($data->sender_id) && !empty($data->message)) {
    
    // Find receiver (student who made the request)
    $receiver_query = "SELECT u.username FROM request1 r JOIN users u ON r.student_id = u.id WHERE r.request_id = ?";
    $receiver_stmt = $db->prepare($receiver_query);
    $receiver_stmt->execute([$data->request_id]);
    $receiver_row = $receiver_stmt->fetch(PDO::FETCH_ASSOC);
    $receiver_username = $receiver_row ? $receiver_row['username'] : null;

    // Insert security message with receiver_id
    $query = "INSERT INTO chat_messages (request_id, sender_id, receiver_id, message, message_type) VALUES (?, ?, ?, ?, 'security')";
    $stmt = $db->prepare($query);
    
    if($stmt->execute([$data->request_id, $data->sender_id, $receiver_username, $data->message])) {
        
        // Get sender information
        $sender_query = "SELECT username, full_name FROM users WHERE id = ?";
        $sender_stmt = $db->prepare($sender_query);
        $sender_stmt->execute([$data->sender_id]);
        $sender = $sender_stmt->fetch(PDO::FETCH_ASSOC);
        
        // Find receiver (student who made the request)
        $receiver_query = "SELECT r.student_id, u.id, u.username, u.full_name, u.fcm_token 
                        FROM request1 r 
                        JOIN users u ON r.student_id = u.id 
                        WHERE r.request_id = ?";
        $receiver_stmt = $db->prepare($receiver_query);
        $receiver_stmt->execute([$data->request_id]);
        $receiver = $receiver_stmt->fetch(PDO::FETCH_ASSOC);
        
        // Determine sender name
        $sender_name_for_notification = $sender['full_name']; // Use full name for staff
        
        // Send FCM notification if receiver has token
        if($receiver && !empty($receiver['fcm_token'])) {
            $title = "Security Alert - " . $sender_name_for_notification;
            $body = $data->message;
            
            file_put_contents('../fcm_debug.txt', date('Y-m-d H:i:s') . " - Sending security notification\n", FILE_APPEND);
            file_put_contents('../fcm_debug.txt', date('Y-m-d H:i:s') . " - From: " . $sender_name_for_notification . " (ID: " . $data->sender_id . ")\n", FILE_APPEND);
            file_put_contents('../fcm_debug.txt', date('Y-m-d H:i:s') . " - To: " . $receiver['full_name'] . " (Token: " . substr($receiver['fcm_token'], 0, 20) . "...)\n", FILE_APPEND);
            file_put_contents('../fcm_debug.txt', date('Y-m-d H:i:s') . " - Message: " . $data->message . "\n", FILE_APPEND);
            
            $fcm_response = sendFCM($receiver['fcm_token'], $title, $body, $data->request_id, $data->sender_id, $sender_name_for_notification, $data->message, 'security');
            
            file_put_contents('../fcm_response.txt', date('Y-m-d H:i:s') . " - Response: " . $fcm_response . "\n", FILE_APPEND);
        } else {
            file_put_contents('../fcm_debug.txt', date('Y-m-d H:i:s') . " - No receiver token for security notification\n", FILE_APPEND);
        }
        
        echo json_encode(["success" => true, "message" => "Security notification sent"]);
        exit;
    } else {
        echo json_encode(["success" => false, "message" => "Failed to send security notification"]);
        exit;
    }
} else {
    echo json_encode(["success" => false, "message" => "Incomplete data"]);
    exit;
}
?>
