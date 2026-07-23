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

/**
 * Helper to fetch exact fee from renew_fee table or hardcoded requirements
 */
function getFeeForRoomType($conn, $room_type_name, $request_id = null) {
    if (empty($room_type_name)) {
        if ($request_id) {
            // Try to find the actual room type from the requested room
            $res = $conn->query("SELECT hr.room_type FROM hostel_rooms hr JOIN room_change_requests rcr ON hr.room_code = rcr.requested_room WHERE rcr.request_id = '$request_id'");
            if ($res && $row = $res->fetch_assoc()) {
                $room_type_name = $row['room_type'];
            }
        }
    }
    
    $normalized = strtoupper(trim($room_type_name ?? ''));
    
    // Robust check for 6 IN 1 AC rooms
    if ($normalized === 'AC - B ATTACHED (6 IN 1)' || 
        $normalized === 'AC - B ATTACHED' || 
        (strpos($normalized, '6 IN 1') !== false && strpos($normalized, 'AC') !== false)) {
        return 65000.00;
    }

    // Robust check for 4 IN 1 AC rooms
    if ($normalized === 'AC - B ATTACHED (4 IN 1)' || 
        (strpos($normalized, '4 IN 1') !== false && strpos($normalized, 'AC') !== false)) {
        return 75000.00;
    }
    
    if (empty($normalized) || $normalized === 'AC' || $normalized === 'NON AC' || $normalized === 'STANDARD') {
        if ($request_id) {
             $res = $conn->query("SELECT hr.room_type FROM hostel_rooms hr JOIN room_change_requests rcr ON hr.room_code = rcr.requested_room WHERE rcr.request_id = '$request_id'");
             if ($res && $row = $res->fetch_assoc()) {
                 return getFeeForRoomType($conn, $row['room_type']);
             }
        }
    }
    
    // Look up in hostel_renew_fee table for other types
    $query = "SELECT hostel_fee, monthly_amount FROM hostel_renew_fee WHERE UPPER(TRIM(room_type)) = ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("s", $normalized);
    $stmt->execute();
    $res = $stmt->get_result()->fetch_assoc();
    
    if ($res) {
        if (floatval($res['hostel_fee']) > 0) return (float)$res['hostel_fee'];
        if (floatval($res['monthly_amount']) > 0) return (float)$res['monthly_amount'] * 12;
    }
    
    return 0;
}

