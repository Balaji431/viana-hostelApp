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
    $poster_username = strtolower(trim($data->username ?? ''));
    if (empty($poster_username)) {
        $poster_username = 'warden1';
    }
    $is_allowed = ($poster_username === 'warden1');
    if (!$is_allowed) {
        $chk_user = $conn->real_escape_string($poster_username);
        $u_res = $conn->query("SELECT full_name, role FROM users WHERE LOWER(username) = '$chk_user' LIMIT 1");
        if ($u_res && $u_row = $u_res->fetch_assoc()) {
            $fn = strtolower($u_row['full_name']);
            $rl = strtolower($u_row['role']);
            if (strpos($fn, 'venkatesh') !== false || $rl === 'admin' || strpos($fn, 'main warden') !== false) {
                $is_allowed = true;
            }
        }
    }

    if (!$is_allowed) {
        echo json_encode(array("status" => "error", "success" => false, "message" => "Access Denied: Only Main Warden (Venkatesh / warden1) has permission to post announcements."));
        exit();
    }

    $title = $conn->real_escape_string($data->title);
    $content = $conn->real_escape_string($data->content);
    $date = date('Y-m-d');
    
    $sql = "INSERT INTO announcements (title, content, date) VALUES ('$title', '$content', '$date')";
    
    if($conn->query($sql)) {
        logActivity(
            $data->user_id ?? null,
            'warden1',
            $data->role ?? 'warden',
            'ADD_ANNOUNCEMENT',
            'announcements',
            null,
            json_encode(['title' => $title, 'content' => $content, 'date' => $date])
        );
        // Send FCM notification to Students, Wardens, Securities, Maintenances/Staff, and Parents
        try {
            require_once __DIR__ . '/../send_notification.php';
            $w_res = $conn->query("SELECT full_name FROM users WHERE username = 'warden1' LIMIT 1");
            $w_row_name = ($w_res && $w_row_fetch = $w_res->fetch_assoc()) ? $w_row_fetch['full_name'] : 'Warden 1';
            $notif_title = $w_row_name . " (Warden)";
            $notif_body = "📢 " . $data->title . ": " . $data->content;

            // 1. Notify users (Students, Wardens, Security, Maintenance, Staff)
            $users_res = $conn->query("SELECT fcm_token FROM users WHERE role IN ('student', 'warden', 'security', 'maintenance', 'staff') AND fcm_token IS NOT NULL AND fcm_token != ''");
            if ($users_res) {
                while ($u_row = $users_res->fetch_assoc()) {
                    if (!empty($u_row['fcm_token'])) {
                        try {
                            sendFCM($u_row['fcm_token'], $notif_title, $notif_body, 'announcement', 'warden1', $w_row_name, $notif_body, 'announcement', '');
                        } catch (Exception $e) {}
                    }
                }
            }

            // 2. Notify Parents
            $parents_res = $conn->query("SELECT fcm_token FROM parent_users WHERE fcm_token IS NOT NULL AND fcm_token != ''");
            if ($parents_res) {
                while ($p_row = $parents_res->fetch_assoc()) {
                    if (!empty($p_row['fcm_token'])) {
                        try {
                            sendFCM($p_row['fcm_token'], $notif_title, $notif_body, 'announcement', 'warden1', $w_row_name, $notif_body, 'announcement', '');
                        } catch (Exception $e) {}
                    }
                }
            }
        } catch (Exception $e) {}

        echo json_encode(array("status" => "success", "success" => true, "message" => "Announcement posted"));
    } else {
        echo json_encode(array("status" => "error", "success" => false, "message" => "Database error: " . $conn->error));
    }
} else {
    echo json_encode(array("status" => "error", "success" => false, "message" => "Incomplete data"));
}

$conn->close();
?>
