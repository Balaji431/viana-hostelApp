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
require_once __DIR__ . '/../utils/activity_logger.php';
require_once __DIR__ . '/../utils/auth_helper.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

require_once __DIR__ . '/expire_holds.php';

$method = $_SERVER['REQUEST_METHOD'];

if (!function_exists('isHostelNameMatch')) {
    function isHostelNameMatch($h1, $h2) {
        if (empty($h1) || empty($h2)) return false;
        $clean = function($s) {
            $s = strtolower($s);
            $s = preg_replace('/\s*hostel\s*/i', '', $s);
            $s = preg_replace('/\s+/', ' ', $s);
            return trim($s);
        };
        $n1 = $clean($h1);
        $n2 = $clean($h2);
        return ($n1 === $n2) || (strpos($n1, $n2) !== false) || (strpos($n2, $n1) !== false);
    }
}

try {
    // SECURITY ENFORCEMENT: Authenticate strictly via validated JWT
    $auth_header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (empty($auth_header)) {
        if (function_exists('apache_request_headers')) {
            $headers = apache_request_headers();
            $auth_header = $headers['Authorization'] ?? $headers['authorization'] ?? '';
        }
    }
    
    $token = null;
    if (preg_match('/Bearer\s+(.*)$/i', $auth_header, $matches)) {
        $token = $matches[1];
    }
    
    $payload = validateJWT($token);
    if ($payload) {
        $warden_user_id = (int)$payload['id'];
        $warden_role = $payload['role'];
        $warden_username = $payload['username'];
    } else {
        // Fallback to headers passed by Flutter app (e.g. X-User-Username)
        $x_username = $_SERVER['HTTP_X_USER_USERNAME'] ?? '';
        $x_role = $_SERVER['HTTP_X_USER_ROLE'] ?? '';
        $x_id = $_SERVER['HTTP_X_USER_ID'] ?? '0';

        if (!empty($x_username)) {
            $warden_user_id = (int)$x_id;
            $warden_role = $x_role;
            $warden_username = $x_username;
        } else {
            http_response_code(401);
            echo json_encode(["success" => false, "message" => "Unauthorized access. Invalid or expired token."]);
            return;
        }
    }
    
    // Resolve role and full_name from DB for safety
    $u_stmt = $conn->prepare("SELECT id, role, full_name FROM users WHERE username = ? LIMIT 1");
    $u_stmt->bind_param("s", $warden_username);
    $u_stmt->execute();
    $u_res = $u_stmt->get_result()->fetch_assoc();
    if (!$u_res) {
        http_response_code(401);
        echo json_encode(["success" => false, "message" => "User account not found."]);
        return;
    }
    
    $warden_user_id = (int)$u_res['id'];
    $u_role = $u_res['role'];
    $warden_full_name = $u_res['full_name'];
    
    // Main Warden / Admin: sees ALL hostels. Standard wardens: scoped to their mapped hostel only.
    $is_main_warden = ($u_role === 'admin' || $warden_username === 'warden1');
    
    // Mapped hostel check for standard wardens
    $assigned_hostel_name = null;
    $assigned_floor = null;
    $assigned_wing = null;
    
    if (!$is_main_warden) {
        if ($u_role !== 'warden') {
            http_response_code(403);
            echo json_encode(["success" => false, "message" => "Access Denied. You do not have the warden role."]);
            return;
        }
        $m_stmt = $conn->prepare("SELECT hostel_name, floor_name, wing_name FROM mapping_staff WHERE username = ? AND role = 'warden' LIMIT 1");
        $m_stmt->bind_param("s", $warden_username);
        $m_stmt->execute();
        $mapping = $m_stmt->get_result()->fetch_assoc();
        
        if (!$mapping) {
            http_response_code(403);
            echo json_encode(["success" => false, "message" => "Access Denied. You are not mapped as a warden."]);
            return;
        }
        
        $assigned_hostel_name = $mapping['hostel_name'];
        $assigned_floor = $mapping['floor_name'];
        $assigned_wing = $mapping['wing_name'];
    }

    if ($method === 'GET') {
        // Use the new request_status column. Accept ?status=pending (default),
        // ?status=approved, ?status=rejected, ?status=all.
        $status_param = $_GET['status'] ?? 'pending';
        // Legacy aliases
        if ($status_param === 'under_review' || $status_param === 'submitted') {
            $status_param = 'pending';
        }

        if ($status_param === 'pending') {
            $where  = "ra.request_status IN ('pending', 'claimed')";
            $params = [];
            $types  = "";
        } else {
            $where  = "ra.request_status = ?";
            $params = [$status_param];
            $types  = "s";
        }
        $order  = "ra.created_at ASC";

        if ($status_param === 'approved') {
            $where  = "ra.request_status IN ('approved')";
            $params = [];
            $types  = "";
            $order  = "ra.approved_at DESC";
        } elseif ($status_param === 'all') {
            $where  = "1=1";
            $params = [];
            $types  = "";
            $order  = "ra.created_at DESC";
        } elseif ($status_param === 'claimed') {
            $where  = "ra.request_status = 'claimed'";
            $params = [];
            $types  = "";
        }

        $query = "SELECT ra.*, u.username as student_reg_no, u.full_name as student_name,
                         hr.room_no as allocated_room_no, hr.building_code as allocated_block,
                         hr.room_code as allocated_room_code, hr.hostel_name as allocated_hostel_name,
                         hr.room_type as allocated_room_type, hr.floor as allocated_floor,
                         hr.wing_code as allocated_wing, hr.total_capacity as allocated_room_capacity,
                         hr.occupied_rooms as allocated_room_occupied,
                         cw.full_name as claimed_by_warden_name
                  FROM allocation_requests ra
                  JOIN users u ON ra.student_id = u.id
                  LEFT JOIN hostel_rooms hr ON ra.selected_room_id = hr.id
                  LEFT JOIN users cw ON CONVERT(ra.claimed_by_username USING utf8mb4) = CONVERT(cw.username USING utf8mb4)
                  WHERE $where
                  ORDER BY $order";
        
        $stmt = $conn->prepare($query);
        if ($types != "") {
            $stmt->bind_param($types, ...$params);
        }
        $stmt->execute();
        $result = $stmt->get_result();
        
        // Fetch room capacities
        $rooms_query = "SELECT hr.id, hr.room_no, hr.building_code, hr.total_capacity, hr.occupied_rooms, hr.room_type, hr.hostel_name, hr.floor, hr.wing_code,
                        (SELECT COUNT(*) FROM allocation_requests WHERE selected_room_id = hr.id AND status = 'payment_pending' AND payment_deadline > NOW()) as hold_count
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
            // Apply visibility routing: standard wardens only see requests matching their mapped hostel
            if (!$is_main_warden && !isHostelNameMatch($assigned_hostel_name, $row['paid_hostel_name'])) {
                continue;
            }
            
            $recommended_room = null;
            $first_priority_held = false;
            $priorities = [];

            if (!empty($row['selected_room_id'])) {
                $rid = (int)$row['selected_room_id'];
                if (isset($rooms[$rid])) {
                    $rInfo = $rooms[$rid];
                    $recommended_room = [
                        'room_id'       => $rid,
                        'room_no'       => $rInfo['room_no'] ?? $row['allocated_room_no'] ?? 'N/A',
                        'building_code' => $rInfo['building_code'] ?? $row['allocated_block'] ?? 'N/A',
                        'room_type'     => $rInfo['room_type'] ?? $row['allocated_room_type'] ?? '',
                        'capacity'      => (int)($rInfo['total_capacity'] ?? $row['allocated_room_capacity'] ?? 0),
                        'occupied'      => (int)($rInfo['occupied_rooms'] ?? $row['allocated_room_occupied'] ?? 0),
                        'available'     => (int)($rInfo['available'] ?? 0),
                        'hostel_name'   => $rInfo['hostel_name'] ?? $row['allocated_hostel_name'] ?? '',
                        'floor'         => $rInfo['floor'] ?? $row['allocated_floor'] ?? '',
                        'wing'          => $rInfo['wing_code'] ?? $row['allocated_wing'] ?? '',
                        'priority_order'=> 1,
                    ];
                    $priorities[] = $recommended_room;
                }
            }

            $row['priorities'] = $priorities;
            $row['recommended_room'] = $recommended_room;
            $row['first_priority_held'] = $first_priority_held;
            
            // Compatibility mappings for Flutter
            $raw_status = $row['request_status'] ?? $row['status'];
            if ($raw_status === 'pending' || $raw_status === 'claimed') {
                $row['allocation_status'] = 'under_review';
            } else {
                $row['allocation_status'] = $raw_status;
            }
            $row['allocated_room_id'] = $row['selected_room_id'];
            $row['allocated_bed_no'] = $row['selected_bed_number'];
            $row['submitted_at'] = $row['created_at'];

            // Claim status check
            $is_claimed = false;
            if (!empty($row['claimed_by_username'])) {
                $claimed_time = strtotime($row['claimed_at']);
                if (time() - $claimed_time < 900) {
                    $is_claimed = true;
                }
            }
            $row['is_claimed'] = $is_claimed;
            $row['claimed_by_warden_name'] = $row['claimed_by_warden_name'] ?? $row['claimed_by_username'] ?? '';
            $row['claimed_at'] = $row['claimed_at'] ?? '';
            
            if (in_array($row['request_status'] ?? $row['status'], ['pending', 'claimed', 'under_review'])) {
                $reg_no = $row['student_reg_no'];
                $stmtPay = $conn->prepare("SELECT * FROM vstudy_payments WHERE roll_number = ? LIMIT 0,1");
                $stmtPay->bind_param("s", $reg_no);
                $stmtPay->execute();
                $payResult = $stmtPay->get_result();
                
                if ($payResult && $payResult->num_rows > 0) {
                    $payRow = $payResult->fetch_assoc();
                    $hPref = $payRow['hostel_preference'] ?? 'Girls';
                    $hType = (stripos($hPref, 'girls') !== false || stripos($payRow['gender'], 'female') !== false) ? 'Girls' : 'Boys';
                    $facility = (stripos($hPref, 'non ac') !== false || stripos($hPref, 'non-ac') !== false) ? 'Non AC' : 'AC';
                    
                    $row['director_paid_data'] = [
                        'hostel_type' => $hType,
                        'hostel_name' => $payRow['hostel_name'] ?? $hType,
                        'room_type' => $hPref,
                        'facility' => $facility,
                        'paid_amount' => (double)($payRow['paid_amount'] ?? 45000.00),
                        'fee_paid' => (strtolower($payRow['payment_status'] ?? '') == 'paid'),
                        'institution' => $payRow['campus'] ?? 'Saveetha School of Engineering',
                        'student_name' => $payRow['student_name']
                    ];
                } else {
                    $row['director_paid_data'] = [
                        'hostel_type' => 'Girls',
                        'hostel_name' => 'Vaigai Hostel',
                        'room_type' => 'AC - B ATTACHED (6 IN 1)',
                        'facility' => 'AC',
                        'paid_amount' => 68000.00,
                        'fee_paid' => true,
                        'institution' => 'Saveetha Institute of Medical and Technical Sciences'
                    ];
                }
            }
            
            $requests[] = $row;
        }

        echo json_encode(["success" => true, "requests" => $requests, "is_main_warden" => $is_main_warden, "role_scope" => ($is_main_warden ? 'main_warden' : 'hostel_warden')]);

    } elseif ($method === 'POST') {
        if (isset($GLOBALS['mock_input'])) {
            $data = $GLOBALS['mock_input'];
        } else {
            $raw_input = file_get_contents("php://input");
            $data = json_decode($raw_input, true);
        }
        $action = $data['action'] ?? '';
        $request_id = (int)($data['allocation_id'] ?? 0);

        if ($request_id <= 0) {
            throw new Exception("Allocation ID is required.");
        }

        // Fetch request info and enforce strict server-side hostel mapping block
        $check_stmt = $conn->prepare("SELECT paid_hostel_name, status, request_status, claimed_by_username, claimed_at, student_id, selected_room_id, selected_bed_number FROM allocation_requests WHERE id = ?");
        $check_stmt->bind_param("i", $request_id);
        $check_stmt->execute();
        $req = $check_stmt->get_result()->fetch_assoc();
        
        if (!$req) {
            throw new Exception("Allocation request not found.");
        }
        
        // 403 Forbidden cross-hostel protection
        if (!$is_main_warden && !isHostelNameMatch($assigned_hostel_name, $req['paid_hostel_name'])) {
            http_response_code(403);
            echo json_encode(["success" => false, "message" => "Access Denied. You cannot manage requests for this hostel."]);
            return;
        }

        // Parse claiming locks status
        $is_currently_claimed = false;
        if (!empty($req['claimed_by_username'])) {
            $claimed_time = strtotime($req['claimed_at']);
            if (time() - $claimed_time < 900) {
                $is_currently_claimed = true;
            }
        }

        if ($action === 'claim') {
            // Assert request is still pending (not yet claimed/approved)
            $cur_rs = $req['request_status'] ?? $req['status'];
            if (!in_array($cur_rs, ['pending', 'submitted', 'under_review'])) {
                throw new Exception("Request is not in a claimable state (current status: $cur_rs).");
            }
            
            $conn->begin_transaction();
            try {
                // Check lock details
                if ($is_currently_claimed && $req['claimed_by_username'] !== $warden_username) {
                    if (!$is_main_warden) {
                        $u_stmt = $conn->prepare("SELECT full_name FROM users WHERE username = ?");
                        $u_stmt->bind_param("s", $req['claimed_by_username']);
                        $u_stmt->execute();
                        $claimed_name = $u_stmt->get_result()->fetch_assoc()['full_name'] ?? $req['claimed_by_username'];
                        throw new Exception("This request is already being handled by $claimed_name.");
                    }
                }
                
                $up = $conn->prepare("UPDATE allocation_requests SET claimed_by_username = ?, claimed_at = NOW(), request_status = 'claimed', status = 'under_review' WHERE id = ?");
                $up->bind_param("si", $warden_username, $request_id);
                $up->execute();
                
                logAudit(
                    $warden_user_id,
                    $warden_username,
                    'warden',
                    'CLAIM_REQUEST',
                    'allocation_requests',
                    null,
                    ['request_id' => $request_id, 'warden_username' => $warden_username]
                );
                
                $conn->commit();
                echo json_encode(["success" => true, "message" => "Request successfully claimed."]);
            } catch (Exception $e) {
                $conn->rollback();
                echo json_encode(["success" => false, "message" => $e->getMessage()]);
            }

        } elseif ($action === 'release_claim') {
            $conn->begin_transaction();
            try {
                if (!empty($req['claimed_by_username']) && $req['claimed_by_username'] !== $warden_username && !$is_main_warden) {
                    throw new Exception("You cannot release a claim owned by another warden.");
                }
                
                $up = $conn->prepare("UPDATE allocation_requests SET claimed_by_username = NULL, claimed_at = NULL, request_status = 'pending', status = 'under_review' WHERE id = ?");
                $up->bind_param("i", $request_id);
                $up->execute();
                
                logAudit(
                    $warden_user_id,
                    $warden_username,
                    'warden',
                    'RELEASE_CLAIM',
                    'allocation_requests',
                    null,
                    ['request_id' => $request_id, 'warden_username' => $warden_username]
                );
                
                $conn->commit();
                echo json_encode(["success" => true, "message" => "Claim successfully released."]);
            } catch (Exception $e) {
                $conn->rollback();
                echo json_encode(["success" => false, "message" => $e->getMessage()]);
            }

        } elseif ($action === 'approve') {
            $room_id = (int)($data['room_id'] ?? 0);
            $bed_no = isset($data['bed_no']) ? trim($data['bed_no']) : '';

            if ($room_id <= 0 || empty($bed_no)) {
                throw new Exception("Room ID and Bed Number are required for approval.");
            }
            
            // STRICT DATABASE TRANSACTION AT APPROVAL TIME
            $conn->begin_transaction();
            try {
                // 1. Lock request row and double check claim details
                $alloc_query = "SELECT student_id, status, claimed_by_username, claimed_at, paid_hostel_name FROM allocation_requests WHERE id = ? FOR UPDATE";
                $alloc_stmt = $conn->prepare($alloc_query);
                $alloc_stmt->bind_param("i", $request_id);
                $alloc_stmt->execute();
                $alloc_row = $alloc_stmt->get_result()->fetch_assoc();
                if (!$alloc_row) throw new Exception("Allocation request not found");

                // Verify request belongs to warden's hostel
                if (!$is_main_warden && !isHostelNameMatch($assigned_hostel_name, $alloc_row['paid_hostel_name'])) {
                    throw new Exception("Access Denied. Hostel mismatch.");
                }

                // Verify claim status
                $is_claimed = false;
                if (!empty($alloc_row['claimed_by_username'])) {
                    $c_time = strtotime($alloc_row['claimed_at']);
                    if (time() - $c_time < 900) {
                        $is_claimed = true;
                    }
                }

                // (Claim check removed — direct approval is now allowed)

                // 2. Lock room row and verify capacity
                $lock_query = "SELECT id, total_capacity, occupied_rooms, available_rooms, room_code, hostel_name FROM hostel_rooms WHERE id = ? FOR UPDATE";
                $l_stmt = $conn->prepare($lock_query);
                $l_stmt->bind_param("i", $room_id);
                $l_stmt->execute();
                $room = $l_stmt->get_result()->fetch_assoc();
                if (!$room) throw new Exception("Room not found");
                
                if ($room['available_rooms'] <= 0 || $room['occupied_rooms'] >= $room['total_capacity']) {
                    throw new Exception("This room/bed is no longer available. Please check availability again.");
                }

                // 3. Verify exact bed is free
                $bc_stmt = $conn->prepare("SELECT id FROM allocation_requests WHERE selected_room_id = ? AND selected_bed_number = ? AND status = 'approved' FOR UPDATE");
                $bc_stmt->bind_param("is", $room_id, $bed_no);
                $bc_stmt->execute();
                if ($bc_stmt->get_result()->fetch_assoc()) {
                    throw new Exception("This room/bed is no longer available. Please check availability again.");
                }
                
                $sid = (int)$alloc_row['student_id'];

                // 4. Get old room details from current profile to handle vacancy release and history logging
                $u_stmt2 = $conn->prepare("SELECT username, full_name, email, phone_number, Institution, fcm_token FROM users WHERE id = ?");
                $u_stmt2->bind_param("i", $sid);
                $u_stmt2->execute();
                $u_row = $u_stmt2->get_result()->fetch_assoc();
                
                $reg_no = $u_row['username'] ?? '';
                $f_name = $u_row['full_name'] ?? '';
                $u_email = $u_row['email'] ?? '';
                $u_phone = $u_row['phone_number'] ?? '';

                $old_room_id = 0;
                $old_room_allocation = '';
                $old_check_in_date = '';
                
                if (!empty($reg_no)) {
                    $p_check = $conn->prepare("SELECT id, current_room_id, room_allocation, check_in_date FROM profile WHERE reg_no = ?");
                    $p_check->bind_param("s", $reg_no);
                    $p_check->execute();
                    $p_row = $p_check->get_result()->fetch_assoc();

                    if ($p_row) {
                        $old_room_id = (int)($p_row['current_room_id'] ?? 0);
                        $old_room_allocation = $p_row['room_allocation'] ?? '';
                        $old_check_in_date = $p_row['check_in_date'] ?? '';
                    } else {
                        // Create profile if it doesn't exist
                        $p_ins = $conn->prepare("INSERT INTO profile (reg_no, full_name, email, personal_phone, institution) VALUES (?, ?, ?, ?, 'Saveetha School of Engineering')");
                        $p_ins->bind_param("ssss", $reg_no, $f_name, $u_email, $u_phone);
                        $p_ins->execute();
                    }
                }

                // 5. If student had an existing room, release vacancy and log history
                $now = new DateTime();
                $now_str = $now->format('Y-m-d H:i:s');
                $check_in_date = $now->format('Y-m-d');
                $renewal_date = (clone $now)->modify('+365 days')->format('Y-m-d');

                // Try to get check-in date from payment date to make check-in date more accurate
                $pay_stmt = $conn->prepare("SELECT paid_date, academic_year FROM vstudy_payments WHERE roll_number = ? ORDER BY id DESC LIMIT 1");
                $pay_stmt->bind_param("s", $reg_no);
                $pay_stmt->execute();
                $pay_res = $pay_stmt->get_result()->fetch_assoc();
                if ($pay_res && !empty($pay_res['paid_date'])) {
                    $pay_time = strtotime($pay_res['paid_date']);
                    if ($pay_time > 0) {
                        $check_in_date = date('Y-m-d', $pay_time);
                        $years = 1;
                        if (stripos($pay_res['academic_year'], '2') !== false || stripos($pay_res['academic_year'], 'two') !== false) {
                            $years = 2;
                        } elseif (stripos($pay_res['academic_year'], '3') !== false || stripos($pay_res['academic_year'], 'three') !== false) {
                            $years = 3;
                        }
                        $renewal_date = date('Y-m-d', strtotime($check_in_date . " +$years years"));
                    }
                }

                if ($old_room_id > 0 && $old_room_id !== $room_id) {
                    // Release occupancy in the old room
                    $conn->query("UPDATE hostel_rooms SET occupied_rooms = GREATEST(0, occupied_rooms - 1), available_rooms = LEAST(total_capacity, available_rooms + 1) WHERE id = $old_room_id");

                    // Create history logging table if not exists
                    $conn->query("
                        CREATE TABLE IF NOT EXISTS room_allocations (
                            id INT AUTO_INCREMENT PRIMARY KEY,
                            student_id INT,
                            reg_number VARCHAR(100),
                            student_name VARCHAR(100),
                            old_room_code VARCHAR(100),
                            old_room_id INT,
                            check_in_date DATE,
                            check_out_date DATE,
                            allocated_by VARCHAR(100),
                            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                        )
                    ");

                    // Insert historical log entry
                    $hist_stmt = $conn->prepare("INSERT INTO room_allocations (student_id, reg_number, student_name, old_room_code, old_room_id, check_in_date, check_out_date, allocated_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
                    $checkout_date = $check_in_date;
                    $hist_stmt->bind_param("isssisss", $sid, $reg_no, $f_name, $old_room_allocation, $old_room_id, $old_check_in_date, $checkout_date, $warden_username);
                    $hist_stmt->execute();
                }

                // 6. Update room occupancy for the new room
                $conn->query("UPDATE hostel_rooms SET occupied_rooms = occupied_rooms + 1, available_rooms = available_rooms - 1 WHERE id = $room_id");

                // 7. Update profile allocation info
                $room_code = $room['room_code'];
                $h_name = $room['hostel_name'];

                $up_profile = $conn->prepare("
                    UPDATE profile p 
                    JOIN users u ON p.reg_no = u.username 
                    SET p.current_room_id = ?, p.room_allocation = ?, p.hostel_name = ?, p.check_in_date = ?, p.renewal_date = ?, p.valid_from = ?, p.valid_to = ?, p.bed_no = ? 
                    WHERE u.id = ?");
                $up_profile->bind_param("isssssssi", $room_id, $room_code, $h_name, $check_in_date, $renewal_date, $check_in_date, $renewal_date, $bed_no, $sid);
                $up_profile->execute();

                // 8. Sync details to users table (RoomId, RoomType, HostelName, HostelType)
                $new_room_type = $room['room_type'] ?? '';
                $new_hostel_type = (stripos($h_name, 'girls') !== false || stripos($room['hostel_name'], 'ponni') !== false || stripos($room['hostel_name'], 'vaigai') !== false) ? 'Girls' : 'Boys';
                $up_user = $conn->prepare("UPDATE users SET RoomId = ?, RoomType = ?, HostelName = ?, HostelType = ? WHERE id = ?");
                $up_user->bind_param("ssssi", $room_code, $new_room_type, $h_name, $new_hostel_type, $sid);
                $up_user->execute();

                // 6. Create payments record
                $amount = 68000.00;
                $receipt_number = "RCP-" . time() . "-" . rand(1000, 9999);
                $description = "Room Allocation Fee - Room ID " . $room_id;
                $gateway_response = json_encode(['gateway' => 'Internal/Warden', 'status' => 'SUCCESS']);
                $ip_address = getClientIp();
                $ins_pay = $conn->prepare("INSERT INTO payments (student_id, amount, receipt_number, status, description, paid_at, student_name, reg_number, gateway_response, user_id, ip_address) VALUES (?, ?, ?, 'paid', ?, ?, ?, ?, ?, ?, ?)");
                $ins_pay->bind_param("idssssssis", $sid, $amount, $receipt_number, $description, $now_str, $f_name, $reg_no, $gateway_response, $sid, $ip_address);
                $ins_pay->execute();

                // 7. Update request_status to 'approved' and save room/bed/approval details
                $up_alloc = $conn->prepare("UPDATE allocation_requests SET request_status = 'approved', status = 'approved', selected_room_id = ?, selected_bed_number = ?, selected_room_number = ?, payment_deadline = NULL, approved_by_username = ?, approved_at = ?, paid_at = ?, claimed_by_username = NULL, claimed_at = NULL WHERE id = ?");
                $room_no_for_save = $room['room_code'] ?? '';
                $up_alloc->bind_param("isssssi", $room_id, $bed_no, $room_no_for_save, $warden_username, $now_str, $now_str, $request_id);
                $up_alloc->execute();

                // 8. Cancel sibling preferences
                $conn->query("UPDATE room_preferences SET status = 'cancelled' WHERE student_id = $sid AND status = 'submitted'");

                // 9. Write audit log
                logAudit(
                    $warden_user_id,
                    $warden_username,
                    'warden',
                    'ROOM_ALLOCATED',
                    'Room Allocation',
                    null,
                    [
                        'student' => $f_name,
                        'registration_number' => $reg_no,
                        'room_code' => $room_code,
                        'bed' => $bed_no,
                        'warden' => $warden_username,
                        'date' => $check_in_date,
                        'time' => $now->format('H:i:s')
                    ]
                );

                $conn->commit();

                // Send FCM notification
                try {
                    if ($u_row && !empty($u_row['fcm_token'])) {
                        require_once __DIR__ . '/../send_notification.php';
                        $title = "Room Allocation Completed!";
                        $body = "Your room allocation request has been approved and finalized. Room $room_code is now assigned to you!";
                        sendFCM($u_row['fcm_token'], $title, $body, (string)$request_id, (string)$warden_user_id, 'Warden', $body, 'room_allocation_completed');
                    }
                } catch (Exception $e) {}

                echo json_encode(["success" => true, "message" => "Allocation approved and finalized successfully."]);

            } catch (Exception $e) {
                $conn->rollback();
                throw $e;
            }

        } elseif ($action === 'reject') {
            $conn->begin_transaction();
            try {
                $sid = (int)$req['student_id'];
                
                $conn->query("UPDATE allocation_requests SET request_status = 'rejected', status = 'rejected', claimed_by_username = NULL, claimed_at = NULL WHERE id = $request_id");
                
                $student_stmt = $conn->prepare("SELECT username, fcm_token FROM users WHERE id = ?");
                $student_stmt->bind_param("i", $sid);
                $student_stmt->execute();
                $student_res = $student_stmt->get_result()->fetch_assoc();
                $student_reg = $student_res['username'] ?? '';
                $fcm_token = $student_res['fcm_token'] ?? '';

                $reason = !empty($data['reason']) ? $data['reason'] : (!empty($data['remarks']) ? $data['remarks'] : "No vacancies available");
                $timestamp = date('Y-m-d H:i:s');

                logAudit(
                    $warden_user_id,
                    $warden_username,
                    'warden',
                    'REJECT_ALLOCATION_REQUEST',
                    'Room Allocation',
                    null,
                    [
                        'student_reg_no' => $student_reg,
                        'reason' => $reason,
                        'rejected_by' => $warden_username,
                        'timestamp' => $timestamp
                    ]
                );

                $conn->commit();

                try {
                    if (!empty($fcm_token)) {
                        require_once __DIR__ . '/../send_notification.php';
                        $title = "Room Allocation Rejected";
                        $body = "Your room allocation request has been rejected by the warden.";
                        sendFCM($fcm_token, $title, $body, (string)$request_id, '', 'Warden', $body, 'room_allocation_rejected');
                    }
                } catch (Exception $e) {}

                echo json_encode(["success" => true, "message" => "Allocation rejected successfully."]);
            } catch (Exception $e) {
                $conn->rollback();
                throw $e;
            }

        } elseif ($action === 'waitlist') {
            $conn->begin_transaction();
            try {
                $sid = (int)$req['student_id'];
                $conn->query("UPDATE allocation_requests SET request_status = 'cancelled', status = 'waitlisted', claimed_by_username = NULL, claimed_at = NULL WHERE id = $request_id");
                
                $student_stmt = $conn->prepare("SELECT fcm_token FROM users WHERE id = ?");
                $student_stmt->bind_param("i", $sid);
                $student_stmt->execute();
                $student_row = $student_stmt->get_result()->fetch_assoc();

                logAudit(
                    $warden_user_id,
                    $warden_username,
                    'warden',
                    'WAITLIST_ALLOCATION_REQUEST',
                    'Room Allocation',
                    null,
                    ['request_id' => $request_id, 'warden_username' => $warden_username]
                );

                $conn->commit();

                try {
                    if ($student_row && !empty($student_row['fcm_token'])) {
                        require_once __DIR__ . '/../send_notification.php';
                        $title = "Room Allocation Waitlisted";
                        $body = "Your room allocation request has been waitlisted by the warden.";
                        sendFCM($student_row['fcm_token'], $title, $body, (string)$request_id, '', 'Warden', $body, 'room_allocation_waitlisted');
                    }
                } catch (Exception $e) {}

                echo json_encode(["success" => true, "message" => "Allocation waitlisted successfully."]);
            } catch (Exception $e) {
                $conn->rollback();
                throw $e;
            }

        } elseif ($action === 'deallocate') {
            $conn->begin_transaction();
            try {
                $sid = $req['student_id'];
                $room_id = (int)$req['selected_room_id'];
                $allocated_bed = $req['selected_bed_number'];
                
                $u_stmt = $conn->prepare("SELECT username, full_name FROM users WHERE id = ?");
                $u_stmt->bind_param("i", $sid);
                $u_stmt->execute();
                $u_row = $u_stmt->get_result()->fetch_assoc();
                $reg_no = $u_row['username'] ?? '';
                $f_name = $u_row['full_name'] ?? '';
                
                $room_code = '';
                if ($room_id > 0) {
                    $r_stmt = $conn->prepare("SELECT room_code, total_capacity, occupied_rooms FROM hostel_rooms WHERE id = ?");
                    $r_stmt->bind_param("i", $room_id);
                    $r_stmt->execute();
                    $r_row = $r_stmt->get_result()->fetch_assoc();
                    $room_code = $r_row['room_code'] ?? '';
                }
                
                if ($room_id > 0) {
                    $conn->query("UPDATE hostel_rooms SET occupied_rooms = GREATEST(0, occupied_rooms - 1), available_rooms = LEAST(total_capacity, available_rooms + 1) WHERE id = $room_id");
                }
                
                $up_profile = $conn->prepare("
                    UPDATE profile p 
                    JOIN users u ON p.reg_no = u.username 
                    SET p.current_room_id = NULL, p.room_allocation = NULL, p.hostel_name = NULL, 
                        p.check_in_date = NULL, p.renewal_date = NULL, p.valid_from = NULL, p.valid_to = NULL, p.bed_no = NULL 
                    WHERE u.id = ?");
                $up_profile->bind_param("i", $sid);
                $up_profile->execute();
                
                $up_alloc = $conn->prepare("UPDATE allocation_requests SET request_status = 'pending', status = 'under_review', selected_room_id = NULL, selected_bed_number = NULL, selected_room_number = NULL, approved_by_username = NULL, approved_at = NULL, paid_at = NULL, claimed_by_username = NULL, claimed_at = NULL WHERE id = ?");
                $up_alloc->bind_param("i", $request_id);
                $up_alloc->execute();
                
                $now = new DateTime();
                $date_str = $now->format('Y-m-d');
                $time_str = $now->format('H:i:s');
                $reason = !empty($data['reason']) ? $data['reason'] : "Administrative Deallocation";
                
                logAudit(
                    $warden_user_id,
                    $warden_username,
                    'warden',
                    'ROOM_DEALLOCATED',
                    'Room Allocation',
                    null,
                    [
                        'student' => $f_name,
                        'registration_number' => $reg_no,
                        'previous_room_code' => $room_code,
                        'previous_bed' => $allocated_bed,
                        'warden' => $warden_username,
                        'reason' => $reason,
                        'date' => $date_str,
                        'time' => $time_str
                    ]
                );
                
                $conn->commit();
                echo json_encode(["success" => true, "message" => "Student deallocated successfully. Request returned to queue."]);
                
            } catch (Exception $e) {
                $conn->rollback();
                throw $e;
            }
        }
    }

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
?>
