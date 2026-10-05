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
require_once '../utils/auth_helper.php';

$authUser = requireAuth();

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));
if (!empty($data) && strtolower($authUser['role'] ?? '') === 'student') {
    $data->student_id = $authUser['id'];
}

if(!empty($data->request_id) && !empty($data->student_id) && isset($data->is_working)){
    try {
        // 1. Get student info
        $student_query = "SELECT full_name, username FROM users WHERE id = :sid OR username = :sid LIMIT 1";
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
                $msg = "[COMPLETED] Student ($student_name) confirmed the issue is resolved. Task completed.";
            } else {
                $msg = "[NOT FIXED] Student ($student_name) reported that the issue is NOT fixed / still not working.";
            }
            
            // Fetch staff receiver_id & request details from existing request
            $req_stmt = $db->prepare("SELECT department, request_type FROM request1 WHERE request_id = :rid LIMIT 1");
            $req_stmt->bindParam(":rid", $data->request_id);
            $req_stmt->execute();
            $req_row = $req_stmt->fetch(PDO::FETCH_ASSOC);
            $req_dept = $req_row ? strtolower(trim($req_row['department'])) : 'maintenance';
            $req_type = $req_row ? $req_row['request_type'] : 'Maintenance';

            $rec_stmt = $db->prepare("SELECT receiver_id FROM chat_messages WHERE request_id = :rid AND receiver_id IS NOT NULL AND receiver_id != '' AND receiver_id != :sid ORDER BY id ASC LIMIT 1");
            $rec_stmt->bindParam(":rid", $data->request_id);
            $rec_stmt->bindParam(":sid", $student_username);
            $rec_stmt->execute();
            $rec_row = $rec_stmt->fetch(PDO::FETCH_ASSOC);
            $staff_receiver_id = $rec_row['receiver_id'] ?? null;

            $chat_query = "INSERT INTO chat_messages (request_id, sender_id, receiver_id, message, message_type, status) 
                           VALUES (:request_id, :sender_id, :receiver_id, :msg, 'status', 'sent')";
            $c_stmt = $db->prepare($chat_query);
            $c_stmt->bindParam(":request_id", $data->request_id);
            $c_stmt->bindParam(":sender_id", $student_username);
            $c_stmt->bindParam(":receiver_id", $staff_receiver_id);
            $c_stmt->bindParam(":msg", $msg);
            $c_stmt->execute();

            // 5. Send FCM Push Notifications
            try {
                require_once __DIR__ . '/../send_notification.php';
                
                // 5a. If working/completed, notify Student: "Your problem has been solved"
                if ($data->is_working) {
                    $stu_fcm_stmt = $db->prepare("SELECT fcm_token FROM users WHERE id = :sid OR username = :sid LIMIT 1");
                    $stu_fcm_stmt->execute([':sid' => $data->student_id]);
                    $stu_fcm = $stu_fcm_stmt->fetch(PDO::FETCH_ASSOC);
                    if ($stu_fcm && !empty($stu_fcm['fcm_token'])) {
                        $stu_title = "Problem Solved";
                        $stu_body = "Your $req_type problem has been solved and the request is now completed.";
                        sendFCM($stu_fcm['fcm_token'], $stu_title, $stu_body, $data->request_id, 'system', 'Viana Stay', $stu_body, 'request_update', $req_dept);
                    }
                }

                // 5b. Notify Staff (Maintenance & Warden)
                // Find active tokens for maintenance staff and assigned warden
                $staff_tokens_stmt = $db->prepare("
                    SELECT DISTINCT u.fcm_token, u.username, u.role
                    FROM users u
                    WHERE u.fcm_token IS NOT NULL AND u.fcm_token != ''
                      AND (
                          u.username = :staff_rec
                          OR u.id = :staff_rec
                          OR u.role = 'maintenance'
                          OR u.role = 'warden'
                      )
                ");
                $staff_tokens_stmt->execute([':staff_rec' => $staff_receiver_id ?? '']);
                $staff_rows = $staff_tokens_stmt->fetchAll(PDO::FETCH_ASSOC);

                $staff_title = $data->is_working ? "Request Completed" : "Issue Not Fixed";
                $staff_body = $data->is_working 
                    ? "Student $student_name confirmed that the $req_type issue has been solved."
                    : "Student $student_name reported that the $req_type issue is still not working.";

                foreach ($staff_rows as $st_row) {
                    if (!empty($st_row['fcm_token'])) {
                        sendFCM($st_row['fcm_token'], $staff_title, $staff_body, $data->request_id, $student_username, $student_name, $staff_body, 'request_update', $req_dept);
                    }
                }
            } catch (Exception $e) {}
            
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
