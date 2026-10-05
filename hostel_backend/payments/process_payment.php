<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/activity_logger.php';
require_once __DIR__ . '/../utils/auth_helper.php';

$authHeader = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
if (empty($authHeader) && function_exists('apache_request_headers')) {
    $headers = apache_request_headers();
    $authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? '';
}
$token = '';
if (preg_match('/Bearer\s+(\S+)/i', $authHeader, $matches)) {
    $token = $matches[1];
}

$payload = validateJWT($token);
if (!$payload) {
    http_response_code(401);
    echo json_encode(["status" => "error", "message" => "Unauthorized access. Valid login token required."]);
    exit();
}

$reqUserId = (int)($payload['id'] ?? 0);
$reqRole = strtolower(trim($payload['role'] ?? ''));
$isPrivileged = in_array($reqRole, ['admin', 'super_admin', 'warden', 'developer', 'it']);

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

if ($data && !empty($data->student_id) && !$isPrivileged && (int)$data->student_id !== $reqUserId) {
    http_response_code(403);
    echo json_encode(["status" => "error", "message" => "Forbidden. You cannot process payment for another student."]);
    exit();
}

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
        $is_wallet = isset($data->payment_method) && strtolower($data->payment_method) === 'wallet';
        $gateway_name = $is_wallet ? 'Wallet' : 'Razorpay';
        $gateway_response = json_encode(['gateway' => $gateway_name, 'status' => 'SUCCESS']);
        $ip_address = getClientIp();

        if ($is_wallet) {
            $w_stmt = $db->prepare("SELECT id, balance FROM user_wallets WHERE LOWER(email) = LOWER(?) OR LOWER(email) = LOWER(?) ORDER BY balance DESC LIMIT 1 FOR UPDATE");
            $w_stmt->execute([$email, "$reg.simats@saveetha.com"]);
            $wallet_row = $w_stmt->fetch(PDO::FETCH_ASSOC);
            $cur_bal = $wallet_row ? (float)$wallet_row['balance'] : 0.0;
            if ($cur_bal < (float)$data->amount) {
                http_response_code(400);
                echo json_encode(["message" => "Insufficient wallet balance", "insufficient_balance" => true, "current_balance" => $cur_bal, "required_amount" => $data->amount]);
                exit();
            }
            $new_bal = $cur_bal - (float)$data->amount;
            $db->prepare("UPDATE user_wallets SET balance = ? WHERE id = ?")->execute([$new_bal, $wallet_row['id']]);
            $db->prepare("INSERT INTO wallet_transactions (wallet_id, email, txn_type, amount, balance_after, reference_id, description) VALUES (?, ?, 'debit', ?, ?, ?, ?)")
               ->execute([$wallet_row['id'], $email, $data->amount, $new_bal, $payment_id, "Payment for " . $data->payment_type . " - Ref: $payment_id"]);
        }

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
                if (stripos($data->payment_type, '1 Year') !== false || stripos($data->payment_type, '12 Months') !== false || stripos($data->payment_type, 'Hostel Renewal') !== false) {
                    $months = 12;
                }
                
                // Fetch current dates and info from profile
                $p_stmt = $db->prepare("SELECT id, full_name, room_allocation, renewal_date, valid_to FROM profile WHERE reg_no = ? OR id = ? LIMIT 1");
                $p_stmt->execute([$reg, $data->student_id]);
                $prof = $p_stmt->fetch(PDO::FETCH_ASSOC);
                
                $baseDate = date('Y-m-d');
                if ($prof) {
                    if (!empty($prof['renewal_date']) && strtotime($prof['renewal_date']) > strtotime($baseDate)) {
                        $baseDate = $prof['renewal_date'];
                    }
                    if (!empty($prof['valid_to']) && strtotime($prof['valid_to']) > strtotime($baseDate)) {
                        $baseDate = $prof['valid_to'];
                    }
                }
                $newRenewalDate = date('Y-m-d', strtotime("$baseDate +$months months"));
                $daysRemaining = max(0, (int)round((strtotime($newRenewalDate) - strtotime(date('Y-m-d'))) / 86400));
                
                // Update profile with synchronized renewal_date, valid_to, and remaining_days
                $db->prepare("UPDATE profile SET 
                              valid_from = IF(valid_from IS NULL OR valid_from = '0000-00-00', CURRENT_DATE, valid_from),
                              valid_to = ?,
                              renewal_date = ?,
                              remaining_days = ?
                              WHERE reg_no = ? OR id = ?")->execute([$newRenewalDate, $newRenewalDate, $daysRemaining, $reg, $data->student_id]);
                              
                // Also record in renewal_requests so Renewals API and Warden management reflect it immediately
                $roomNum = ($prof && !empty($prof['room_allocation'])) ? $prof['room_allocation'] : 'N/A';
                $sName = ($prof && !empty($prof['full_name'])) ? $prof['full_name'] : $name;
                $db->prepare("INSERT INTO renewal_requests 
                    (student_id, student_name, student_reg_no, room_number, reason, status, requested_at, processed_by, processed_by_name, processed_at, remarks)
                    VALUES (?, ?, ?, ?, ?, 'approved', NOW(), 1, 'Online Payment', NOW(), ?)")
                   ->execute([
                       $data->student_id,
                       $sName,
                       $reg,
                       $roomNum,
                       "$months Months Hostel Renewal (Online Payment)",
                       "Auto-approved: Paid ₹" . number_format($data->amount, 2) . " via Payment (Ref: $payment_id)"
                   ]);

                // Record in vstudy_webhook_events and vstudy_renewal_syncs
                try {
                    require_once __DIR__ . '/../utils/vstudy_sync_helper.php';
                    $renUuid = generateUuidV4();
                    $renPayload = json_encode([
                        'eventId'         => $renUuid,
                        'externalEventId' => $renUuid,
                        'eventType'       => 'booking.renewed',
                        'entityType'      => 'HOSTEL_BOOKING',
                        'entityId'        => $payment_id,
                        'occurredAt'      => date('c'),
                        'data'            => [
                            'rollNumber'        => $reg,
                            'studentName'       => $sName,
                            'roomNumber'        => $roomNum,
                            'months'            => (int)$months,
                            'amount'            => (float)$data->amount,
                            'renewalId'         => $payment_id,
                            'status'            => 'PAID',
                            'paymentMethod'     => 'Razorpay'
                        ]
                    ]);

                    $insWb = $db->prepare("
                        INSERT INTO vstudy_webhook_events (
                            event_id, event_type, entity_type, entity_id,
                            roll_number, room_number, hostel_name, status,
                            occurred_at, payload, response, created_at, updated_at
                        ) VALUES (
                            ?, 'booking.renewed', 'HOSTEL_BOOKING', ?,
                            ?, ?, ?, 'PROCESSED',
                            NOW(), ?, ?, NOW(), NOW()
                        )
                    ");
                    $hName = $prof['hostel_name'] ?? 'Hostel';
                    $insWb->execute([
                        $renUuid,
                        $payment_id,
                        $reg,
                        $roomNum,
                        $hName,
                        $renPayload,
                        json_encode(['received' => true, 'status' => 'SUCCESS'])
                    ]);

                    $insSync = $db->prepare("
                        INSERT INTO vstudy_renewal_syncs (
                            external_event_id, roll_number, student_name, renewal_id,
                            months, amount, room_rent, food, premium_multiplier,
                            status, sync_status, request_payload, response_payload, created_at, updated_at
                        ) VALUES (
                            ?, ?, ?, ?,
                            ?, ?, ?, ?, 1.00,
                            'PAID', 'synced', ?, ?, NOW(), NOW()
                        )
                    ");
                    $amt = (float)$data->amount;
                    $insSync->execute([
                        $renUuid,
                        $reg,
                        $sName,
                        $payment_id,
                        (int)$months,
                        $amt,
                        round($amt * 0.70, 2),
                        round($amt * 0.30, 2),
                        $renPayload,
                        json_encode(['received' => true, 'synced' => true])
                    ]);
                } catch (Exception $eRen) {
                    error_log("Failed to log online renewal to vstudy_webhook_events: " . $eRen->getMessage());
                }
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
                    
                    // Fetch destination room details from room_master and rooms_groups_details
                    $rm_stmt = $db->prepare("SELECT id, room_code, location_name as hostel_name, room_type FROM room_master WHERE room_code = ? OR room_no = ? LIMIT 1");
                    $rm_stmt->execute([$requested_room, $requested_room]);
                    $r_info = $rm_stmt->fetch(PDO::FETCH_ASSOC);

                    $rgd_stmt = $db->prepare("SELECT hostel_name, room_type, warden_name FROM rooms_groups_details WHERE room_number = ? LIMIT 1");
                    $rgd_stmt->execute([$requested_room]);
                    $rgd_info = $rgd_stmt->fetch(PDO::FETCH_ASSOC);

                    $room_id_db = $r_info ? (int)$r_info['id'] : null;
                    $room_code_db = $r_info ? $r_info['room_code'] : $requested_room;
                    $hostel_name_db = ($r_info && !empty($r_info['hostel_name'])) ? $r_info['hostel_name'] : ($rgd_info['hostel_name'] ?? '');
                    $room_type_db = ($r_info && !empty($r_info['room_type'])) ? $r_info['room_type'] : ($rgd_info['room_type'] ?? ($request['requested_room_type'] ?? 'Standard'));
                    $new_warden = ($rgd_info && !empty($rgd_info['warden_name'])) ? $rgd_info['warden_name'] : null;

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
                    $prof_updates = [
                        $room_id_db,
                        $room_code_db,
                        $hostel_name_db,
                        $today,
                        $expiry,
                        $today,
                        $expiry
                    ];
                    $warden_sql = "";
                    if (!empty($new_warden)) {
                        $warden_sql = ", warden = ?";
                        $prof_updates[] = $new_warden;
                    }
                    $prof_updates[] = $reg;

                    $db->prepare("UPDATE profile SET 
                                  current_room_id = ?,
                                  room_allocation = ?, 
                                  hostel_name = ?,
                                  check_in_date = ?,
                                  renewal_date = ?,
                                  valid_from = ?, 
                                  valid_to = ?
                                  $warden_sql
                                  WHERE reg_no = ?")->execute($prof_updates);
                                  
                    // Update users table as well to keep them aligned
                    $db->prepare("UPDATE users SET 
                                  RoomId = ?, 
                                  RoomType = ?, 
                                  HostelName = ?
                                  WHERE username = ? OR id = ?")->execute([$room_code_db, $room_type_db, $hostel_name_db, $reg, $data->student_id]);

                    // Sync vstudy_payments table
                    $db->prepare("UPDATE vstudy_payments SET 
                                  room_number = ?, 
                                  hostel_name = COALESCE(NULLIF(?, ''), hostel_name)
                                  WHERE roll_number = ?")->execute([$room_code_db, $hostel_name_db, $reg]);

                    // Atomic Inventory Rebalance for BOTH old room and new room in room_master and rooms_groups_details
                    $roomsToRebalance = array_filter(array_unique([$current_room, $requested_room, $room_code_db]));
                    foreach ($roomsToRebalance as $rNo) {
                        if (empty($rNo) || $rNo === 'N/A') continue;
                        $occStmt = $db->prepare("SELECT COUNT(*) FROM profile WHERE room_allocation = ?");
                        $occStmt->execute([$rNo]);
                        $occCount = (int)$occStmt->fetchColumn();

                        $db->prepare("
                            UPDATE room_master 
                            SET occupied_beds = ?, 
                                available_beds = GREATEST(0, total_beds - ?) 
                            WHERE room_no = ? OR room_code = ?
                        ")->execute([$occCount, $occCount, $rNo, $rNo]);

                        $db->prepare("
                            UPDATE rooms_groups_details 
                            SET occupied_beds = ?, 
                                available_beds = GREATEST(0, total_beds - ?) 
                            WHERE room_number = ?
                        ")->execute([$occCount, $occCount, $rNo]);
                    }

                    // Invalidate session micro-cache for room master fetch
                    if (session_status() === PHP_SESSION_ACTIVE) {
                        unset($_SESSION['room_student_map_v4'], $_SESSION['room_id_map_v4'], $_SESSION['room_map_expire_v4']);
                    }

                    // Outbound Real-time Sync to VStudy ERP for Transfer
                    try {
                        require_once __DIR__ . '/../utils/vstudy_sync_helper.php';
                        syncTransferToVStudy($reg, $room_code_db, $hostel_name_db, $current_room);
                    } catch (Exception $e) {
                        error_log("VStudy transfer sync error: " . $e->getMessage());
                    }
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

        // Store failed payment event in vstudy_webhook_events table without calling external VStudy ERP
        try {
            require_once __DIR__ . '/../utils/vstudy_sync_helper.php';
            $failUuid = generateUuidV4();
            $failPayload = json_encode([
                'eventId'         => $failUuid,
                'externalEventId' => $failUuid,
                'eventType'       => 'payment.failed',
                'entityType'      => 'PAYMENT',
                'entityId'        => $temp_txn,
                'occurredAt'      => date('c'),
                'data'            => [
                    'rollNumber'      => $temp_reg,
                    'transactionId'   => $temp_txn,
                    'amount'          => (float)$temp_amt,
                    'paymentType'     => $data->payment_type ?? 'hostel_fee',
                    'failureReason'   => $e->getMessage(),
                    'status'          => 'FAILED'
                ]
            ]);

            $insFail = $db->prepare("
                INSERT INTO vstudy_webhook_events (
                    event_id, event_type, entity_type, entity_id,
                    roll_number, room_number, hostel_name, status,
                    occurred_at, payload, response, created_at, updated_at
                ) VALUES (
                    ?, 'payment.failed', 'PAYMENT', ?,
                    ?, '', '', 'FAILED',
                    NOW(), ?, ?, NOW(), NOW()
                )
            ");
            $insFail->execute([
                $failUuid,
                $temp_txn,
                $temp_reg,
                $failPayload,
                json_encode(['received' => true, 'status' => 'PAYMENT_FAILED_INTERNAL'])
            ]);
        } catch (Exception $wbFailEx) {
            error_log("Failed to log payment failure to vstudy_webhook_events: " . $wbFailEx->getMessage());
        }
    } catch (Exception $log_ex) {
        error_log("Failed to log PAYMENT_FAILED: " . $log_ex->getMessage());
    }
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
?>
