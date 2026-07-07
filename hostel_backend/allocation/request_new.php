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

$data = json_decode(file_get_contents('php://input'), true);
$student_id = isset($data['student_id']) ? (int)$data['student_id'] : 0;

if ($student_id <= 0) {
    echo json_encode(["success" => false, "message" => "Student ID is required"]);
    exit();
}

try {
    // ── 1. Fetch student details ──────────────────────────────────────────────
    $u_stmt = $conn->prepare("
        SELECT u.id, u.username AS register_no, u.full_name, u.Gender,
               p.room_allocation, p.current_room_id
         FROM users u
         LEFT JOIN profile p ON u.username = p.reg_no
         WHERE u.id = ? AND u.role = 'student'
    ");
    $u_stmt->bind_param("i", $student_id);
    $u_stmt->execute();
    $student = $u_stmt->get_result()->fetch_assoc();

    if (!$student) {
        throw new Exception("Student not found");
    }

    // ── 2. Guard: student must not already have a physical room ───────────────
    $r_alloc = trim($student['room_allocation'] ?? '');
    $r_id    = (int)($student['current_room_id'] ?? 0);

    if ($r_id > 0 || (!empty($r_alloc) && !in_array(strtoupper($r_alloc), ['N/A', 'NONE', 'NULL', 'N/A, N/A, N/A']))) {
        throw new Exception("Student already has an active room allocation. Upgrades and transfers must use the existing flows.");
    }

    // ── 3. Guard: no duplicate active request ─────────────────────────────────
    $req_stmt = $conn->prepare("
        SELECT id, request_status, selected_room_id, selected_bed_number,
               paid_hostel_name, paid_room_type
        FROM allocation_requests
        WHERE student_id = ?
        ORDER BY id DESC
        LIMIT 1
    ");
    $req_stmt->bind_param("i", $student_id);
    $req_stmt->execute();
    $existing_req = $req_stmt->get_result()->fetch_assoc();

    // Block only if there is an active (non-terminal) request
    if ($existing_req && in_array($existing_req['request_status'], ['pending', 'claimed', 'approved'])) {
        echo json_encode([
            "success"         => false,
            "message"         => "An allocation request is already active.",
            "status"          => $existing_req['request_status'],
            "allocation_id"   => (int)$existing_req['id'],
            "allocated_hostel_name" => $existing_req['paid_hostel_name'],
        ]);
        exit();
    }

    // ── 4. Fetch paid hostel details from vstudy_payments ─────────────────────
    $reg_no = $student['register_no'];
    $gender = $student['Gender'] ?? 'Female';
    $default_hostel_type = (stripos($gender, 'female') !== false || stripos($gender, 'girls') !== false) ? 'Girls' : 'Boys';

    $paid_data = null;
    $stmtPay = $conn->prepare("SELECT * FROM vstudy_payments WHERE TRIM(roll_number) = TRIM(?) LIMIT 1");
    $stmtPay->bind_param("s", $reg_no);
    $stmtPay->execute();
    $payRow = $stmtPay->get_result()->fetch_assoc();

    if ($payRow) {
        $hPref    = $payRow['hostel_preference'] ?? '';
        $hType    = (stripos($hPref, 'girls') !== false || stripos($payRow['gender'] ?? '', 'female') !== false) ? 'Girls' : 'Boys';
        $facility = (stripos($hPref, 'non ac') !== false || stripos($hPref, 'non-ac') !== false || stripos($hPref, 'non a/c') !== false) ? 'Non AC' : 'AC';
        $paid_data = [
            'hostel_type'    => $hType,
            'hostel_name'    => $payRow['hostel_name'] ?? (($hType === 'Girls') ? 'Vaigai Hostel' : 'Krishna Hostel'),
            'room_type'      => $hPref,
            'facility'       => $facility,
            'payment_status' => $payRow['payment_status'] ?? 'Paid',
        ];
    } else {
        // Fallback: no payment record — use gender-based default
        $paid_data = [
            'hostel_type'    => $default_hostel_type,
            'hostel_name'    => ($default_hostel_type === 'Girls') ? 'Vaigai Hostel' : 'Krishna Hostel',
            'room_type'      => ($default_hostel_type === 'Girls') ? 'AC - B ATTACHED (6 IN 1)' : '4 IN 1 AC',
            'facility'       => 'AC',
            'payment_status' => 'Paid',
        ];
    }

    $paid_room_type    = trim($paid_data['room_type'] ?? '');
    $raw_hostel_name   = trim($paid_data['hostel_name'] ?? '');
    $payment_status    = $paid_data['payment_status'] ?? 'Paid';

    if (empty($raw_hostel_name)) {
        throw new Exception("Hostel name is blank in your payment record. Cannot submit allocation request.");
    }

    // ── 5. Normalise the hostel name (strip trailing "Hostel" word for matching)
    // We store exactly what vstudy_payments says — no lookup in hostel_rooms required.
    // The warden queue uses isHostelNameMatch() which handles "Noyyal" == "Noyyal Hostel".
    $paid_hostel_name = $raw_hostel_name;

    // Resolve paid_hostel_id from hostel_type (nullable — do not fail if absent)
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

    // ── 6. Insert or re-open request ──────────────────────────────────────────
    $now            = date('Y-m-d H:i:s');
    $request_status = 'pending';
    $old_status     = 'under_review'; // backward compat with old status column

    $student_name = $student['full_name'] ?? '';

    if ($existing_req) {
        // Re-open a rejected / cancelled request
        $ins_stmt = $conn->prepare("
            UPDATE allocation_requests
            SET request_status = ?, status = ?,
                student_reg_no = ?, student_name = ?,
                paid_hostel_id = ?, paid_hostel_name = ?, paid_room_type = ?,
                payment_status = ?,
                selected_room_id = NULL, selected_bed_number = NULL, selected_room_number = NULL,
                claimed_by_username = NULL, claimed_at = NULL,
                approved_by_username = NULL, approved_at = NULL,
                remarks = NULL, created_at = ?
            WHERE student_id = ?
        ");
        $ins_stmt->bind_param(
            "ssssissssi",
            $request_status, $old_status,
            $reg_no, $student_name,
            $paid_hostel_id, $paid_hostel_name, $paid_room_type,
            $payment_status,
            $now,
            $student_id
        );
    } else {
        $ins_stmt = $conn->prepare("
            INSERT INTO allocation_requests
                (student_id, student_reg_no, student_name,
                 paid_hostel_id, paid_hostel_name, paid_room_type, payment_status,
                 request_status, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");
        $ins_stmt->bind_param(
            "ississssss",
            $student_id, $reg_no, $student_name,
            $paid_hostel_id, $paid_hostel_name, $paid_room_type, $payment_status,
            $request_status, $old_status, $now
        );
    }

    if (!$ins_stmt->execute()) {
        throw new Exception("Failed to submit room allocation request: " . $conn->error);
    }

    $alloc_id = $existing_req ? (int)$existing_req['id'] : $conn->insert_id;

    // ── 7. Audit log ──────────────────────────────────────────────────────────
    logAudit(
        $student_id, $reg_no, 'student',
        'SUBMIT_ALLOCATION_REQUEST', 'Room Allocation', null,
        [
            'student_reg_no' => $reg_no,
            'hostel'         => $paid_hostel_name,
            'room_type'      => $paid_room_type,
            'request_time'   => $now
        ]
    );

    echo json_encode([
        "success"               => true,
        "message"               => "Room allocation request submitted successfully.",
        "status"                => $request_status,
        "allocation_id"         => $alloc_id,
        "allocated_hostel_name" => $paid_hostel_name,
        "allocated_room_type"   => $paid_room_type,
        "allocated_room_id"     => null,
        "allocated_room_no"     => null,
        "allocated_bed_no"      => null,
    ]);

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
?>
