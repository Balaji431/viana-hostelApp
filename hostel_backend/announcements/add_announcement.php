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
require_once '../utils/activity_logger.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

if(!empty($data->title) && !empty($data->content)) {
    $title = $conn->real_escape_string($data->title);
    $content = $conn->real_escape_string($data->content);
    $date = date('Y-m-d');
    
    $sql = "INSERT INTO announcements (title, content, date) VALUES ('$title', '$content', '$date')";
    
    if($conn->query($sql)) {
        logActivity(
            $data->user_id ?? null,
            $data->username ?? 'warden',
            $data->role ?? 'warden',
            'ADD_ANNOUNCEMENT',
            'announcements',
            null,
            json_encode(['title' => $title, 'content' => $content, 'date' => $date])
        );
        echo json_encode(array("status" => "success", "success" => true, "message" => "Announcement posted"));
    } else {
        echo json_encode(array("status" => "error", "success" => false, "message" => "Database error: " . $conn->error));
    }
} else {
    echo json_encode(array("status" => "error", "success" => false, "message" => "Incomplete data"));
}

$conn->close();
?>
