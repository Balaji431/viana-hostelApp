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
require_once '../utils/auth_helper.php';

$authUser = requireAuth(['warden', 'admin', 'super_admin']);

$database = new DatabaseMysqli();
$conn = $database->getConnection();

try {
    $json_input = file_get_contents('php://input');
    $data = json_decode($json_input, true);
    
    if (!$data) throw new Exception('Invalid JSON data');
    
    $required_fields = ['request_id', 'status'];
    foreach ($required_fields as $field) {
        if (!isset($data[$field]) || empty(trim($data[$field]))) {
            throw new Exception("Missing required field: $field");
        }
    }
    
    $request_id = $data['request_id'];
    $status = strtolower(trim($data['status']));
    $warden_id = !empty($data['warden_id']) ? (int)$data['warden_id'] : (int)$authUser['id'];
    $remarks = isset($data['remarks']) ? trim($data['remarks']) : null;
    
    // Get warden details
    $warden_query = "SELECT id, username, full_name, role FROM users WHERE id = ?";
    $warden_stmt = $conn->prepare($warden_query);
    $warden_stmt->bind_param("i", $warden_id);
    $warden_stmt->execute();
    $warden_data = $warden_stmt->get_result()->fetch_assoc();
    
    if (!$warden_data) throw new Exception("Warden not found");
    $warden_name = !empty($warden_data['full_name']) ? $warden_data['full_name'] : $warden_data['username'];
    
    // Check if request exists in room_change_requests
    $check_query = "SELECT * FROM room_change_requests WHERE request_id = ?";
    $check_stmt = $conn->prepare($check_query);
    $check_stmt->bind_param("s", $request_id);
    $check_stmt->execute();
    $request_data = $check_stmt->get_result()->fetch_assoc();
    
    if (!$request_data) throw new Exception('Room change request not found');

    $requested_room = $request_data['requested_room'];
    $current_room = $request_data['current_room'];
    $reg_no = $request_data['student_reg_no'];
    $student_id = $request_data['student_id'];
    $requested_room_type = $request_data['requested_room_type'] ?? 'Standard';
    $amount_to_pay = (float)($request_data['amount_to_pay'] ?? 0.00);

    if ($status === 'approved' || $status === 'pre_approved') {
        // Check available bed vacancy from room_master before approving
        $vac_query = "SELECT COALESCE(SUM(rm.available_beds), 10) as total_vac 
                      FROM room_master rm 
                      WHERE (LOWER(TRIM(rm.room_type)) LIKE CONCAT('%', LOWER(TRIM(?)), '%') OR LOWER(TRIM(rm.room_code)) = LOWER(TRIM(?))) AND rm.active = 1";
        $vac_stmt = $conn->prepare($vac_query);
        $vac_stmt->bind_param("ss", $requested_room_type, $requested_room);
        $vac_stmt->execute();
        $vac_res = $vac_stmt->get_result()->fetch_assoc();
        $total_vac = (int)($vac_res['total_vac'] ?? 10);

        if ($total_vac <= 0) {
            throw new Exception("⚠️ Cannot approve application: No vacant beds available for requested room type.");
        }

        if ($amount_to_pay > 0) {
            // Upgrade request: Approve and wait for student upgrade fee payment
            $final_status = 'approved';
            $approved_remarks = ($remarks ? $remarks . " | " : "") . "Approved by Warden. Payment pending: ₹" . number_format($amount_to_pay);

            // Reserve room for 3 days (72 hours) for payment
            $up_stmt = $conn->prepare("UPDATE room_change_requests SET status = ?, payment_status = 'unpaid', reserved_until = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 3 DAY), remarks = ?, processed_by = ?, processed_by_name = ?, updated_at = CURRENT_TIMESTAMP WHERE request_id = ?");
            $up_stmt->bind_param("ssiss", $final_status, $approved_remarks, $warden_id, $warden_name, $request_id);
            if (!$up_stmt->execute()) {
                throw new Exception("Failed to approve room change request");
            }

            logAudit(
                $warden_id,
                $warden_data['username'],
                'warden',
                'REQUEST_APPROVED',
                'Room Change Requests',
                null,
                [
                    'request_id' => $request_id,
                    'student_id' => $student_id,
                    'student_reg_no' => $reg_no,
                    'amount_to_pay' => $amount_to_pay,
                    'remarks' => $remarks
                ]
            );

            echo json_encode([
                'success' => true,
                'status' => 'success',
                'message' => "Request approved. Upgrade fee to be paid: ₹" . number_format($amount_to_pay),
                'amount' => $amount_to_pay
            ]);
            exit();
        } else {
            // Same room type / downgrade: Approve and finalize allocation directly
            $final_status = 'approved';
            $approved_remarks = ($remarks ? $remarks . " | " : "") . "Approved and room allocation updated.";

            $up_stmt = $conn->prepare("UPDATE room_change_requests SET status = ?, payment_status = 'paid', remarks = ?, processed_by = ?, processed_by_name = ?, updated_at = CURRENT_TIMESTAMP WHERE request_id = ?");
            $up_stmt->bind_param("ssiss", $final_status, $approved_remarks, $warden_id, $warden_name, $request_id);
            $up_stmt->execute();

            // Update student room in users table
            $conn->query("UPDATE users SET RoomId = '$requested_room', RoomType = '$requested_room_type' WHERE username = '$reg_no' OR id = '$student_id'");

            // Fetch destination room master ID if available
            $rm_stmt = $conn->prepare("SELECT id, location_name FROM room_master WHERE REPLACE(REPLACE(TRIM(room_code), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(?), ' ', ''), '-', '') LIMIT 1");
            $rm_stmt->bind_param("s", $requested_room);
            $rm_stmt->execute();
            $rm_row = $rm_stmt->get_result()->fetch_assoc();
            $new_rm_id = $rm_row ? (int)$rm_row['id'] : 0;
            $new_hostel_name = $rm_row['location_name'] ?? '';

            // Update profile table
            if ($new_rm_id > 0) {
                $conn->query("UPDATE profile SET room_allocation = '$requested_room', current_room_id = $new_rm_id" . (!empty($new_hostel_name) ? ", hostel_name = '$new_hostel_name'" : "") . " WHERE reg_no = '$reg_no'");
            } else {
                $conn->query("UPDATE profile SET room_allocation = '$requested_room' WHERE reg_no = '$reg_no'");
            }

            // Sync vstudy_payments table
            $conn->query("UPDATE vstudy_payments SET room_number = '$requested_room'" . (!empty($new_hostel_name) ? ", hostel_name = '$new_hostel_name'" : "") . " WHERE roll_number = '$reg_no'");

            // Atomic Inventory Rebalance for BOTH old room and new room in room_master and rooms_groups_details
            $roomsToRebalance = array_filter(array_unique([$current_room, $requested_room]));
            foreach ($roomsToRebalance as $rNo) {
                if (empty($rNo) || $rNo === 'N/A') continue;
                $occRes = $conn->query("SELECT COUNT(*) as occ FROM profile WHERE room_allocation = '$rNo'");
                $occCount = $occRes ? (int)($occRes->fetch_assoc()['occ'] ?? 0) : 0;
                $conn->query("UPDATE room_master SET occupied_beds = $occCount, available_beds = GREATEST(0, total_beds - $occCount) WHERE room_no = '$rNo' OR room_code = '$rNo'");
                $conn->query("UPDATE rooms_groups_details SET occupied_beds = $occCount, available_beds = GREATEST(0, total_beds - $occCount) WHERE room_number = '$rNo'");
            }

            // Outbound Real-time Sync to VStudy ERP for Transfer
            try {
                require_once __DIR__ . '/../utils/vstudy_sync_helper.php';
                syncTransferToVStudy($reg_no, $requested_room, $new_hostel_name, $current_room);
            } catch (Exception $e) {
                error_log("VStudy transfer sync error: " . $e->getMessage());
            }

            logAudit(
                $warden_id,
                $warden_data['username'],
                'warden',
                'REQUEST_APPROVED',
                'Room Change Requests',
                null,
                [
                    'request_id' => $request_id,
                    'student_id' => $student_id,
                    'student_reg_no' => $reg_no,
                    'new_room' => $requested_room,
                    'remarks' => $remarks
                ]
            );

            echo json_encode([
                'success' => true,
                'status' => 'success',
                'message' => "Request approved and room updated to $requested_room."
            ]);
            exit();
        }
    } else if ($status === 'rejected') {
        $rej_remarks = $remarks ? $remarks : "Rejected by Warden";
        $up_stmt = $conn->prepare("UPDATE room_change_requests SET status = 'rejected', remarks = ?, rejection_reason = ?, processed_by = ?, processed_by_name = ?, updated_at = CURRENT_TIMESTAMP WHERE request_id = ?");
        $up_stmt->bind_param("ssiss", $rej_remarks, $rej_remarks, $warden_id, $warden_name, $request_id);
        if (!$up_stmt->execute()) {
            throw new Exception("Failed to reject request");
        }

        logAudit(
            $warden_id,
            $warden_data['username'],
            'warden',
            'REQUEST_REJECTED',
            'Room Change Requests',
            null,
            [
                'request_id' => $request_id,
                'student_id' => $student_id,
                'student_reg_no' => $reg_no,
                'rejection_reason' => $rej_remarks
            ]
        );

        // Store rejected transfer in vstudy_webhook_events without sending to external VStudy ERP
        try {
            require_once __DIR__ . '/../utils/vstudy_sync_helper.php';
            $eventUuid = generateUuidV4();
            $rejPayload = json_encode([
                'eventId'         => $eventUuid,
                'externalEventId' => $eventUuid,
                'eventType'       => 'booking.transfer_rejected',
                'entityType'      => 'HOSTEL_BOOKING',
                'entityId'        => $request_id,
                'occurredAt'      => date('c'),
                'data'            => [
                    'requestId'       => $request_id,
                    'rollNumber'      => $reg_no,
                    'currentRoom'     => $current_room,
                    'requestedRoom'   => $requested_room,
                    'rejectionReason' => $rej_remarks,
                    'wardenName'      => $warden_name,
                    'status'          => 'REJECTED'
                ]
            ]);

            $insWb = $conn->prepare("
                INSERT INTO vstudy_webhook_events (
                    event_id, event_type, entity_type, entity_id,
                    roll_number, room_number, hostel_name, status,
                    occurred_at, payload, response, created_at, updated_at
                ) VALUES (
                    ?, 'booking.transfer_rejected', 'HOSTEL_BOOKING', ?,
                    ?, ?, '', 'REJECTED',
                    NOW(), ?, ?, NOW(), NOW()
                )
            ");
            $respStr = json_encode(['received' => true, 'status' => 'REJECTED_INTERNAL']);
            $insWb->bind_param("ssssss", $eventUuid, $request_id, $reg_no, $requested_room, $rejPayload, $respStr);
            $insWb->execute();
        } catch (Exception $eWb) {
            error_log("Failed to log rejected transfer to vstudy_webhook_events: " . $eWb->getMessage());
        }

        echo json_encode([
            'success' => true,
            'status' => 'success',
            'message' => "Request rejected successfully."
        ]);
        exit();
    } else {
        throw new Exception("Invalid status action: $status");
    }
} catch(Exception $e) {
    http_response_code(400);
    echo json_encode([
        'status' => 'error',
        'success' => false,
        'message' => $e->getMessage()
    ]);
}
?>
