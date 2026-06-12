<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
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

try {
    $data = json_decode(file_get_contents('php://input'), true);
    $student_id = (int)($data['student_id'] ?? 0);

    if ($student_id <= 0) throw new Exception("Student ID required");

    // 1. Check if has preferences
    $res = $conn->query("SELECT COUNT(*) as count FROM room_preferences WHERE student_id = $student_id");
    if ($res->fetch_assoc()['count'] == 0) throw new Exception("Please select at least one preference");

    $conn->begin_transaction();

    // 2. Compute queue position
    $q_res = $conn->query("SELECT COUNT(*) as count FROM room_allocations WHERE allocation_status != 'draft'");
    $queue_pos = $q_res->fetch_assoc()['count'] + 1;

    $now = date('Y-m-d H:i:s');

    // 3. Update preferences status
    $up_pref = $conn->prepare("UPDATE room_preferences SET status = 'submitted', submitted_at = ? WHERE student_id = ?");
    $up_pref->bind_param("si", $now, $student_id);
    $up_pref->execute();

    // 4. Update/Create allocation row
    $check_alloc = "SELECT id FROM room_allocations WHERE student_id = ?";
    $st_check = $conn->prepare($check_alloc);
    $st_check->bind_param("i", $student_id);
    $st_check->execute();
    
    if ($st_check->get_result()->num_rows > 0) {
        $up_alloc = $conn->prepare("UPDATE room_allocations SET allocation_status = 'submitted', queue_position = ?, submitted_at = ?, allocated_room_id = NULL, payment_deadline = NULL, approved_by = NULL, approved_at = NULL, notified_of_conflict = 0 WHERE student_id = ?");
        $up_alloc->bind_param("isi", $queue_pos, $now, $student_id);
        $up_alloc->execute();
    } else {
        $ins_alloc = $conn->prepare("INSERT INTO room_allocations (student_id, allocation_status, queue_position, submitted_at) VALUES (?, 'submitted', ?, ?)");
        $ins_alloc->bind_param("iis", $student_id, $queue_pos, $now);
        $ins_alloc->execute();
    }

    $conn->commit();

    // Log audit trail
    $student_name = 'Student';
    $student_reg = '';
    try {
        $st_stmt = $conn->prepare("SELECT full_name, username FROM users WHERE id = ?");
        $st_stmt->bind_param("i", $student_id);
        $st_stmt->execute();
        $st_res = $st_stmt->get_result()->fetch_assoc();
        $student_name = $st_res['full_name'] ?? 'Student';
        $student_reg = $st_res['username'] ?? '';

        $pref_query = $conn->prepare("
            SELECT hr.building_code, hr.room_type 
            FROM room_preferences rp 
            JOIN hostel_rooms hr ON rp.room_id = hr.id 
            WHERE rp.student_id = ? AND rp.priority_order = 1
            LIMIT 1
        ");
        $pref_query->bind_param("i", $student_id);
        $pref_query->execute();
        $pref = $pref_query->get_result()->fetch_assoc();
        $hostel = $pref['building_code'] ?? 'Vaigai Hostel';
        $room_type = $pref['room_type'] ?? '4 IN 1 AC';

        logAudit(
            $student_id,
            $student_reg,
            'student',
            'SUBMIT_ALLOCATION_REQUEST',
            'Room Allocation',
            null,
            [
                'student_reg_no' => $student_reg,
                'hostel' => $hostel,
                'room_type' => $room_type,
                'priority' => '1',
                'request_time' => $now
            ]
        );
    } catch (Exception $e) {
        error_log("Audit logging failed in submit_preferences: " . $e->getMessage());
    }

    // 5. Send push notification to main warden
    try {

        $w_res = $conn->query("SELECT fcm_token FROM users WHERE role = 'warden' LIMIT 1");
        if ($w_res && $w_row = $w_res->fetch_assoc()) {
            $warden_token = $w_row['fcm_token'];
            if (!empty($warden_token)) {
                require_once '../send_notification.php';
                $title = "New Room Allocation Request: $student_name ($student_reg)";
                $body = "$student_name ($student_reg) has submitted a new room allocation request.";
                sendFCM($warden_token, $title, $body, 'allocation_req', $student_id, $student_name, $body, 'room_allocation');
            }
        }
    } catch (Exception $e) {
        // Silently catch notification errors to avoid failing the preference submission
    }

    echo json_encode(["success" => true, "message" => "Preferences submitted successfully", "queue_position" => $queue_pos]);

} catch (Exception $e) {
    if (isset($conn)) $conn->rollback();
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
?>
