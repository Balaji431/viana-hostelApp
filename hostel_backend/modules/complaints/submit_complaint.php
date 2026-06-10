<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../send_notification.php';

$data = json_decode(file_get_contents("php://input"), true);

$student_id = $data['student_id'] ?? null;
$staff_username = $data['staff_username'] ?? null;
$staff_role = $data['staff_role'] ?? null;
$message = $data['message'] ?? null;

if (!$student_id || !$staff_username || !$staff_role || !$message) {
    echo json_encode(["success" => false, "message" => "Missing required fields"]);
    exit;
}

$message = trim($message);
if (strlen($message) < 10) {
    echo json_encode(["success" => false, "message" => "Complaint message must be at least 10 characters long"]);
    exit;
}

try {
    $database = new Database();
    $db = $database->getConnection();

    // 1. Anti-spam Check: Existing Pending or Under Review complaint against the same staff
    $spam_query = "SELECT id FROM complaints 
                   WHERE student_id = :student_id 
                   AND staff_username = :staff_username 
                   AND status IN ('Pending', 'Under Review') 
                   LIMIT 1";
    $spam_stmt = $db->prepare($spam_query);
    $spam_stmt->bindParam(':student_id', $student_id);
    $spam_stmt->bindParam(':staff_username', $staff_username);
    $spam_stmt->execute();

    if ($spam_stmt->fetch(PDO::FETCH_ASSOC)) {
        echo json_encode([
            "success" => false, 
            "message" => "You already have a pending or under-review complaint against this staff member."
        ]);
        exit;
    }

    // 2. Anti-spam Check: Rapid submissions in the last 10 minutes
    $recent_query = "SELECT id FROM complaints 
                     WHERE student_id = :student_id 
                     AND staff_username = :staff_username 
                     AND created_at >= DATE_SUB(NOW(), INTERVAL 10 MINUTE) 
                     LIMIT 1";
    $recent_stmt = $db->prepare($recent_query);
    $recent_stmt->bindParam(':student_id', $student_id);
    $recent_stmt->bindParam(':staff_username', $staff_username);
    $recent_stmt->execute();

    if ($recent_stmt->fetch(PDO::FETCH_ASSOC)) {
        echo json_encode([
            "success" => false, 
            "message" => "Please wait a few minutes before submitting another complaint against this staff member."
        ]);
        exit;
    }

    // 3. Insert complaint
    $insert_query = "INSERT INTO complaints (student_id, staff_username, staff_role, message, status) 
                     VALUES (:student_id, :staff_username, :staff_role, :message, 'Pending')";
    $insert_stmt = $db->prepare($insert_query);
    $insert_stmt->bindParam(':student_id', $student_id);
    $insert_stmt->bindParam(':staff_username', $staff_username);
    $insert_stmt->bindParam(':staff_role', $staff_role);
    $insert_stmt->bindParam(':message', $message);

    if ($insert_stmt->execute()) {
        // 4. Retrieve student & staff names for personalized notification
        $student_name = "A student";
        $u_stmt = $db->prepare("SELECT full_name FROM users WHERE id = :id LIMIT 1");
        $u_stmt->bindParam(':id', $student_id);
        $u_stmt->execute();
        if ($student_row = $u_stmt->fetch(PDO::FETCH_ASSOC)) {
            $student_name = $student_row['full_name'];
        }

        $staff_name = $staff_username;
        $ms_stmt = $db->prepare("SELECT name FROM mapping_staff WHERE username = :username LIMIT 1");
        $ms_stmt->bindParam(':username', $staff_username);
        $ms_stmt->execute();
        if ($staff_row = $ms_stmt->fetch(PDO::FETCH_ASSOC)) {
            $staff_name = $staff_row['name'];
        }

        // 5. Send FCM notification to all active Administrators
        $admin_stmt = $db->query("SELECT fcm_token FROM users WHERE role = 'admin' AND fcm_token IS NOT NULL AND fcm_token != ''");
        $admin_tokens = $admin_stmt->fetchAll(PDO::FETCH_COLUMN);

        $notif_title = "🚨 New Complaint Raised";
        $notif_body = "$student_name has raised a complaint against $staff_name ($staff_role).";

        foreach ($admin_tokens as $token) {
            if (!empty($token)) {
                sendFCM($token, $notif_title, $notif_body, '', '', '', '', 'complaint', '');
            }
        }

        echo json_encode([
            "success" => true,
            "message" => "Complaint raised successfully. Administrators have been notified."
        ]);
    } else {
        echo json_encode(["success" => false, "message" => "Failed to submit complaint"]);
    }

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Server error: " . $e->getMessage()]);
}
?>
