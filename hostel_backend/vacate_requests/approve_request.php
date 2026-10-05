<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/activity_logger.php';
require_once __DIR__ . '/../utils/vstudy_sync_helper.php';
require_once __DIR__ . '/../utils/auth_helper.php';

$authUser = requireAuth(['warden', 'admin', 'super_admin']);

$database = new DatabaseMysqli();
$conn = $database->getConnection();

if (!$conn) {
    echo json_encode(["status" => "error", "success" => false, "message" => "Database connection failed"]);
    exit();
}

$raw = file_get_contents("php://input");
$data = json_decode($raw, true) ?? [];

$request_id = trim($data['request_id'] ?? ($_POST['request_id'] ?? ''));
$warden_username = $authUser['username'] ?? 'warden';
$warden_name = $authUser['full_name'] ?? ($data['warden_name'] ?? 'Hostel Warden');
$remarks = trim($data['remarks'] ?? ($_POST['remarks'] ?? 'Early vacate approved by warden. Room verified & freed.'));

if (empty($request_id)) {
    echo json_encode(["status" => "error", "success" => false, "message" => "Request ID is required."]);
    $conn->close();
    exit();
}

// 1. Fetch request details
$stmt = $conn->prepare("SELECT * FROM vacate_requests WHERE request_id = ? FOR UPDATE");
$stmt->bind_param("s", $request_id);
$stmt->execute();
$req = $stmt->get_result()->fetch_assoc();

if (!$req) {
    echo json_encode(["status" => "error", "success" => false, "message" => "Vacate request not found."]);
    $conn->close();
    exit();
}

if ($req['status'] !== 'pending') {
    echo json_encode(["status" => "error", "success" => false, "message" => "This request has already been " . $req['status'] . "."]);
    $conn->close();
    exit();
}

$student_id = (int)$req['student_id'];
$reg_no = $req['student_reg_no'];
$room_number = trim($req['room_number']);
$expected_vacate_date = $req['expected_vacate_date'];
$renewal_date = $req['renewal_date'];
$full_name = $req['student_name'];
$hostel_name = $req['hostel_name'];

// 2. Fetch student user and profile
$u_stmt = $conn->prepare("SELECT * FROM users WHERE id = ? OR username = ?");
$u_stmt->bind_param("is", $student_id, $reg_no);
$u_stmt->execute();
$user_row = $u_stmt->get_result()->fetch_assoc();

$p_stmt = $conn->prepare("SELECT * FROM profile WHERE reg_no = ?");
$p_stmt->bind_param("s", $reg_no);
$p_stmt->execute();
$prof_row = $p_stmt->get_result()->fetch_assoc();

$conn->begin_transaction();

