<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

$method = $_SERVER['REQUEST_METHOD'];

try {
    if ($method !== 'POST') {
        throw new Exception("Invalid request method");
    }

    $data = json_decode(file_get_contents('php://input'), true);
    $allocation_id = (int)($data['allocation_id'] ?? 0);
    $payment_method = $data['method'] ?? 'Online';

    if ($allocation_id <= 0) {
        throw new Exception("Allocation ID required");
    }

    $conn->begin_transaction();

    try {
        // 1. Lock allocation record
        $stmt = $conn->prepare("SELECT * FROM room_allocations WHERE id = ? FOR UPDATE");
        $stmt->bind_param("i", $allocation_id);
        $stmt->execute();
        $allocation = $stmt->get_result()->fetch_assoc();

        if (!$allocation) throw new Exception("Allocation request not found");
        
        // 2. Verify status and deadline
        if ($allocation['allocation_status'] !== 'payment_pending') {
            throw new Exception("Allocation is not in payment pending state (Current: " . $allocation['allocation_status'] . ")");
        }

        $now = new DateTime();
        $deadline = new DateTime($allocation['payment_deadline']);
        
        if ($now > $deadline) {
            // Logic for expiration should ideally be handled by a cron, 
            // but we check it here too for safety.
            $conn->query("UPDATE room_allocations SET allocation_status = 'payment_expired' WHERE id = $allocation_id");
            $conn->query("UPDATE hostel_rooms SET blocked_by = NULL, blocked_until = NULL WHERE id = " . $allocation['allocated_room_id']);
            $conn->commit();
            throw new Exception("Payment deadline has expired");
        }

        $student_id = $allocation['student_id'];
        $room_id = $allocation['allocated_room_id'];

        // 3. Update Room Occupancy
        $conn->query("UPDATE hostel_rooms SET occupied_rooms = occupied_rooms + 1, blocked_by = NULL, blocked_until = NULL WHERE id = $room_id");

        // 4. Update Profile (using JOIN to match reg_no)
        $check_in_date = $now->format('Y-m-d');
        $renewal_date = (clone $now)->modify('+365 days')->format('Y-m-d');
        
        // Fetch room info to populate profile text fields
        $room_stmt = $conn->prepare("SELECT room_code, hostel_name FROM hostel_rooms WHERE id = ?");
        $room_stmt->bind_param("i", $room_id);
        $room_stmt->execute();
        $room_info = $room_stmt->get_result()->fetch_assoc();
        
        $room_code = $room_info['room_code'] ?? '';
        $h_name = $room_info['hostel_name'] ?? '';

        // Fetch student details from users table to verify/insert profile row if missing
        $u_stmt = $conn->prepare("SELECT username, full_name, email, phone_number FROM users WHERE id = ?");
        $u_stmt->bind_param("i", $student_id);
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
        $up_profile->bind_param("issssssi", $room_id, $room_code, $h_name, $check_in_date, $renewal_date, $check_in_date, $renewal_date, $student_id);
        $up_profile->execute();

        // 5. Insert Payment Record
        $amount = 68000.00; // Fixed fee as per prompt
        $receipt_number = "RCP-" . time() . "-" . rand(1000, 9999);
        $description = "Room Allocation Fee - Room ID " . $room_id;
        
        $ins_pay = $conn->prepare("INSERT INTO payments (student_id, amount, receipt_number, status, description, paid_at) VALUES (?, ?, ?, 'paid', ?, ?)");
        $now_str = $now->format('Y-m-d H:i:s');
        $ins_pay->bind_param("idsss", $student_id, $amount, $receipt_number, $description, $now_str);
        $ins_pay->execute();

        // 6. Finalize Allocation Status
        $up_alloc = $conn->prepare("UPDATE room_allocations SET allocation_status = 'approved', paid_at = ? WHERE id = ?");
        $up_alloc->bind_param("si", $now_str, $allocation_id);
        $up_alloc->execute();

        // 7. Cancel Sibling Preferences
        $conn->query("UPDATE room_preferences SET status = 'cancelled' WHERE student_id = $student_id AND status = 'submitted'");

        $conn->commit();

        echo json_encode([
            "success" => true,
            "message" => "Payment successful. Room allocated.",
            "receipt_number" => $receipt_number,
            "room_id" => $room_id
        ]);

    } catch (Exception $e) {
        $conn->rollback();
        throw $e;
    }

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
?>
