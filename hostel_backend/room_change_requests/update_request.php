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
    $status = strtolower(trim($data['status']));
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

            $up_stmt = $conn->prepare("UPDATE room_change_requests SET status = ?, payment_status = 'unpaid', remarks = ?, processed_by = ?, processed_by_name = ?, updated_at = CURRENT_TIMESTAMP WHERE request_id = ?");
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
            // Update profile table
            $conn->query("UPDATE profile SET room_allocation = '$requested_room' WHERE reg_no = '$reg_no'");

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
