<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
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

$data = json_decode(file_get_contents('php://input'), true);
$action = $data['action'] ?? 'preview'; // 'preview' or 'confirm'
$request_ids = $data['request_ids'] ?? [];
$warden_id = (int)($data['warden_id'] ?? 0);

if (empty($request_ids)) {
    echo json_encode(["success" => false, "message" => "No requests selected"]);
    exit;
}

// Clean IDs
$ids = implode(',', array_map('intval', $request_ids));

try {
    // 1. Fetch current live capacities of ALL rooms
    $rooms_query = "SELECT hr.id, hr.room_no, hr.building_code, hr.total_capacity, hr.occupied_rooms, hr.room_type, hr.floor, hr.hostel_name,
                    (SELECT COUNT(*) FROM room_allocations WHERE allocated_room_id = hr.id AND allocation_status = 'payment_pending' AND payment_deadline > NOW()) as hold_count
                    FROM hostel_rooms hr";
    $r_res = $conn->query($rooms_query);
    
    $rooms = [];
    while ($r = $r_res->fetch_assoc()) {
        $available = (int)$r['total_capacity'] - (int)$r['occupied_rooms'] - (int)$r['hold_count'];
        $r['available'] = max(0, $available);
        $rooms[(int)$r['id']] = $r;
    }

    // 2. Fetch the selected requests, ordered by submission time (asc)
    $req_query = "SELECT ra.id as request_id, ra.student_id, u.full_name as student_name, u.username as student_reg_no 
                  FROM room_allocations ra
                  JOIN users u ON ra.student_id = u.id
                  WHERE ra.id IN ($ids) AND ra.allocation_status = 'submitted'
                  ORDER BY ra.submitted_at ASC";
    $req_res = $conn->query($req_query);
    
    $results = [];
    $matched_count = 0;
    $rejected_count = 0;

    $now = new DateTime();
    $deadline = clone $now;
    $deadline->modify('+24 hours');
    $deadline_str = $deadline->format('Y-m-d H:i:s');
    $now_str = $now->format('Y-m-d H:i:s');

    if ($action === 'confirm') {
        $conn->begin_transaction();
    }

    while ($req = $req_res->fetch_assoc()) {
        $student_id = (int)$req['student_id'];
        $request_id = (int)$req['request_id'];
        
        // Fetch priorities for this student
        $p_res = $conn->query("SELECT room_id, priority_order FROM room_preferences WHERE student_id = $student_id ORDER BY priority_order ASC");
        
        $assigned_room_id = null;
        $assigned_room_details = null;
        $matched_priority = null;

        while ($p = $p_res->fetch_assoc()) {
            $rid = (int)$p['room_id'];
            if (isset($rooms[$rid]) && $rooms[$rid]['available'] > 0) {
                // Match found!
                $assigned_room_id = $rid;
                $assigned_room_details = $rooms[$rid];
                $matched_priority = $p['priority_order'];
                
                // Decrement virtual availability to prevent double-booking in this batch
                $rooms[$rid]['available']--;
                break;
            }
        }

        if ($assigned_room_id) {
            $matched_count++;
            $results[] = [
                "request_id" => $request_id,
                "student_name" => $req['student_name'],
                "student_reg_no" => $req['student_reg_no'],
                "status" => "matched",
                "room_id" => $assigned_room_id,
                "room_display" => "Room {$assigned_room_details['room_no']} ({$assigned_room_details['building_code']})",
                "priority_matched" => $matched_priority
            ];

            if ($action === 'confirm') {
                $room_id = $assigned_room_id;
                $sid = $student_id;

                // 1. Update Room Occupancy (Direct occupancy increment)
                $conn->query("UPDATE hostel_rooms SET occupied_rooms = occupied_rooms + 1 WHERE id = $room_id");

                // 2. Fetch room details
                $room_code = $assigned_room_details['room_no'];
                $h_name = $assigned_room_details['building_code']; // The block/hostel

                // 3. Update Profile & Users Table
                $check_in_date = $now->format('Y-m-d');
                $renewal_date = (clone $now)->modify('+365 days')->format('Y-m-d');

                $u_stmt = $conn->prepare("SELECT username, full_name, email, phone_number FROM users WHERE id = ?");
                $u_stmt->bind_param("i", $sid);
                $u_stmt->execute();
                $u_row = $u_stmt->get_result()->fetch_assoc();
                
                $reg_no = $u_row['username'] ?? '';
                $f_name = $u_row['full_name'] ?? '';
                $u_email = $u_row['email'] ?? '';
                $u_phone = $u_row['phone_number'] ?? '';

                if (!empty($reg_no)) {
                    $p_check = $conn->prepare("SELECT id FROM profile WHERE reg_no = ?");
                    $p_check->bind_param("s", $reg_no);
                    $p_check->execute();
                    $p_exists = $p_check->get_result()->fetch_assoc();

                    if (!$p_exists) {
                        $p_ins = $conn->prepare("INSERT INTO profile (reg_no, full_name, email, personal_phone, institution) VALUES (?, ?, ?, ?, 'Saveetha Institute of Medical and Technical Sciences')");
                        $p_ins->bind_param("ssss", $reg_no, $f_name, $u_email, $u_phone);
                        $p_ins->execute();
                    }
                }

                $up_profile = $conn->prepare("
                    UPDATE profile p 
                    JOIN users u ON p.reg_no = u.username 
                    SET p.current_room_id = ?, p.room_allocation = ?, p.hostel_name = ?, p.check_in_date = ?, p.renewal_date = ?, p.valid_from = ?, p.valid_to = ? 
                    WHERE u.id = ?");
                $up_profile->bind_param("issssssi", $room_id, $room_code, $h_name, $check_in_date, $renewal_date, $check_in_date, $renewal_date, $sid);
                $up_profile->execute();

                // 4. Insert Payment Record
                $amount = 68000.00;
                $receipt_number = "RCP-" . time() . "-" . rand(1000, 9999);
                $description = "Room Allocation Fee - Room ID " . $room_id;
                
                $gateway_response = json_encode(['gateway' => 'AutoAllocation', 'status' => 'SUCCESS', 'method' => 'System']);
                $ip_address = getClientIp();
                $ins_pay = $conn->prepare("INSERT INTO payments (student_id, amount, receipt_number, status, description, paid_at, student_name, reg_number, gateway_response, user_id, ip_address) VALUES (?, ?, ?, 'paid', ?, ?, ?, ?, ?, ?, ?)");
                $ins_pay->bind_param("idsssssssis", $sid, $amount, $receipt_number, $description, $now_str, $f_name, $reg_no, $gateway_response, $sid, $ip_address);
                $ins_pay->execute();

                // 5. Update room_allocations status to 'approved' and paid_at
                $up_alloc = $conn->prepare("UPDATE room_allocations SET allocation_status = 'approved', allocated_room_id = ?, payment_deadline = NULL, approved_by = ?, approved_at = ?, paid_at = ? WHERE id = ?");
                $up_alloc->bind_param("iisssi", $room_id, $warden_id, $now_str, $now_str, $now_str, $request_id);
                $up_alloc->execute();

                // 6. Cancel Sibling Preferences
                $conn->query("UPDATE room_preferences SET status = 'cancelled' WHERE student_id = $sid AND status = 'submitted'");

                // Audit Logging for Warden Approving Request & Room Allocation
                try {
                    $w_stmt = $conn->prepare("SELECT username FROM users WHERE id = ?");
                    $w_stmt->bind_param("i", $warden_id);
                    $w_stmt->execute();
                    $warden_row = $w_stmt->get_result()->fetch_assoc();
                    $warden_username = $warden_row['username'] ?? 'warden1';

                    $hostel_val = $assigned_room_details['building_code'] ?? $assigned_room_details['hostel_name'] ?? 'Vaigai Hostel';
                    $room_type_val = $assigned_room_details['room_type'] ?? '4 IN 1 AC';
                    $floor_val = $assigned_room_details['floor'] ?? '';
                    $room_no_val = $assigned_room_details['room_no'] ?? '';
                    $student_reg = $req['student_reg_no'];

                    logAudit(
                        $warden_id,
                        $warden_username,
                        'warden',
                        'APPROVE_ALLOCATION_REQUEST',
                        'Room Allocation',
                        null,
                        [
                            'student_reg_no' => $student_reg,
                            'hostel' => $hostel_val,
                            'room_type' => $room_type_val,
                            'approved_by' => $warden_username,
                            'approval_time' => $now_str
                        ]
                    );

                    logAudit(
                        $warden_id,
                        $warden_username,
                        'warden',
                        'ROOM_ALLOCATED',
                        'Room Allocation',
                        null,
                        [
                            'student_reg_no' => $student_reg,
                            'hostel' => $hostel_val,
                            'floor' => $floor_val,
                            'room_no' => $room_no_val,
                            'bed_no' => 'B1',
                            'allocated_by' => $warden_username,
                            'allocated_at' => $now_str
                        ]
                    );
                } catch (Exception $e) {
                    error_log("Failed to log auto_allocate approvals: " . $e->getMessage());
                }
            }

        } else {
            $rejected_count++;
            $results[] = [
                "request_id" => $request_id,
                "student_name" => $req['student_name'],
                "student_reg_no" => $req['student_reg_no'],
                "status" => "rejected",
                "room_id" => null,
                "room_display" => "No rooms available in priorities",
                "priority_matched" => null
            ];
        }
    }

    if ($action === 'confirm') {
        $conn->commit();
        echo json_encode([
            "success" => true, 
            "message" => "Successfully allocated $matched_count students. $rejected_count skipped due to capacity.",
            "matched" => $matched_count,
            "rejected" => $rejected_count
        ]);
    } else {
        echo json_encode([
            "success" => true, 
            "preview" => $results,
            "summary" => [
                "total" => count($results),
                "matched" => $matched_count,
                "rejected" => $rejected_count
            ]
        ]);
    }

} catch (Exception $e) {
    if ($action === 'confirm' && isset($conn)) {
        $conn->rollback();
    }
    echo json_encode(["success" => false, "message" => "Server Error: " . $e->getMessage()]);
}
?>
