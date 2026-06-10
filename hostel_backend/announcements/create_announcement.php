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



$data = json_decode(file_get_contents("php://input"));

if (!empty($data->title) && !empty($data->message) && !empty($data->created_by)) {
    
    $title = trim($data->title);
    $message = trim($data->message);
    $created_by = trim($data->created_by);
    $priority = isset($data->priority) ? trim($data->priority) : 'normal';
    $target_audience = isset($data->target_audience) ? trim($data->target_audience) : 'all';
    $expires_at = isset($data->expires_at) ? trim($data->expires_at) : null;
    
    try {
        $query = "INSERT INTO announcements (title, message, priority, target_audience, created_by, expires_at, created_at) 
                  VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)";
        
        $stmt = $conn->prepare($query);
        $stmt->bind_param("ssssss", $title, $message, $priority, $target_audience, $created_by, $expires_at);
        
        if ($stmt->execute()) {
            $announcement_id = $conn->insert_id;
            logActivity(
                $data->user_id ?? null,
                $created_by,
                $data->role ?? 'warden',
                'CREATE_ANNOUNCEMENT',
                'announcements',
                null,
                json_encode([
                    'id' => $announcement_id,
                    'title' => $title,
                    'message' => $message,
                    'priority' => $priority,
                    'target_audience' => $target_audience,
                    'created_by' => $created_by,
                    'expires_at' => $expires_at
                ])
            );
            echo json_encode([
                'success' => true,
                'message' => 'Announcement created successfully',
                'data' => [
                    'id' => $announcement_id,
                    'title' => $title,
                    'message' => $message,
                    'priority' => $priority,
                    'target_audience' => $target_audience,
                    'created_by' => $created_by,
                    'expires_at' => $expires_at,
                    'created_at' => date('Y-m-d H:i:s')
                ]
            ]);
        } else {
            echo json_encode([
                'success' => false,
                'message' => 'Failed to create announcement'
            ]);
        }
        
    } catch (Exception $e) {
        echo json_encode([
            'success' => false,
            'message' => 'Database error: ' . $e->getMessage()
        ]);
    }
} else {
    echo json_encode([
        'success' => false,
        'message' => 'Incomplete data. Required: title, message, created_by'
    ]);
}

$conn->close();
?>
