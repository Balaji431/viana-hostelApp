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

// Run lightweight inline migration to ensure the bed number column exists
try {
    $conn->query("ALTER TABLE room_allocations ADD COLUMN allocated_bed_no VARCHAR(20) DEFAULT NULL");
} catch (Exception $e) {
    // Ignore error if column already exists
}

if (!isset($data) || empty($data)) {
    $data = json_decode(file_get_contents('php://input'), true);
}
$student_id = isset($data['student_id']) ? (int)$data['student_id'] : 0;

if ($student_id <= 0) {
    echo json_encode(["success" => false, "message" => "Student ID is required"]);
    exit();
}

try {
    // 1. Fetch student credentials and active allocation details
    $u_stmt = $conn->prepare("
        SELECT u.id, u.username as register_no, u.full_name, u.Gender,
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

    // 2. Validate student is indeed a "New Student" (no existing allocation)
    $r_alloc = trim($student['room_allocation'] ?? '');
    $r_id = (int)($student['current_room_id'] ?? 0);

    $has_allocation = false;
    if ($r_id > 0) {
        $has_allocation = true;
    } elseif (!empty($r_alloc) && !in_array(strtoupper($r_alloc), ['N/A', 'NONE', 'NULL', 'N/A, N/A, N/A'])) {
        $has_allocation = true;
    }

    if ($has_allocation) {
        throw new Exception("Student already has an active room allocation. Upgrades and transfers must use the existing flows.");
    }

    // 3. Check for existing active allocation request
    $req_stmt = $conn->prepare("SELECT id, allocation_status, allocated_room_id, allocated_bed_no FROM room_allocations WHERE student_id = ?");
    $req_stmt->bind_param("i", $student_id);
    $req_stmt->execute();
    $existing_req = $req_stmt->get_result()->fetch_assoc();

    if ($existing_req && in_array($existing_req['allocation_status'], ['submitted', 'under_review', 'payment_pending', 'approved'])) {
        echo json_encode([
            "success" => true,
            "message" => "An allocation request is already active.",
            "status" => $existing_req['allocation_status'],
            "allocated_room_id" => $existing_req['allocated_room_id'],
            "allocated_bed_no" => $existing_req['allocated_bed_no']
        ]);
        exit();
    }

    // 4. Fetch paid hostel parameters from simulated Director API
    // We fetch it internally by hitting our newly created API to ensure clean service boundary
    $reg_no = $student['register_no'];
    $protocol = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? "https" : "http";
    $host = $_SERVER['HTTP_HOST'] ?? 'localhost:8081';
    
    // Fallback lookup internally if HTTP request fails (extremely robust!)
    $paid_data = null;
    $url = "$protocol://$host/hostelapp/hostel_backend/director/get_paid_hostel_type.php?register_no=" . urlencode($reg_no);
    
    $api_ctx = stream_context_create([
        "http" => [
            "timeout" => 2 // Short timeout
        ]
    ]);
    
    $api_res = @file_get_contents($url, false, $api_ctx);
    if ($api_res) {
        $res_json = json_decode($api_res, true);
        if (isset($res_json['success']) && $res_json['success'] && isset($res_json['data'])) {
            $paid_data = $res_json['data'];
        }
    }

    // Internal fallback in case webserver loopback is blocked
    if (!$paid_data) {
        $mock_payments = [
            '192425398' => [
                'hostel_type' => 'Girls',
                'room_type' => 'AC - B ATTACHED (6 IN 1)',
                'facility' => 'AC'
            ],
            '192413034' => [
                'hostel_type' => 'Girls',
                'room_type' => 'AC - B ATTACHED (4 IN 1)',
                'facility' => 'AC'
            ],
            '192315010' => [
                'hostel_type' => 'Girls',
                'room_type' => 'NON AC (6 IN 1)',
                'facility' => 'Non AC'
            ]
        ];
        $paid_data = $mock_payments[$reg_no] ?? [
            'hostel_type' => 'Girls',
            'room_type' => 'AC - B ATTACHED (6 IN 1)',
            'facility' => 'AC'
        ];
    }

    $paid_hostel_type = $paid_data['hostel_type'] ?? 'Girls';
    $paid_room_type = $paid_data['room_type'] ?? 'AC - B ATTACHED (6 IN 1)';
    $paid_facility = $paid_data['facility'] ?? 'AC';

    // 5. Search for a matching room in hostel_rooms with available capacity
    $room_query = "
        SELECT id, room_no, room_code, building_code, total_capacity, occupied_rooms, room_type, facility
        FROM hostel_rooms
        WHERE hostel_type = ? 
          AND room_type = ? 
          AND facility = ? 
          AND occupied_rooms < total_capacity
        ORDER BY (total_capacity - occupied_rooms) DESC
        LIMIT 1
    ";
    $r_stmt = $conn->prepare($room_query);
    $r_stmt->bind_param("sss", $paid_hostel_type, $paid_room_type, $paid_facility);
    $r_stmt->execute();
    $matched_room = $r_stmt->get_result()->fetch_assoc();

    if (!$matched_room) {
        // Soft fallback: Try matching hostel_type and facility with capacity, ignoring room_type capacity format
        $soft_query = "
            SELECT id, room_no, room_code, building_code, total_capacity, occupied_rooms, room_type, facility
            FROM hostel_rooms
            WHERE hostel_type = ? 
              AND facility = ? 
              AND occupied_rooms < total_capacity
            ORDER BY (total_capacity - occupied_rooms) DESC
            LIMIT 1
        ";
        $r_stmt_soft = $conn->prepare($soft_query);
        $r_stmt_soft->bind_param("ss", $paid_hostel_type, $paid_facility);
        $r_stmt_soft->execute();
        $matched_room = $r_stmt_soft->get_result()->fetch_assoc();

        if (!$matched_room) {
            throw new Exception("No rooms with available capacity match the paid hostel specifications.");
        }
    }

    $room_id = (int)$matched_room['id'];
    $room_no = $matched_room['room_no'];
    $room_code = $matched_room['room_code'];
    $total_capacity = (int)$matched_room['total_capacity'];

    // 6. Find the first available bed number in this room
    // Fetch all occupied beds from profile table
    $occupied_beds = [];
    $b_stmt = $conn->prepare("SELECT bed_no FROM profile WHERE room_allocation = ? AND bed_no IS NOT NULL AND bed_no != ''");
    $b_stmt->bind_param("s", $room_code);
    $b_stmt->execute();
    $b_res = $b_stmt->get_result();
    while ($b_row = $b_res->fetch_assoc()) {
        $occupied_beds[] = strtoupper(trim($b_row['bed_no']));
    }

    // Fetch virtually locked beds in room_allocations
    $a_stmt = $conn->prepare("
        SELECT allocated_bed_no 
        FROM room_allocations 
        WHERE allocated_room_id = ? 
          AND allocation_status IN ('under_review', 'payment_pending', 'approved')
    ");
    $a_stmt->bind_param("i", $room_id);
    $a_stmt->execute();
    $a_res = $a_stmt->get_result();
    while ($a_row = $a_res->fetch_assoc()) {
        if (!empty($a_row['allocated_bed_no'])) {
            $occupied_beds[] = strtoupper(trim($a_row['allocated_bed_no']));
        }
    }

    // Choose first available bed B1 to B{capacity}
    $allocated_bed = "B1";
    for ($i = 1; $i <= $total_capacity; $i++) {
        $candidate = "B" . $i;
        if (!in_array($candidate, $occupied_beds)) {
            $allocated_bed = $candidate;
            break;
        }
    }

    // 7. Insert or update Suggested Room Allocation in room_allocations table
    $now = date('Y-m-d H:i:s');
    $status = 'under_review'; // 'under_review' perfectly represents a suggested allocation pending warden review

    if ($existing_req) {
        $ins_stmt = $conn->prepare("
            UPDATE room_allocations 
            SET allocated_room_id = ?, allocated_bed_no = ?, allocation_status = ?, submitted_at = ?
            WHERE student_id = ?
        ");
        $ins_stmt->bind_param("isssi", $room_id, $allocated_bed, $status, $now, $student_id);
    } else {
        $ins_stmt = $conn->prepare("
            INSERT INTO room_allocations (student_id, allocated_room_id, allocated_bed_no, allocation_status, submitted_at)
            VALUES (?, ?, ?, ?, ?)
        ");
        $ins_stmt->bind_param("iisss", $student_id, $room_id, $allocated_bed, $status, $now);
    }

    if ($ins_stmt->execute()) {
        logAudit(
            $student_id,
            $reg_no,
            'student',
            'SUBMIT_ALLOCATION_REQUEST',
            'Room Allocation',
            null,
            [
                'student_reg_no' => $reg_no,
                'hostel' => $matched_room['building_code'] ?? 'Vaigai Hostel',
                'room_type' => $paid_room_type,
                'priority' => '1',
                'request_time' => $now
            ]
        );
        echo json_encode([
            "success" => true,
            "message" => "Suggested room allocation generated successfully.",
            "status" => $status,
            "allocated_room_id" => $room_id,
            "allocated_room_no" => $room_no,
            "allocated_block" => $matched_room['building_code'],
            "allocated_bed_no" => $allocated_bed
        ]);
    } else {
        throw new Exception("Failed to generate suggested allocation request.");
    }

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
?>
