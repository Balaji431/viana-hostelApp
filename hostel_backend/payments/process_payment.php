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

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

try {
    if($data && !empty($data->student_id) && !empty($data->amount) && !empty($data->payment_type)) {
        // 1. Fetch user info
        $query_u = "SELECT u.full_name, u.username as reg_no, p.email, p.personal_phone as phone, p.institution
                    FROM users u 
                    LEFT JOIN profile p ON u.username = p.reg_no 
                    WHERE u.id = ?";
        $stmt_u = $db->prepare($query_u);
        $stmt_u->execute([$data->student_id]);
        $user_info = $stmt_u->fetch(PDO::FETCH_ASSOC);

        if (!$user_info) {
            throw new Exception("Student not found");
        }

        $payment_id = "E" . time() . rand(10, 99);
        $reg = $user_info['reg_no'];
        $name = $user_info['full_name'];
        $campus = $user_info['institution'] ?? "Thandalam Campus";
        $email = $user_info['email'] ?? ($data->email ?? "$reg.simats@saveetha.com");
        $phone = $user_info['phone'] ?? ($data->contactNumber ?? "N/A");

        // 2. Insert payment record
        $gateway_response = json_encode(['gateway' => 'Razorpay', 'status' => 'SUCCESS']);
        $ip_address = getClientIp();
        $query = "INSERT INTO payment (campus, registerNumber, name, email, contactNumber, payment_type, payment_id, amount, status, admin_status, gateway_response, user_id, ip_address, paid_at) 
                  VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'Success', 'Confirmed', ?, ?, ?, NOW())";
        
        $stmt = $db->prepare($query);

        if($stmt->execute([$campus, $reg, $name, $email, $phone, $data->payment_type, $payment_id, $data->amount, $gateway_response, $data->student_id, $ip_address])) {
            logAudit(
                $data->student_id,
                $reg,
                'student',
                "PAYMENT_SUCCESS",
                "Payments",
                null,
                [
                    "student_reg_no" => $reg,
                    "student_name" => $name,
                    "transaction_id" => $payment_id,
                    "payment_gateway" => "Razorpay",
                    "amount" => (string)$data->amount,
                    "payment_time" => date('Y-m-d H:i:s'),
                    "status" => "SUCCESS"
                ]
            );
            
            $today = date('Y-m-d');
            $expiry = date('Y-m-d', strtotime('+12 months'));

            // 3. Handle Renewal or Room Change Date Updates
            if (stripos($data->payment_type, 'Renewal') !== false) {
                $months = 6;
                if (stripos($data->payment_type, '1 Year') !== false || stripos($data->payment_type, '12 Months') !== false) {
                    $months = 12;
                }
                
                // Standard Renewal: Add months to existing expiry
                $db->prepare("UPDATE profile SET 
                              valid_from = IF(valid_from IS NULL OR valid_from = '0000-00-00', CURRENT_DATE, valid_from),
                              valid_to = DATE_FORMAT(DATE_ADD(IF(valid_to IS NULL OR valid_to = '0000-00-00', CURRENT_DATE, STR_TO_DATE(valid_to, '%Y-%m-%d')), INTERVAL ? MONTH), '%Y-%m-%d')
                              WHERE reg_no = ?")->execute([$months, $reg]);
            }

            // 4. Handle Room Change / New Allocation
            if (isset($data->request_id) && !empty($data->request_id)) {
                $request_id = $data->request_id;
                
                $req_stmt = $db->prepare("SELECT * FROM room_change_requests WHERE request_id = ?");
                $req_stmt->execute([$request_id]);
                $request = $req_stmt->fetch(PDO::FETCH_ASSOC);
                
                if ($request && ($request['status'] === 'pre_approved' || $request['status'] === 'approved')) {
                    $requested_room = $request['requested_room'];
                    $current_room = $request['current_room'];
                    
                    // Update Request
                    $db->prepare("UPDATE room_change_requests SET status = 'completed', payment_status = 'paid', updated_at = CURRENT_TIMESTAMP WHERE request_id = ?")
                       ->execute([$request_id]);
                    
                    // Fetch room from hostel_rooms matching requested_room (room_code)
                    $r_stmt = $db->prepare("SELECT id, room_code, hostel_name, room_type FROM hostel_rooms WHERE room_code = ?");
                    $r_stmt->execute([$requested_room]);
                    $r_info = $r_stmt->fetch(PDO::FETCH_ASSOC);
                    
                    $room_id_db = $r_info ? $r_info['id'] : null;
                    $room_code_db = $r_info ? $r_info['room_code'] : $requested_room;
                    $hostel_name_db = $r_info ? $r_info['hostel_name'] : '';
                    $room_type_db = $r_info ? $r_info['room_type'] : ($request['requested_room_type'] ?? 'Standard');

                    // Check if profile exists, insert if missing
                    $p_stmt = $db->prepare("SELECT id FROM profile WHERE reg_no = ?");
                    $p_stmt->execute([$reg]);
                    $p_exists = $p_stmt->fetch(PDO::FETCH_ASSOC);

                    if (!$p_exists) {
                        // Fetch user info
                        $u_stmt = $db->prepare("SELECT full_name, email, phone_number FROM users WHERE username = ?");
                        $u_stmt->execute([$reg]);
                        $u_row = $u_stmt->fetch(PDO::FETCH_ASSOC);
                        $f_name = $u_row ? $u_row['full_name'] : '';
                        $u_email = $u_row ? $u_row['email'] : '';
                        $u_phone = $u_row ? $u_row['phone_number'] : '';

                        $p_ins = $db->prepare("INSERT INTO profile (reg_no, full_name, email, personal_phone, institution) VALUES (?, ?, ?, ?, 'Saveetha Institute of Medical and Technical Sciences')");
                        $p_ins->execute([$reg, $f_name, $u_email, $u_phone]);
                    }

                    // Update Profile & Sync Dates
                    $db->prepare("UPDATE profile SET 
                                  current_room_id = ?,
                                  room_allocation = ?, 
                                  hostel_name = ?,
                                  check_in_date = ?,
                                  renewal_date = ?,
                                  valid_from = ?, 
                                  valid_to = ?
                                  WHERE reg_no = ?")->execute([$room_id_db, $room_code_db, $hostel_name_db, $today, $expiry, $today, $expiry, $reg]);
                                  
                    // Update users table as well to keep them aligned
                    $db->prepare("UPDATE users SET 
                                  RoomId = ?, 
                                  RoomType = ?, 
                                  HostelName = ?
                                  WHERE username = ?")->execute([$room_code_db, $room_type_db, $hostel_name_db, $reg]);

                    // Update occupancies
                    if ($current_room && $current_room !== 'N/A') {
                        $db->prepare("UPDATE hostel_rooms SET occupied_rooms = occupied_rooms - 1, available_rooms = available_rooms + 1 WHERE room_code = ?")
                           ->execute([$current_room]);
                    }
                    $db->prepare("UPDATE hostel_rooms SET occupied_rooms = occupied_rooms + 1, available_rooms = available_rooms - 1 WHERE room_code = ?")
                       ->execute([$requested_room]);
                }
            }

            echo json_encode(["success" => true, "message" => "Success", "payment_id" => $payment_id]);
        } else {
            throw new Exception("Database Error");
        }
    } else {
        throw new Exception("Incomplete data");
    }
} catch (Exception $e) {
    // Log PAYMENT_FAILED
    try {
        $temp_reg = isset($reg) ? $reg : '';
        if (empty($temp_reg) && isset($data->student_id)) {
            $temp_stmt = $db->prepare("SELECT username FROM users WHERE id = ?");
            $temp_stmt->execute([$data->student_id]);
            $temp_u = $temp_stmt->fetch(PDO::FETCH_ASSOC);
            $temp_reg = $temp_u['username'] ?? '';
        }
        $temp_txn = isset($payment_id) ? $payment_id : 'N/A';
        $temp_amt = (string)($data->amount ?? '0');
        logAudit(
            isset($data->student_id) ? $data->student_id : null,
            $temp_reg,
            'student',
            'PAYMENT_FAILED',
            'Payments',
            null,
            [
                'student_reg_no' => $temp_reg,
                'transaction_id' => $temp_txn,
                'amount' => $temp_amt,
                'failure_reason' => $e->getMessage(),
                'timestamp' => date('Y-m-d H:i:s')
            ]
        );
    } catch (Exception $log_ex) {
        error_log("Failed to log PAYMENT_FAILED: " . $log_ex->getMessage());
    }
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
?>
