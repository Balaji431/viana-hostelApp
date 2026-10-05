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

$authUser = requireAuth(['warden', 'admin', 'super_admin', 'maintenance', 'security', 'it']);

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));
if (!empty($data) && empty($data->warden_id)) {
    $data->warden_id = $authUser['id'] ?? $authUser['username'];
}

if(!empty($data->request_id) && !empty($data->status) && !empty($data->warden_id)){
    try {
        // 1. Get staff info (Check mapping_staff for specific role like plumber/electricity, fallback to users role)
        $staff_query = "SELECT u.full_name, u.username, 
                        COALESCE(ms.role, u.role) as effective_role,
                        u.role as base_role
                        FROM users u
                        LEFT JOIN mapping_staff ms ON (TRIM(u.username) = TRIM(ms.username) OR TRIM(u.username) = TRIM(ms.staff_bio_id))
                        WHERE u.id = :wid OR TRIM(u.username) = TRIM(:wid) LIMIT 1";
        $w_stmt = $db->prepare($staff_query);
        $w_stmt->bindParam(":wid", $data->warden_id);
        $w_stmt->execute();
        $staff = $w_stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$staff) {
            echo json_encode(["success" => false, "message" => "Staff member not found"]);
            exit();
        }
        $staff_name = $staff['full_name'];
        $staff_role = strtolower(trim($staff['effective_role']));
        $staff_username = $staff['username'];
        $base_role = strtolower(trim($staff['base_role']));

        // 2. Identify target table and get request department
        $table = "request1";
        $is_rcr = false;
        if (strpos($data->request_id, 'RCR-') === 0) {
            $table = "room_change_requests";
            $is_rcr = true;
        }

        // Fetch request details to check department
        $req_query = "SELECT department, request_type FROM $table WHERE request_id = :rid LIMIT 1";
        $req_stmt = $db->prepare($req_query);
        $req_stmt->bindParam(":rid", $data->request_id);
        $req_stmt->execute();
        $request = $req_stmt->fetch(PDO::FETCH_ASSOC);

        if (!$request) {
            echo json_encode(["success" => false, "message" => "Request not found"]);
            exit();
        }

        $req_dept = strtolower(trim($request['department'] ?? ''));

        // 3. Authorization Check
        $is_authorized = false;
        if ($base_role === 'admin' || $staff_role === 'admin') {
            $is_authorized = true;
        } else {
            // Role matching logic
            if ($staff_role === $req_dept) {
                $is_authorized = true;
            } elseif (strpos($staff_role, 'warden') !== false && (strpos($req_dept, 'warden') !== false || $req_dept === 'parent_warden')) {
                $is_authorized = true;
            } elseif (strpos($staff_role, 'maint') !== false && strpos($req_dept, 'maint') !== false) {
                $is_authorized = true;
            } elseif (strpos($staff_role, 'sec') !== false && strpos($req_dept, 'sec') !== false) {
                $is_authorized = true;
            } elseif ($is_rcr && (strpos($staff_role, 'warden') !== false || strpos($base_role, 'warden') !== false)) {
                // Warden handles room change requests
                $is_authorized = true;
            }
        }

        if (!$is_authorized) {
            echo json_encode([
                "success" => false, 
                "message" => "Access Denied: You are logged in as " . ucfirst($staff_role) . " and cannot approve " . ucfirst($req_dept) . " requests."
            ]);
            exit();
        }

        // 3. Update Status
        $query = "UPDATE $table SET status = :status WHERE request_id = :request_id";
        $stmt = $db->prepare($query);
        $stmt->bindParam(":status", $data->status);
        $stmt->bindParam(":request_id", $data->request_id);

        if($stmt->execute()){
            logAudit(
                $data->warden_id,
                $staff_username,
                $staff_role,
                "UPDATE_REQUEST_STATUS_" . strtoupper($data->status),
                $is_rcr ? "Room Change" : "Complaints",
                null,
                [
                    "request_id" => $data->request_id,
                    "status" => $data->status,
                    "reason" => $data->reason ?? null
                ]
            );

            // 4. Add Status notification message to chat history
            $display_status = strtoupper($data->status);
            
            // Custom message based on status
            if ($data->status == 'fixed') {
                $msg = "[MAINTENANCE] Issue has been marked as fixed by $staff_role ($staff_name). Student, please verify and acknowledge if the issue is resolved.";
            } elseif ($data->status == 'rejected' && !empty($data->reason)) {
                $msg = "Request has been REJECTED by $staff_role ($staff_name). Reason: " . $data->reason;
            } elseif ($data->status == 'completed') {
                $msg = "Request has been COMPLETED by $staff_role ($staff_name).";
            } else {
                $msg = "Request has been $display_status by $staff_role ($staff_name)";
            }
            
            // Fetch student username for receiver_id
            $stu_req = $db->prepare("SELECT u.username FROM request1 r JOIN users u ON (CONVERT(r.student_id USING utf8mb4) = CONVERT(u.username USING utf8mb4) OR CONVERT(r.student_id USING utf8mb4) = CONVERT(u.id USING utf8mb4)) WHERE r.request_id = :rid LIMIT 1");
            $stu_req->bindParam(":rid", $data->request_id);
            $stu_req->execute();
            $stu_user = $stu_req->fetch(PDO::FETCH_ASSOC);
            $target_receiver_id = $stu_user['username'] ?? $req['student_id'] ?? null;

            $chat_query = "INSERT INTO chat_messages (request_id, sender_id, receiver_id, message, message_type, status) 
                           VALUES (:request_id, :sender_id, :receiver_id, :msg, 'status', 'sent')";
            $c_stmt = $db->prepare($chat_query);
            $c_stmt->bindParam(":request_id", $data->request_id);
            $c_stmt->bindParam(":sender_id", $staff_username);
            $c_stmt->bindParam(":receiver_id", $target_receiver_id);
            $c_stmt->bindParam(":msg", $msg);
            $c_stmt->execute();
            
            // 5. Send FCM Push Notification to Student
            try {
                require_once __DIR__ . '/../send_notification.php';
                $stu_query = "SELECT u.fcm_token, u.username, u.full_name FROM $table r JOIN users u ON (CONVERT(r.student_id USING utf8mb4) = CONVERT(u.username USING utf8mb4) OR CONVERT(r.student_id USING utf8mb4) = CONVERT(u.id USING utf8mb4)) WHERE r.request_id = :rid LIMIT 1";
                $s_stmt = $db->prepare($stu_query);
                $s_stmt->bindParam(":rid", $data->request_id);
                $s_stmt->execute();
                $stu = $s_stmt->fetch(PDO::FETCH_ASSOC);

                if ($stu && !empty($stu['fcm_token'])) {
                    // Title format: Staff Name (Role) -> e.g. A naveen arul (Maintenance)
                    $title = $staff_name . " (" . ucfirst($staff_role) . ")";
                    $st = strtolower($data->status);
                    $req_type_clean = !empty($request['request_type']) ? $request['request_type'] : ucfirst($req_dept);

                    if ($st === 'rejected') {
                        $reason_text = !empty($data->reason) ? $data->reason : 'No reason specified';
                        $body = "Your " . $req_type_clean . " request has been rejected by " . $staff_name . ". Reason: " . $reason_text;
                    } elseif ($st === 'fixed') {
                        $body = "The " . $req_type_clean . " issue has been fixed. Please check and verify the resolution.";
                    } elseif ($st === 'completed') {
                        $body = "Your " . $req_type_clean . " problem has been solved and the request is completed.";
                    } elseif ($st === 'approved') {
                        $body = "Your " . $req_type_clean . " request has been approved by " . $staff_name . ".";
                    } else {
                        $body = "Your " . $req_type_clean . " request status updated to " . strtoupper($st) . " by " . $staff_name . ".";
                    }

                    sendFCM($stu['fcm_token'], $title, $body, $data->request_id, $staff_username, $staff_name, $body, 'request_update', $req_dept);
                }
            } catch (Exception $e) {}

            echo json_encode([
                "success" => true,
                "message" => "Status updated successfully",
                "data" => [
                    "request_id" => $data->request_id,
                    "status" => $data->status,
                    "staff_name" => $staff_name,
                    "staff_role" => $staff_role
                ]
            ]);
        } else {
            echo json_encode(["success" => false, "message" => "Failed to update record in database"]);
        }
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Database error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Incomplete data. Required: request_id, status, warden_id"]);
}
?>
