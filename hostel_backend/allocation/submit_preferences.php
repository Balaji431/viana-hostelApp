<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/activity_logger.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

try {
    if (isset($GLOBALS['mock_input'])) {
        $data = $GLOBALS['mock_input'];
    } else {
        $data = json_decode(file_get_contents('php://input'), true);
    }
    $student_id = (int)($data['student_id'] ?? 0);

    if ($student_id <= 0) throw new Exception("Student ID required");

    // 1. Check if has preferences
    $res = $conn->query("SELECT COUNT(*) as count FROM room_preferences WHERE student_id = $student_id");
    if ($res->fetch_assoc()['count'] == 0) throw new Exception("Please select at least one preference");

    // Fetch student info
    $st_stmt = $conn->prepare("SELECT full_name, username, Gender FROM users WHERE id = ?");
    $st_stmt->bind_param("i", $student_id);
    $st_stmt->execute();
    $st_res = $st_stmt->get_result()->fetch_assoc();
    if (!$st_res) {
        throw new Exception("Student user record not found");
    }
    $student_name = $st_res['full_name'] ?? 'Student';
    $student_reg = $st_res['username'] ?? '';
    $gender = $st_res['Gender'] ?? 'Female';

    // Fetch paid details
    $default_hostel_type = (stripos($gender, 'female') !== false || stripos($gender, 'girls') !== false) ? 'Girls' : 'Boys';
    $stmtPay = $conn->prepare("SELECT * FROM vstudy_payments WHERE TRIM(roll_number) = TRIM(?) LIMIT 1");
    $stmtPay->bind_param("s", $student_reg);
    $stmtPay->execute();
    $payRow = $stmtPay->get_result()->fetch_assoc();

    if ($payRow) {
        $hPref    = $payRow['hostel_preference'] ?? '';
        $hType    = (stripos($hPref, 'girls') !== false || stripos($payRow['gender'] ?? '', 'female') !== false) ? 'Girls' : 'Boys';
        $facility = (stripos($hPref, 'non ac') !== false || stripos($hPref, 'non-ac') !== false || stripos($hPref, 'non a/c') !== false) ? 'Non AC' : 'AC';
        $paid_hostel_name = $payRow['hostel_name'] ?? (($hType === 'Girls') ? 'Vaigai Hostel' : 'Krishna Hostel');
        $paid_room_type = $hPref;
        $payment_status = $payRow['payment_status'] ?? 'Paid';
    } else {
        $paid_hostel_name = ($default_hostel_type === 'Girls') ? 'Vaigai Hostel' : 'Krishna Hostel';
        $paid_room_type = ($default_hostel_type === 'Girls') ? 'AC - B ATTACHED (6 IN 1)' : '4 IN 1 AC';
        $payment_status = 'Paid';
    }

    // Resolve paid_hostel_id
    $paid_hostel_id = 0;
    $norm_hostel    = preg_replace('/\s*hostel\s*/i', '', $paid_hostel_name);
    $search_pattern = "%" . trim($norm_hostel) . "%";
    $h_stmt = $conn->prepare("SELECT id FROM hostel_type WHERE hostel_name LIKE ? LIMIT 1");
    $h_stmt->bind_param("s", $search_pattern);
    $h_stmt->execute();
    $h_row = $h_stmt->get_result()->fetch_assoc();
    if ($h_row) {
        $paid_hostel_id = (int)$h_row['id'];
    }

    $conn->begin_transaction();

    $q_res = $conn->query("SELECT COUNT(*) as count FROM allocation_requests WHERE status != 'draft'");
    $queue_pos = $q_res->fetch_assoc()['count'] + 1;

    $now = date('Y-m-d H:i:s');

    // 3. Update preferences status
    $up_pref = $conn->prepare("UPDATE room_preferences SET status = 'submitted', submitted_at = ? WHERE student_id = ?");
    $up_pref->bind_param("si", $now, $student_id);
    $up_pref->execute();

    $check_alloc = "SELECT id FROM allocation_requests WHERE student_id = ?";
    $st_check = $conn->prepare($check_alloc);
    $st_check->bind_param("i", $student_id);
    $st_check->execute();
    
    if ($st_check->get_result()->num_rows > 0) {
        $up_alloc = $conn->prepare("UPDATE allocation_requests SET status = 'submitted', request_status = 'pending', student_reg_no = ?, student_name = ?, paid_hostel_id = ?, paid_hostel_name = ?, paid_room_type = ?, payment_status = ?, queue_position = ?, created_at = ?, selected_room_id = NULL, payment_deadline = NULL, approved_by_username = NULL, approved_at = NULL, notified_of_conflict = 0 WHERE student_id = ?");
        $up_alloc->bind_param("ssisssisii", $student_reg, $student_name, $paid_hostel_id, $paid_hostel_name, $paid_room_type, $payment_status, $queue_pos, $now, $student_id);
        $up_alloc->execute();
    } else {
        $ins_alloc = $conn->prepare("INSERT INTO allocation_requests (student_id, student_reg_no, student_name, paid_hostel_id, paid_hostel_name, paid_room_type, payment_status, request_status, status, queue_position, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', 'submitted', ?, ?)");
        $ins_alloc->bind_param("ississsis", $student_id, $student_reg, $student_name, $paid_hostel_id, $paid_hostel_name, $paid_room_type, $payment_status, $queue_pos, $now);
        $ins_alloc->execute();
    }

    $conn->commit();

    // Log audit trail
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

    // 5. Send push notification to Wardens
    try {
        require_once __DIR__ . '/../send_notification.php';
        // Title format: Student Name (Reg No) -> e.g. BIRAJ CHAUDHARY (192514071)
        $title = $student_name . " (" . $student_reg . ")";
        $body = "Room Allocation Preference submitted: Hostel: " . $hostel . " | Room Type: " . $room_type;

        $w_res = $conn->query("SELECT fcm_token FROM users WHERE role = 'warden' AND fcm_token IS NOT NULL AND fcm_token != ''");
        if ($w_res) {
            while ($w_row = $w_res->fetch_assoc()) {
                $warden_token = $w_row['fcm_token'];
                if (!empty($warden_token)) {
                    try {
                        sendFCM($warden_token, $title, $body, 'allocation_req', $student_id, $student_name, $body, 'room_allocation', 'warden');
                    } catch (Exception $e) {}
                }
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