try {
    $json_input = file_get_contents('php://input');
    $data = json_decode($json_input, true);
    
    if (!$data) throw new Exception('Invalid JSON data');
    
    $required_fields = ['request_id', 'status', 'warden_id'];
    foreach ($required_fields as $field) {
        if (!isset($data[$field]) || empty(trim($data[$field]))) {
            throw new Exception("Missing required field: $field");
        }
    }
    
    $request_id = $data['request_id'];
    $status = $data['status'];
    $warden_id = (int)$data['warden_id'];
    $remarks = isset($data['remarks']) ? trim($data['remarks']) : null;
    
    // Get warden details
    $warden_query = "SELECT id, username, full_name, role FROM users WHERE id = ?";
    $warden_stmt = $conn->prepare($warden_query);
    $warden_stmt->bind_param("i", $warden_id);
    $warden_stmt->execute();
    $warden_data = $warden_stmt->get_result()->fetch_assoc();
    
    if (!$warden_data) throw new Exception("Warden not found");
    $warden_name = !empty($warden_data['full_name']) ? $warden_data['full_name'] : $warden_data['username'];
    
    // Check if request exists
    $check_query = "SELECT r.*, u.username as reg_no 
                    FROM room_change_requests r 
                    JOIN users u ON r.student_id = u.id 
                    WHERE r.request_id = ?";
    $check_stmt = $conn->prepare($check_query);
    $check_stmt->bind_param("s", $request_id);
    $check_stmt->execute();
    $request_data = $check_stmt->get_result()->fetch_assoc();
    
    if (!$request_data) throw new Exception('Room change request not found');

    $requested_room = $request_data['requested_room'];
    $current_room = $request_data['current_room'];
    $reg_no = $request_data['reg_no'];

    if ($status === 'approved' || $status === 'pre_approved') {
        // 1. Get room details
        $room_stmt = $conn->prepare("SELECT available_rooms, amount, room_type FROM hostel_rooms WHERE room_code = ?");
        $room_stmt->bind_param("s", $requested_room);
        $room_stmt->execute();
        $room_data = $room_stmt->get_result()->fetch_assoc();

        if (!$room_data) throw new Exception("Requested room $requested_room not found");
        if ($room_data['available_rooms'] <= 0) throw new Exception("Room $requested_room is full");

        $room_type = $room_data['room_type'] ?? 'Standard';
                $amount = getFeeForRoomType($conn, $room_type, $request_id);
                if ($amount <= 0) $amount = (float)$room_data['amount'];
                
                if ($amount <= 0) throw new Exception("Fee amount not found for '$room_type'. Please update hostel_renew_fee table.");
        
                // 2. Reject others
                $conn->query("UPDATE room_change_requests SET status = 'rejected', remarks = 'Room filled by another student' WHERE requested_room = '$requested_room' AND status = 'pending' AND request_id != '$request_id'");
        
                // 3. Check for auto-finalize (Same or lower price)
                $cp_stmt = $conn->prepare("SELECT amount, room_type FROM hostel_rooms WHERE room_code = ?");
                $cp_stmt->bind_param("s", $current_room);
                $cp_stmt->execute();
                $current_room_data = $cp_stmt->get_result()->fetch_assoc();
                
                $current_price = 0;
                if ($current_room_data) {
                    $current_price = getFeeForRoomType($conn, $current_room_data['room_type']);
                    if ($current_price <= 0) $current_price = (float)$current_room_data['amount'];
                }

        $is_upgrade = ($amount > $current_price);
        
        if ($is_upgrade) {
            // Case A: Upgrade -> pre-approve and wait for payment of the difference
            $amount_to_pay = $amount - $current_price;
            $pre_approved_remarks = ($remarks ? $remarks . " | " : "") . "Pre-approved by Warden. Waiting for student payment of upgrade fee difference: " . $amount_to_pay;
            
            $final_up = $conn->prepare("UPDATE room_change_requests SET status = 'pre_approved', payment_status = 'unpaid', amount_to_pay = ?, requested_room_type = ?, remarks = ?, processed_by = ?, processed_by_name = ?, updated_at = CURRENT_TIMESTAMP WHERE request_id = ?");
            $final_up->bind_param("dssiss", $amount_to_pay, $room_type, $pre_approved_remarks, $warden_id, $warden_name, $request_id);
            if (!$final_up->execute()) {
                throw new Exception("Failed to pre-approve request");
            }
            
            logAudit(
                $warden_id,
                $warden_data['username'],
                'warden',
                'REQUEST_PRE_APPROVED',
                'Room Change Requests',
                null,
                [
                    'request_id' => $request_id,
                    'student_id' => $request_data['student_id'],
                    'student_reg_no' => $request_data['reg_no'] ?? $reg_no,
                    'amount_to_pay' => $amount_to_pay,
                    'remarks' => $remarks
                ]
            );
            
            echo json_encode(['success' => true, 'status' => 'success', 'message' => "Request pre-approved. Upgrade fee difference is $amount_to_pay", 'amount' => $amount_to_pay]);
            exit();
        } else {
            // Case B: Downgrade or same price -> finalize directly and change room allocation
            $conn->begin_transaction();
            try {
                // Fetch old profile details (specifically current room and bed number)
                $prof_query = $conn->prepare("SELECT bed_no, room_allocation FROM profile WHERE reg_no = ?");
                $prof_query->bind_param("s", $reg_no);
                $prof_query->execute();
                $prof_data = $prof_query->get_result()->fetch_assoc();
                
                // Map current room_allocation to room number
                $old_room_no = '';
                $old_bed_no = 'B1';
                if ($prof_data) {
                    $old_bed_no = $prof_data['bed_no'] ?? 'B1';
                    $old_room_code = $prof_data['room_allocation'] ?? '';
                    
                    $old_r_stmt = $conn->prepare("SELECT room_no FROM hostel_rooms WHERE room_code = ?");
                    $old_r_stmt->bind_param("s", $old_room_code);
                    $old_r_stmt->execute();
                    $old_r_res = $old_r_stmt->get_result()->fetch_assoc();
                    $old_room_no = $old_r_res['room_no'] ?? '';
                }

                // Fetch room details
                $r_stmt = $conn->prepare("SELECT id, hostel_name, room_no, total_capacity FROM hostel_rooms WHERE room_code = ?");
                $r_stmt->bind_param("s", $requested_room);
                $r_stmt->execute();
                $r_info = $r_stmt->get_result()->fetch_assoc();
                $room_id_db = $r_info ? $r_info['id'] : 0;
                $hostel_name_db = $r_info ? $r_info['hostel_name'] : '';
                $new_room_no = $r_info ? $r_info['room_no'] : '';
                $total_cap = $r_info ? (int)$r_info['total_capacity'] : 4;

                // Assign a bed in the new room
                $occupied_beds = [];
                $b_stmt = $conn->prepare("SELECT bed_no FROM profile WHERE room_allocation = ? AND bed_no IS NOT NULL AND bed_no != ''");
                $b_stmt->bind_param("s", $requested_room);
                $b_stmt->execute();
                $b_res = $b_stmt->get_result();
                while ($b_row = $b_res->fetch_assoc()) {
                    $occupied_beds[] = strtoupper(trim($b_row['bed_no']));
                }

                // Also check virtually locked beds in allocation_requests
                $a_stmt = $conn->prepare("
                    SELECT selected_bed_number 
                    FROM allocation_requests 
                    WHERE selected_room_id = ? 
                      AND status IN ('under_review', 'payment_pending', 'approved')
                ");
                $a_stmt->bind_param("i", $room_id_db);
                $a_stmt->execute();
                $a_res = $a_stmt->get_result();
                while ($a_row = $a_res->fetch_assoc()) {
                    if (!empty($a_row['selected_bed_number'])) {
                        $occupied_beds[] = strtoupper(trim($a_row['selected_bed_number']));
                    }
                }

                $new_bed_no = "B1";
                for ($i = 1; $i <= $total_cap; $i++) {
                    $candidate = "B" . $i;
                    if (!in_array($candidate, $occupied_beds)) {
                        $new_bed_no = $candidate;
                        break;
                    }
                }

                // Check if profile exists, insert if missing
                $p_check = $conn->prepare("SELECT id FROM profile WHERE reg_no = ?");
                $p_check->bind_param("s", $reg_no);
                $p_check->execute();
                $p_exists = $p_check->get_result()->fetch_assoc();

                if (!$p_exists) {
                    $u_stmt = $conn->prepare("SELECT full_name, email, phone_number FROM users WHERE username = ?");
                    $u_stmt->bind_param("s", $reg_no);
                    $u_stmt->execute();
                    $u_row = $u_stmt->get_result()->fetch_assoc();
                    $f_name = $u_row ? $u_row['full_name'] : '';
                    $u_email = $u_row ? $u_row['email'] : '';
                    $u_phone = $u_row ? $u_row['phone_number'] : '';

                    $p_ins = $conn->prepare("INSERT INTO profile (reg_no, full_name, email, personal_phone, institution) VALUES (?, ?, ?, ?, 'Saveetha Institute of Medical and Technical Sciences')");
                    $p_ins->bind_param("ssss", $reg_no, $f_name, $u_email, $u_phone);
                    $p_ins->execute();
                }

                // Update profile with NEW ALLOCATION, RESET DATES (From Today), and set the new bed number
                $conn->query("UPDATE profile SET 
                              current_room_id = '$room_id_db',
                              room_allocation = '$requested_room', 
                              hostel_name = '$hostel_name_db',
                              bed_no = '$new_bed_no',
                              check_in_date = CURRENT_DATE,
                              renewal_date = DATE_FORMAT(DATE_ADD(CURRENT_DATE, INTERVAL 12 MONTH), '%Y-%m-%d'),
                              valid_from = CURRENT_DATE, 
                              valid_to = DATE_FORMAT(DATE_ADD(CURRENT_DATE, INTERVAL 12 MONTH), '%Y-%m-%d')
                              WHERE reg_no = '$reg_no'");
                
                if ($current_room && $current_room !== 'N/A') {
                    $conn->query("UPDATE hostel_rooms SET occupied_rooms = occupied_rooms - 1, available_rooms = available_rooms + 1 WHERE room_code = '$current_room'");
                }
                $conn->query("UPDATE hostel_rooms SET occupied_rooms = occupied_rooms + 1, available_rooms = available_rooms - 1 WHERE room_code = '$requested_room'");
                
                // Update users table as well to keep them aligned
                $conn->query("UPDATE users SET 
                              RoomId = '$requested_room', 
                              RoomType = '$room_type', 
                              HostelName = '$hostel_name_db'
                              WHERE username = '$reg_no'");
                
                $status = 'completed';
                $completed_remarks = ($remarks ? $remarks . " | " : "") . "Approved and finalized directly by Warden (No payment waiting required).";
                
                $final_up = $conn->prepare("UPDATE room_change_requests SET status = ?, payment_status = 'paid', amount_to_pay = 0.00, requested_room_type = ?, remarks = ?, processed_by = ?, processed_by_name = ?, updated_at = CURRENT_TIMESTAMP WHERE request_id = ?");
                $final_up->bind_param("sssiss", $status, $room_type, $completed_remarks, $warden_id, $warden_name, $request_id);
                $final_up->execute();

                // Log ROOM_CHANGED in audit_logs
                logAudit(
                    $warden_id,
                    $warden_data['username'],
                    'warden',
                    'ROOM_CHANGED',
                    'Room Allocation',
                    [
                        'room_no' => $old_room_no,
                        'bed_no' => $old_bed_no
                    ],
                    [
                        'room_no' => $new_room_no,
                        'bed_no' => $new_bed_no
                    ]
                );
                
                $conn->commit();
                
                echo json_encode(['success' => true, 'status' => 'success', 'message' => "Request approved and completed successfully (Downgrade/No Fee)", 'amount' => 0]);
                exit();
            } catch (Exception $e) { 
                $conn->rollback(); 
                throw $e; 
            }
        }
    } else {
        // Handle rejection or any other status update (e.g. rejected)
        $update_stmt = $conn->prepare("UPDATE room_change_requests SET status = ?, processed_by = ?, processed_by_name = ?, remarks = ?, updated_at = CURRENT_TIMESTAMP WHERE request_id = ?");
        $update_stmt->bind_param("sisss", $status, $warden_id, $warden_name, $remarks, $request_id);
        if (!$update_stmt->execute()) {
            throw new Exception("Failed to update request status to: $status");
        }
    }
    
    // Log activity
    logActivity(
        $warden_id,
        $warden_data['username'],
        'warden',
        'UPDATE_ROOM_CHANGE_REQUEST',
        'room_change_requests',
        json_encode(['status' => $request_data['status']]),
        json_encode(['status' => $status])
    );
    
    if ($status === 'rejected') {
        logAudit(
            $warden_id,
            $warden_data['username'],
            'warden',
            'REQUEST_REJECT',
            'Room Change Requests',
            null,
            [
                'request_id' => $request_id,
                'student_id' => $request_data['student_id'],
                'student_reg_no' => $request_data['reg_no'] ?? $reg_no,
                'remarks' => $remarks
            ]
        );
    }
    
    echo json_encode(['success' => true, 'status' => 'success', 'message' => "Request processed: $status", 'amount' => $amount ?? 0]);
    
} catch(Exception $e) {
    http_response_code(400);
    echo json_encode(['success' => false, 'status' => 'error', 'message' => $e->getMessage()]);
}
?>
