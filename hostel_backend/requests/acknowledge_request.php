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

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

if(!empty($data->request_id) && !empty($data->student_id) && isset($data->is_working)){
    try {
        // 1. Get student info
        $student_query = "SELECT full_name, username FROM users WHERE id = :sid AND role = 'student'";
        $s_stmt = $db->prepare($student_query);
        $s_stmt->bindParam(":sid", $data->student_id);
        $s_stmt->execute();
        $student = $s_stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$student) {
            echo json_encode(["success" => false, "message" => "Student not found"]);
            exit();
        }
        $student_name = $student['full_name'];
        $student_username = $student['username'];

        // 2. Determine new status
        $new_status = $data->is_working ? 'completed' : 'reopened'; // Re-open if not working
        $display_status = strtoupper($new_status);

        // 3. Update Status
        $query = "UPDATE request1 SET status = :status WHERE request_id = :request_id";
        $stmt = $db->prepare($query);
        $stmt->bindParam(":status", $new_status);
        $stmt->bindParam(":request_id", $data->request_id);

        if($stmt->execute()){
            // Log Audit state transition
            $action = ($new_status === 'completed') ? 'REQUEST_CLOSE' : 'REQUEST_REOPEN';
            logAudit(
                $data->student_id,
                $student_username,
                'student',
                $action,
                'Requests',
                null,
                [
                    'request_id' => $data->request_id,
                    'is_working' => $data->is_working,
                    'new_status' => $new_status
                ]
            );

            // 4. Add Acknowledgment message to chat history
            if ($data->is_working) {
                $msg = "[SUCCESS] Student ($student_name) has acknowledged that the issue is resolved. Request closed.";
            } else {
                $msg = "[REOPENED] Student ($student_name) reported that the issue persists. Request reopened.";
            }
            
            $chat_query = "INSERT INTO chat_messages (request_id, sender_id, message, message_type) 
                           VALUES (:request_id, :sender_id, :msg, 'status')";
            $c_stmt = $db->prepare($chat_query);
            $c_stmt->bindParam(":request_id", $data->request_id);
            $c_stmt->bindParam(":sender_id", $student_username);
            $c_stmt->bindParam(":msg", $msg);
            $c_stmt->execute();
            
            echo json_encode([
                "success" => true,
                "message" => "Acknowledgment recorded successfully",
                "status" => $new_status
            ]);
        } else {
            echo json_encode(["success" => false, "message" => "Failed to update record"]);
        }
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Database error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Incomplete data. Required: request_id, student_id, is_working"]);
}
?>
