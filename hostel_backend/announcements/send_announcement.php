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

if(!empty($data->title) && !empty($data->message) && !empty($data->sender_id)) {
    
    // Insert announcement
    $query = "INSERT INTO announcements (title, content, created_at) VALUES (?, ?, NOW())";
    $stmt = $db->prepare($query);
    
    if($stmt->execute([$data->title, $data->message])) {
        
        // Get sender information
        $sender_query = "SELECT username, full_name FROM users WHERE id = ?";
        $sender_stmt = $db->prepare($sender_query);
        $sender_stmt->execute([$data->sender_id]);
        $sender = $sender_stmt->fetch(PDO::FETCH_ASSOC);
        
        // Get all students with FCM tokens
        $students_query = "SELECT id, username, full_name, fcm_token FROM users WHERE role = 'student' AND fcm_token IS NOT NULL AND fcm_token != ''";
        $students_stmt = $db->prepare($students_query);
        $students_stmt->execute();
        $students = $students_stmt->fetchAll(PDO::FETCH_ASSOC);
        
        $sender_name_for_notification = $sender['full_name']; // Use full name for staff
        $title = "📢 New Announcement: " . $data->title;
        $body = $data->message;
        
        file_put_contents('../../fcm_debug.txt', date('Y-m-d H:i:s') . " - Sending announcement to " . count($students) . " students\n", FILE_APPEND);
        
        // Send FCM to all students
        $success_count = 0;
        foreach ($students as $student) {
            if (!empty($student['fcm_token'])) {
                $fcm_response = sendFCM($student['fcm_token'], $title, $body, 'announcement', $data->sender_id, $sender_name_for_notification, $data->message, 'announcement');
                
                // Log each student notification
                file_put_contents('../fcm_debug.txt', date('Y-m-d H:i:s') . " - To: " . $student['full_name'] . " (Token: " . substr($student['fcm_token'], 0, 20) . "...)\n", FILE_APPEND);
                
                // Check if FCM was successful (response contains "name" field)
                if (strpos($fcm_response, '"name"') !== false) {
                    $success_count++;
                }
                
                file_put_contents('../../fcm_response.txt', date('Y-m-d H:i:s') . " - Response: " . $fcm_response . "\n", FILE_APPEND);
            }
        }
        
        file_put_contents('../fcm_debug.txt', date('Y-m-d H:i:s') . " - Announcement sent successfully to $success_count students\n", FILE_APPEND);
        
        echo json_encode([
            "success" => true, 
            "message" => "Announcement sent to $success_count students",
            "students_notified" => $success_count
        ]);
        exit;
    } else {
        echo json_encode(["success" => false, "message" => "Failed to create announcement"]);
        exit;
    }
} else {
    echo json_encode(["success" => false, "message" => "Incomplete data"]);
    exit;
}
?>
