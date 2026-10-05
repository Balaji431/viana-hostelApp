<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/activity_logger.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

if(!empty($data->title) && !empty($data->content)) {
    $poster_username = strtolower(trim($data->username ?? ''));
    if (empty($poster_username)) {
        $poster_username = 'warden1';
    }
    
    $chk_user = $conn->real_escape_string($poster_username);
    $u_res = $conn->query("SELECT id, full_name, role, Designation, can_announce FROM users WHERE LOWER(username) = '$chk_user' LIMIT 1");
    
    $poster_name = 'Warden';
    $poster_role = 'warden';
    $poster_id = null;
    $is_allowed = ($poster_username === 'warden1');

    if ($u_res && $u_row = $u_res->fetch_assoc()) {
        $fn = strtolower($u_row['full_name'] ?? '');
        $rl = strtolower($u_row['role'] ?? '');
        $ds = strtolower($u_row['Designation'] ?? '');
        $ca = (int)($u_row['can_announce'] ?? 0);
        $poster_name = !empty($u_row['full_name']) ? $u_row['full_name'] : 'Warden';
        $poster_role = !empty($u_row['role']) ? $u_row['role'] : 'warden';
        $poster_id = $u_row['id'] ?? null;

        // Allow all wardens, main warden, admin, super admin, or users with can_announce = 1
        if (
            $ca === 1 ||
            $rl === 'warden' || 
            $rl === 'main warden' || 
            $rl === 'admin' || 
            $rl === 'super_admin' || 
            strpos($rl, 'warden') !== false ||
            strpos($fn, 'venkatesh') !== false || 
            strpos($ds, 'warden') !== false
        ) {
            $is_allowed = true;
        }
    }

    if (!$is_allowed) {
        echo json_encode(array("status" => "error", "success" => false, "message" => "Access Denied: Only Wardens and Admins have permission to post announcements."));
        exit();
    }

    $title = $conn->real_escape_string($data->title);
    $content = $conn->real_escape_string($data->content);
    $date = date('Y-m-d');
    $esc_poster_name = $conn->real_escape_string($poster_name);
    
    // Insert announcement with posted_by and warden_name
    $sql = "INSERT INTO announcements (title, content, date, posted_by, warden_name) VALUES ('$title', '$content', '$date', '$chk_user', '$esc_poster_name')";
    
    $inserted = $conn->query($sql);
    if(!$inserted) {
        // Fallback in case columns are missing
        $sql = "INSERT INTO announcements (title, content, date) VALUES ('$title', '$content', '$date')";
        $inserted = $conn->query($sql);
    }

    if (!$inserted) {
        echo json_encode(array("status" => "error", "success" => false, "message" => "Database error: " . $conn->error));
        exit();
    }

    // Log Activity
    logActivity(
        $data->user_id ?? $poster_id,
        $poster_username,
        $poster_role,
        'ADD_ANNOUNCEMENT',
        'announcements',
        null,
        json_encode(['title' => $title, 'content' => $content, 'date' => $date, 'posted_by' => $poster_username, 'warden_name' => $poster_name])
    );

    // Send immediate HTTP response to client
    echo json_encode(array("status" => "success", "success" => true, "message" => "Announcement posted successfully"));

    // Flush response to client if running under FastCGI / PHP-FPM
    if (function_exists('fastcgi_finish_request')) {
        fastcgi_finish_request();
    }

    // Send FCM notification in background to Students, Wardens, Securities, Maintenances/Staff, and Parents
    try {
        if (file_exists(__DIR__ . '/../send_notification.php')) {
            require_once __DIR__ . '/../send_notification.php';
            $notif_title = $poster_name . " (Warden)";
            $notif_body = "📢 " . $data->title . ": " . $data->content;

            // 1. Notify users (Students, Wardens, Security, Maintenance, Staff)
            $users_res = $conn->query("SELECT fcm_token FROM users WHERE role IN ('student', 'warden', 'security', 'maintenance', 'staff') AND fcm_token IS NOT NULL AND fcm_token != '' LIMIT 200");
            if ($users_res) {
                while ($u_row = $users_res->fetch_assoc()) {
                    if (!empty($u_row['fcm_token'])) {
                        try {
                            sendFCM($u_row['fcm_token'], $notif_title, $notif_body, 'announcement', $poster_username, $poster_name, $notif_body, 'announcement', '');
                        } catch (Exception $e) {}
                    }
                }
            }

            // 2. Notify Parents
            $parents_res = $conn->query("SELECT fcm_token FROM parent_users WHERE fcm_token IS NOT NULL AND fcm_token != '' LIMIT 100");
            if ($parents_res) {
                while ($p_row = $parents_res->fetch_assoc()) {
                    if (!empty($p_row['fcm_token'])) {
                        try {
                            sendFCM($p_row['fcm_token'], $notif_title, $notif_body, 'announcement', $poster_username, $poster_name, $notif_body, 'announcement', '');
                        } catch (Exception $e) {}
                    }
                }
            }
        }
    } catch (Exception $e) {}

} else {
    echo json_encode(array("status" => "error", "success" => false, "message" => "Incomplete data"));
}

$conn->close();
?>