try {
    // A. Update vacate_requests status
    $up_vr = $conn->prepare("
        UPDATE vacate_requests 
        SET status = 'approved',
            processed_by = ?,
            processed_by_name = ?,
            processed_at = NOW(),
            remarks = ?,
            updated_at = NOW()
        WHERE request_id = ?
    ");
    $up_vr->bind_param("ssss", $warden_username, $warden_name, $remarks, $request_id);
    $up_vr->execute();

    // B. Record in checkout_students
    $conn->query("CREATE TABLE IF NOT EXISTS checkout_students (
        id INT AUTO_INCREMENT PRIMARY KEY,
        student_id INT NOT NULL,
        reg_no VARCHAR(255) NOT NULL,
        full_name VARCHAR(255) NOT NULL,
        hostel_name VARCHAR(255) NULL,
        room_code VARCHAR(255) NULL,
        conduct VARCHAR(255) NULL,
        conduct_remarks TEXT NULL,
        checked_out_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        checked_out_by VARCHAR(255) NULL,
        profile_data TEXT NULL,
        user_data TEXT NULL
    )");

    $ins_co = $conn->prepare("
        INSERT INTO checkout_students (
            student_id, reg_no, full_name, hostel_name, room_code,
            conduct, conduct_remarks, checked_out_at, checked_out_by,
            profile_data, user_data
        ) VALUES (?, ?, ?, ?, ?, 'Good', ?, NOW(), ?, ?, ?)
    ");
    $p_json = json_encode($prof_row);
    $u_json = json_encode($user_row);
    $co_remarks = "Early Vacate approved (Requested date: $expected_vacate_date, Tenure till: $renewal_date). $remarks";
    $ins_co->bind_param(
        "issssssss",
        $student_id,
        $reg_no,
        $full_name,
        $hostel_name,
        $room_number,
        $co_remarks,
        $warden_name,
        $p_json,
        $u_json
    );
    $ins_co->execute();

    // C. Update users table: deallocate room but KEEP ACCOUNT ACTIVE so student can log in and view clearance status
    $up_u = $conn->prepare("UPDATE users SET RoomId = NULL, RoomType = NULL, HostelName = NULL, Status = '1', is_active = 1 WHERE id = ? OR username = ?");
    $up_u->bind_param("is", $student_id, $reg_no);
    $up_u->execute();

    // D. Update profile table: mark room cleared and remaining days 0
    $up_p = $conn->prepare("
        UPDATE profile 
        SET room_allocation = NULL,
            current_room_id = NULL,
            hostel_name = NULL,
            valid_to = ?,
            remaining_days = 0 
        WHERE reg_no = ?
    ");
    $up_p->bind_param("ss", $expected_vacate_date, $reg_no);
    $up_p->execute();

    // D2. Update vstudy_payments table: clear room allocation and mark vacated
    $up_vp = $conn->prepare("
        UPDATE vstudy_payments 
        SET room_number = NULL,
            payment_status = 'EXPIRED',
            application_status = 'VACATED',
            remaining_days = 0 
        WHERE roll_number = ?
    ");
    $up_vp->bind_param("s", $reg_no);
    $up_vp->execute();

    // E. CRITICAL: FREE THE ROOM AND BED IMMEDIATELY
    if (!empty($room_number) && $room_number !== 'vacated' && $room_number !== 'unallocated') {
        // 1. Update hostel_rooms
        $up_hr = $conn->prepare("
            UPDATE hostel_rooms 
            SET occupied_rooms = GREATEST(0, occupied_rooms - 1),
                available_rooms = LEAST(total_capacity, available_rooms + 1)
            WHERE TRIM(room_code) = TRIM(?)
        ");
        $up_hr->bind_param("s", $room_number);
        $up_hr->execute();

        // 2. Update rooms_groups_details
        $up_rgd = $conn->prepare("
            UPDATE rooms_groups_details 
            SET occupied_beds = GREATEST(0, occupied_beds - 1),
                available_beds = LEAST(total_beds, available_beds + 1)
            WHERE TRIM(room_number) = TRIM(?)
        ");
        $up_rgd->bind_param("s", $room_number);
        $up_rgd->execute();

        // 3. Update room_master (Note: column is total_beds, NOT total_capacity)
        $up_rm = $conn->prepare("
            UPDATE room_master 
            SET occupied_beds = GREATEST(0, occupied_beds - 1),
                available_beds = LEAST(total_beds, available_beds + 1)
            WHERE TRIM(room_code) = TRIM(?) OR TRIM(room_no) = TRIM(?)
        ");
        $up_rm->bind_param("ss", $room_number, $room_number);
        $up_rm->execute();

        // 4. Recalculate room counts dynamically from active occupants
        $cnt_stmt = $conn->prepare("
            SELECT COUNT(DISTINCT p.reg_no) as active_count
            FROM profile p
            JOIN users u ON (p.reg_no = u.username OR p.user_id = u.id)
            LEFT JOIN checkout_students co ON (co.reg_no = p.reg_no)
            WHERE (p.room_allocation = ? OR u.RoomId = ?)
              AND (p.room_allocation IS NOT NULL AND p.room_allocation != '' AND p.room_allocation != 'vacated')
              AND (u.RoomId IS NOT NULL AND u.RoomId != '' AND u.RoomId != 'vacated')
              AND co.id IS NULL
              AND u.is_active = 1
        ");
        $cnt_stmt->bind_param("ss", $room_number, $room_number);
        $cnt_stmt->execute();
        $cnt_res = $cnt_stmt->get_result()->fetch_assoc();
        $live_count = (int)($cnt_res['active_count'] ?? 0);

        $sync_rm = $conn->prepare("
            UPDATE room_master 
            SET occupied_beds = ?,
                available_beds = GREATEST(0, total_beds - ? - assigned_pending)
            WHERE TRIM(room_code) = TRIM(?) OR TRIM(room_no) = TRIM(?)
        ");
        $sync_rm->bind_param("iiss", $live_count, $live_count, $room_number, $room_number);
        $sync_rm->execute();

        $sync_rgd = $conn->prepare("
            UPDATE rooms_groups_details 
            SET occupied_beds = ?,
                available_beds = GREATEST(0, total_beds - ?)
            WHERE TRIM(room_number) = TRIM(?)
        ");
        $sync_rgd->bind_param("iis", $live_count, $live_count, $room_number);
        $sync_rgd->execute();

        // 5. Ensure no vacated_room_locks blocks this bed
        $del_locks = $conn->prepare("
            DELETE FROM vacated_room_locks 
            WHERE student_reg_no = ? OR room_number = ?
        ");
        $del_locks->bind_param("ss", $reg_no, $room_number);
        $del_locks->execute();

        // 6. Invalidate session cache if active
        if (session_status() === PHP_SESSION_NONE) {
            @session_start();
        }
        unset($_SESSION['student_map_v5'], $_SESSION['student_map_expire_v5'], $_SESSION['room_id_map_v5'], $_SESSION['student_map_v4'], $_SESSION['room_id_map_v4']);
    }

    // F. Audit Logging
    $conn->query("
        INSERT INTO audit_logs (username, role, action, module_name, new_value, ip_address) 
        VALUES (
            '" . $conn->real_escape_string($warden_username) . "', 
            'warden', 
            'STUDENT_EARLY_VACATE_APPROVED', 
            'vacate_requests', 
            '" . $conn->real_escape_string(json_encode([
                'request_id' => $request_id,
                'student_reg_no' => $reg_no,
                'student_name' => $full_name,
                'room_freed' => $room_number,
                'expected_vacate_date' => $expected_vacate_date,
                'renewal_date' => $renewal_date,
                'status' => 'freed_and_archived'
            ])) . "',
            '" . ($_SERVER['REMOTE_ADDR'] ?? '127.0.0.1') . "'
        )
    ");

    $conn->commit();

    // G. Outbound Real-Time Sync to VStudy ERP & log to vstudy_webhook_events
    $vstudy_sync = null;
    try {
        $vstudy_sync = syncVacateToVStudy($reg_no, $room_number, $hostel_name, $remarks, generateUuidV4());
    } catch (Exception $vErr) {
        error_log("Failed to sync vacate to VStudy: " . $vErr->getMessage());
    }

    echo json_encode([
        "status" => "success",
        "success" => true,
        "message" => "Vacate request approved successfully. Student $full_name is checked out and Room $room_number has been FREED and made available for allocation.",
        "data" => [
            "request_id" => $request_id,
            "student_reg_no" => $reg_no,
            "room_freed" => $room_number,
            "status" => "approved"
        ],
        "vstudy_sync" => $vstudy_sync
    ]);

} catch (Exception $e) {
    $conn->rollback();
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => "Failed to approve vacate request: " . $e->getMessage()
    ]);
}

$conn->close();
?>
