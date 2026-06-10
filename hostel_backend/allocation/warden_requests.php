<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

require_once __DIR__ . '/expire_holds.php';

try {
    $conn->query("ALTER TABLE room_allocations ADD COLUMN notified_of_conflict TINYINT(1) DEFAULT 0");
    $conn->query("ALTER TABLE room_allocations ADD COLUMN allocated_bed_no VARCHAR(20) DEFAULT NULL");
} catch (Exception $e) {}

$method = $_SERVER['REQUEST_METHOD'];

try {
    if ($method === 'GET') {
        $status = $_GET['status'] ?? 'submitted';
        
        $where = "ra.allocation_status = ?";
        $params = [$status];
        $types = "s";
        $order = "ra.submitted_at ASC";

        if ($status === 'approved') {
            $where = "ra.allocation_status IN ('payment_pending', 'approved')";
            $params = [];
            $types = "";
            $order = "ra.approved_at DESC";
        } elseif ($status === 'all') {
            $where = "1=1";
            $params = [];
            $types = "";
            $order = "ra.submitted_at DESC";
        }
        
        $query = "SELECT ra.*, u.username as student_reg_no, u.full_name as student_name,
                         hr.room_no as allocated_room_no, hr.building_code as allocated_block
                  FROM room_allocations ra
                  JOIN users u ON ra.student_id = u.id
                  LEFT JOIN hostel_rooms hr ON ra.allocated_room_id = hr.id
                  WHERE $where
                  ORDER BY $order";
        
        $stmt = $conn->prepare($query);
        if ($types != "") {
            $stmt->bind_param($types, ...$params);
        }
        $stmt->execute();
        $result = $stmt->get_result();
        
        // Fetch current live capacities of ALL rooms
        $rooms_query = "SELECT hr.id, hr.room_no, hr.building_code, hr.total_capacity, hr.occupied_rooms,
                        (SELECT COUNT(*) FROM room_allocations WHERE allocated_room_id = hr.id AND allocation_status = 'payment_pending' AND payment_deadline > NOW()) as hold_count
                        FROM hostel_rooms hr";
        $r_res = $conn->query($rooms_query);
        
        $rooms = [];
        if ($r_res) {
            while ($r = $r_res->fetch_assoc()) {
                $available = (int)$r['total_capacity'] - (int)$r['occupied_rooms'] - (int)$r['hold_count'];
                $r['available'] = max(0, $available);
                $rooms[(int)$r['id']] = $r;
            }
        }
        
        $requests = [];
        while ($row = $result->fetch_assoc()) {
            // Get student priorities
            $pid = $row['student_id'];
            $p_res = $conn->query("SELECT rp.*, hr.room_no, hr.building_code, hr.room_type, hr.total_capacity as capacity, hr.occupied_rooms as occupied
                                   FROM room_preferences rp
                                   JOIN hostel_rooms hr ON rp.room_id = hr.id
                                   WHERE rp.student_id = $pid
                                   ORDER BY rp.priority_order ASC");
            
            $priorities = [];
            $recommended_room = null;
            $first_priority_held = false;
            
            if ($p_res) {
                $is_first = true;
                while ($p_row = $p_res->fetch_assoc()) {
                    $rid = (int)$p_row['room_id'];
                    $p_row['capacity'] = (int)$p_row['capacity'];
                    $p_row['occupied'] = (int)$p_row['occupied'];
                    
                    $live_avail = isset($rooms[$rid]) ? $rooms[$rid]['available'] : 0;
                    $p_row['available'] = $live_avail;
                    
                    $priorities[] = $p_row;
                    
                    $is_physically_full = isset($rooms[$rid]) && ($rooms[$rid]['occupied_rooms'] >= $rooms[$rid]['total_capacity']);
                    $is_virtually_held = isset($rooms[$rid]) && ($rooms[$rid]['available'] == 0) && !$is_physically_full;
                    
                    if ($is_first) {
                        if ($is_virtually_held) {
                            $first_priority_held = true;
                        }
                        $is_first = false;
                    }
                    
                    if ($recommended_room === null) {
                        if ($live_avail > 0) {
                            if (!$first_priority_held || count($priorities) == 1) {
                                $recommended_room = $p_row;
                                $rooms[$rid]['available']--;
                            }
                        }
                    }
                }
            }
            
            
            $row['priorities'] = $priorities;
            $row['recommended_room'] = $recommended_room;
            $row['first_priority_held'] = $first_priority_held;
            
            if ($row['allocation_status'] === 'under_review') {
                $reg_no = $row['student_reg_no'];
                $mock_payments = [
                    '192425398' => [
                        'hostel_type' => 'Girls',
                        'room_type' => 'AC - B ATTACHED (6 IN 1)',
                        'facility' => 'AC',
                        'paid_amount' => 68000.00,
                        'fee_paid' => true,
                        'institution' => 'Saveetha School of Engineering'
                    ],
                    '192413034' => [
                        'hostel_type' => 'Girls',
                        'room_type' => 'AC - B ATTACHED (4 IN 1)',
                        'facility' => 'AC',
                        'paid_amount' => 80000.00,
                        'fee_paid' => true,
                        'institution' => 'Saveetha School of Engineering'
                    ],
                    '192315010' => [
                        'hostel_type' => 'Girls',
                        'room_type' => 'NON AC (6 IN 1)',
                        'facility' => 'Non AC',
                        'paid_amount' => 45000.00,
                        'fee_paid' => true,
                        'institution' => 'Saveetha School of Engineering'
                    ]
                ];
                $row['director_paid_data'] = $mock_payments[$reg_no] ?? [
                    'hostel_type' => 'Girls',
                    'room_type' => 'AC - B ATTACHED (6 IN 1)',
                    'facility' => 'AC',
                    'paid_amount' => 68000.00,
                    'fee_paid' => true,
                    'institution' => 'Saveetha Institute of Medical and Technical Sciences'
                ];
            }
            
            $requests[] = $row;
        }

        echo json_encode(["success" => true, "requests" => $requests]);

    } elseif ($method === 'POST') {
        if (!isset($data) || empty($data)) {
            $data = json_decode(file_get_contents('php://input'), true);
        }
        $action = $data['action'] ?? ''; // approve, reject, waitlist
        $request_id = (int)($data['allocation_id'] ?? 0);
        $warden_id = (int)($data['warden_id'] ?? 0);

        if ($action === 'approve') {
            $room_id = (int)$data['room_id'];
            
            $conn->begin_transaction();
            try {
                // Capacity Guard: SELECT ... FOR UPDATE
                $lock_query = "SELECT total_capacity, occupied_rooms, room_code, hostel_name FROM hostel_rooms WHERE id = ? FOR UPDATE";
                $l_stmt = $conn->prepare($lock_query);
                $l_stmt->bind_param("i", $room_id);
                $l_stmt->execute();
                $room = $l_stmt->get_result()->fetch_assoc();
                
                if (!$room) throw new Exception("Room not found");
                
                if ($room['occupied_rooms'] >= $room['total_capacity']) {
                    throw new Exception("Room is already full.");
                }

                // Get student_id and request details
                $alloc_query = "SELECT student_id, allocation_status, allocated_room_id, allocated_bed_no FROM room_allocations WHERE id = $request_id";
                $alloc_res = $conn->query($alloc_query);
                if (!$alloc_res || $alloc_res->num_rows === 0) throw new Exception("Allocation request not found");
                $alloc_row = $alloc_res->fetch_assoc();
                $sid = $alloc_row['student_id'];
                $current_alloc_status = $alloc_row['allocation_status'];
                $suggested_room_id = (int)$alloc_row['allocated_room_id'];
                $allocated_bed = $alloc_row['allocated_bed_no'] ?? 'B1';

                // Recalculate bed if modified by warden
                if ($current_alloc_status === 'under_review' && $room_id !== $suggested_room_id) {
                    $occupied_beds = [];
                    $b_stmt = $conn->prepare("SELECT bed_no FROM profile WHERE room_allocation = ? AND bed_no IS NOT NULL AND bed_no != ''");
                    $b_stmt->bind_param("s", $room['room_code']);
                    $b_stmt->execute();
                    $b_res = $b_stmt->get_result();
                    while ($b_row = $b_res->fetch_assoc()) {
                        $occupied_beds[] = strtoupper(trim($b_row['bed_no']));
                    }

                    $a_stmt = $conn->prepare("
                        SELECT allocated_bed_no 
                        FROM room_allocations 
                        WHERE allocated_room_id = ? 
                          AND allocation_status IN ('under_review', 'payment_pending', 'approved')
                          AND id != ?
                    ");
                    $a_stmt->bind_param("ii", $room_id, $request_id);
                    $a_stmt->execute();
                    $a_res = $a_stmt->get_result();
                    while ($a_row = $a_res->fetch_assoc()) {
                        if (!empty($a_row['allocated_bed_no'])) {
                            $occupied_beds[] = strtoupper(trim($a_row['allocated_bed_no']));
                        }
                    }

                    $allocated_bed = "B1";
                    for ($i = 1; $i <= (int)$room['total_capacity']; $i++) {
                        $candidate = "B" . $i;
                        if (!in_array($candidate, $occupied_beds)) {
                            $allocated_bed = $candidate;
                            break;
                        }
                    }
                }

                // 1. Update Room Occupancy (Direct occupancy increment)
                $conn->query("UPDATE hostel_rooms SET occupied_rooms = occupied_rooms + 1, blocked_by = NULL, blocked_until = NULL WHERE id = $room_id");

                // 2. Update Profile & Users Table
                $now = new DateTime();
                $now_str = $now->format('Y-m-d H:i:s');
                $check_in_date = $now->format('Y-m-d');
                $renewal_date = (clone $now)->modify('+365 days')->format('Y-m-d');
                
                $room_code = $room['room_code'];
                $h_name = $room['hostel_name'];

                $u_stmt = $conn->prepare("SELECT username, full_name, email, phone_number, Institution, fcm_token FROM users WHERE id = ?");
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
                    SET p.current_room_id = ?, p.room_allocation = ?, p.hostel_name = ?, p.check_in_date = ?, p.renewal_date = ?, p.valid_from = ?, p.valid_to = ?, p.bed_no = ? 
                    WHERE u.id = ?");
                $up_profile->bind_param("isssssssi", $room_id, $room_code, $h_name, $check_in_date, $renewal_date, $check_in_date, $renewal_date, $allocated_bed, $sid);
                $up_profile->execute();

                // 3. (Legacy new_room_booking table writes successfully removed)

                // 4. Insert Payment Record
                $amount = 68000.00; // Standard room allocation fee
                $receipt_number = "RCP-" . time() . "-" . rand(1000, 9999);
                $description = "Room Allocation Fee - Room ID " . $room_id;
                
                $ins_pay = $conn->prepare("INSERT INTO payments (student_id, amount, receipt_number, status, description, paid_at) VALUES (?, ?, ?, 'paid', ?, ?)");
                $ins_pay->bind_param("idsss", $sid, $amount, $receipt_number, $description, $now_str);
                $ins_pay->execute();

                // 5. Update room_allocations status to 'approved' and paid_at
                $up_alloc = $conn->prepare("UPDATE room_allocations SET allocation_status = 'approved', allocated_room_id = ?, allocated_bed_no = ?, payment_deadline = NULL, approved_by = ?, approved_at = ?, paid_at = ? WHERE id = ?");
                $up_alloc->bind_param("issssi", $room_id, $allocated_bed, $warden_id, $now_str, $now_str, $request_id);
                $up_alloc->execute();

                // 6. Cancel Sibling Preferences
                $conn->query("UPDATE room_preferences SET status = 'cancelled' WHERE student_id = $sid AND status = 'submitted'");

                $conn->commit();

                // Send push notification to student
                try {
                    if ($u_row && !empty($u_row['fcm_token'])) {
                        require_once '../send_notification.php';
                        $title = "Room Allocation Completed!";
                        $body = "Your room allocation request has been approved and finalized. Room $room_code is now assigned to you!";
                        sendFCM($u_row['fcm_token'], $title, $body, (string)$request_id, (string)$warden_id, 'Warden', $body, 'room_allocation_completed');
                    }
                } catch (Exception $e) {}

                echo json_encode(["success" => true, "message" => "Allocation approved and finalized successfully. Room allocated directly!"]);

            } catch (Exception $e) {
                $conn->rollback();
                throw $e;
            }

        } elseif ($action === 'reject') {
            // Get student ID to send rejection notification
            $sid_query = $conn->query("SELECT student_id FROM room_allocations WHERE id = $request_id");
            if ($sid_query && $sid_row = $sid_query->fetch_assoc()) {
                $sid = $sid_row['student_id'];
                $conn->query("UPDATE room_allocations SET allocation_status = 'rejected' WHERE id = $request_id");
                
                try {
                    $student_stmt = $conn->prepare("SELECT fcm_token FROM users WHERE id = ?");
                    $student_stmt->bind_param("i", $sid);
                    $student_stmt->execute();
                    $student_row = $student_stmt->get_result()->fetch_assoc();
                    
                    if ($student_row && !empty($student_row['fcm_token'])) {
                        require_once '../send_notification.php';
                        $title = "Room Allocation Rejected";
                        $body = "Your room allocation request has been rejected by the warden.";
                        sendFCM($student_row['fcm_token'], $title, $body, (string)$request_id, '', 'Warden', $body, 'room_allocation_rejected');
                    }
                } catch (Exception $e) {}
            }
            echo json_encode(["success" => true, "message" => "Allocation rejected"]);
        } elseif ($action === 'waitlist') {
            // Get student ID to send waitlisted notification
            $sid_query = $conn->query("SELECT student_id FROM room_allocations WHERE id = $request_id");
            if ($sid_query && $sid_row = $sid_query->fetch_assoc()) {
                $sid = $sid_row['student_id'];
                $conn->query("UPDATE room_allocations SET allocation_status = 'waitlisted' WHERE id = $request_id");
                
                try {
                    $student_stmt = $conn->prepare("SELECT fcm_token FROM users WHERE id = ?");
                    $student_stmt->bind_param("i", $sid);
                    $student_stmt->execute();
                    $student_row = $student_stmt->get_result()->fetch_assoc();
                    
                    if ($student_row && !empty($student_row['fcm_token'])) {
                        require_once '../send_notification.php';
                        $title = "Room Allocation Waitlisted";
                        $body = "Your room allocation request has been waitlisted by the warden.";
                        sendFCM($student_row['fcm_token'], $title, $body, (string)$request_id, '', 'Warden', $body, 'room_allocation_waitlisted');
                    }
                } catch (Exception $e) {}
            }
            echo json_encode(["success" => true, "message" => "Allocation waitlisted"]);
        } elseif ($action === 'release_room') {
            // Revert back to submitted (pending) state
            $conn->query("UPDATE room_allocations SET 
                            allocation_status = 'submitted', 
                            allocated_room_id = NULL, 
                            payment_deadline = NULL,
                            approved_by = NULL,
                            approved_at = NULL 
                          WHERE id = $request_id");
            echo json_encode(["success" => true, "message" => "Room released. Request is now pending again."]);
        } elseif ($action === 'notify_conflict') {
            $conn->query("UPDATE room_allocations SET notified_of_conflict = 1 WHERE id = $request_id");
            echo json_encode(["success" => true, "message" => "Student has been notified of the conflict successfully!"]);
        }
    }

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
?>
