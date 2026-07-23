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

if (!$conn) {
    echo json_encode(array("status" => "error", "success" => false, "message" => "Database connection failed"));
    exit();
}

$data = json_decode(file_get_contents("php://input"), true);

if (isset($data['student_id'])) {
    $student_id = $conn->real_escape_string($data['student_id']);
    
    // Fetch previous state
    $prev_user = null;
    $prev_profile = null;
    $res = $conn->query("SELECT username, Status, conduct, conduct_remarks FROM users WHERE id = '$student_id'");
    if ($res && $row = $res->fetch_assoc()) {
        $reg_no = $row['username'];
        $prev_user = $row;
        $prof_res = $conn->query("SELECT valid_from, valid_to FROM profile WHERE reg_no = '$reg_no'");
        if ($prof_res) {
            $prev_profile = $prof_res->fetch_assoc();
        }
    }
    $previous_state = json_encode(['users' => $prev_user, 'profile' => $prev_profile]);

    // Update Users table (Status, Conduct, Remarks)
    $updates_users = [];
    if (isset($data['status'])) $updates_users[] = "Status = '" . $conn->real_escape_string($data['status']) . "'";
    if (isset($data['conduct'])) $updates_users[] = "conduct = '" . $conn->real_escape_string($data['conduct']) . "'";
    if (isset($data['remarks'])) $updates_users[] = "conduct_remarks = '" . $conn->real_escape_string($data['remarks']) . "'";
    
    if (!empty($updates_users)) {
        $sql_users = "UPDATE users SET " . implode(", ", $updates_users) . " WHERE id = '$student_id'";
        $conn->query($sql_users);
    }
    
    // Update Profile table (Expiry only)
    if (isset($reg_no)) {
        $updates_profile = [];
        if (isset($data['valid_from'])) $updates_profile[] = "valid_from = '" . $conn->real_escape_string($data['valid_from']) . "'";
        if (isset($data['valid_to'])) $updates_profile[] = "valid_to = '" . $conn->real_escape_string($data['valid_to']) . "'";
        
        if (!empty($updates_profile)) {
            $sql_profile = "UPDATE profile SET " . implode(", ", $updates_profile) . " WHERE reg_no = '$reg_no'";
            $conn->query($sql_profile);
        }
    }

    $after_state = json_encode([
        'users' => [
            'Status' => $data['status'] ?? ($prev_user['Status'] ?? null),
            'conduct' => $data['conduct'] ?? ($prev_user['conduct'] ?? null),
            'conduct_remarks' => $data['remarks'] ?? ($prev_user['conduct_remarks'] ?? null)
        ],
        'profile' => [
            'valid_from' => $data['valid_from'] ?? ($prev_profile['valid_from'] ?? null),
            'valid_to' => $data['valid_to'] ?? ($prev_profile['valid_to'] ?? null)
        ]
    ]);

    logActivity(
        $data['warden_id'] ?? null,
        $data['warden_username'] ?? 'warden',
        'warden',
        'UPDATE_STUDENT_DETAILS',
        'users & profile',
        $previous_state,
        $after_state
    );

    // Send Push Notification if conduct or remarks were updated
    try {
        if (isset($data['conduct']) || isset($data['remarks'])) {
            require_once __DIR__ . '/../send_notification.php';
            $stu_res = $conn->query("SELECT fcm_token, full_name FROM users WHERE id = '$student_id' LIMIT 1");
            if ($stu_res && $stu_row = $stu_res->fetch_assoc()) {
                if (!empty($stu_row['fcm_token'])) {
                    $w_username = $conn->real_escape_string($data['warden_username'] ?? 'warden');
                    $w_res = $conn->query("SELECT full_name FROM users WHERE username = '$w_username' LIMIT 1");
                    $w_name = ($w_res && $w_fetch = $w_res->fetch_assoc()) ? $w_fetch['full_name'] : 'Warden';
                    $title = $w_name . " (Warden)";
                    $c_val = $data['conduct'] ?? ($prev_user['conduct'] ?? 'Good');
                    $c_rem = $data['remarks'] ?? ($prev_user['conduct_remarks'] ?? '');
                    $body = "Disciplinary Notice: Conduct updated to $c_val." . (!empty($c_rem) ? " Remarks: $c_rem" : "");
                    sendFCM($stu_row['fcm_token'], $title, $body, 'conduct_update', $w_username, $w_name, $body, 'conduct', '');
                }
            }
        }
    } catch (Exception $e) {}

    echo json_encode(array("status" => "success", "success" => true, "message" => "Student details updated successfully"));
} else {
    echo json_encode(array("status" => "error", "success" => false, "message" => "Invalid parameters"));
}

$conn->close();
?>
