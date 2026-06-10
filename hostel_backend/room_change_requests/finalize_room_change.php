<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header("Content-Type: application/json; charset=UTF-8");

require_once '../config/database.php';
require_once '../utils/activity_logger.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

try {
    $json = file_get_contents('php://input');
    $data = json_decode($json, true);
    
    if (!$data || !isset($data['request_id']) || !isset($data['student_id']) || !isset($data['new_room_code'])) {
        throw new Exception('Missing required fields');
    }
    
    $request_id = $data['request_id'];
    $student_id = (int)$data['student_id'];
    $new_room_code = $data['new_room_code'];
    
    // 1. Get request and student details
    $req_query = "SELECT r.*, u.username as reg_no FROM room_change_requests r 
                  JOIN users u ON r.student_id = u.id 
                  WHERE r.request_id = ?";
    $req_stmt = $conn->prepare($req_query);
    $req_stmt->bind_param("s", $request_id);
    $req_stmt->execute();
    $request = $req_stmt->get_result()->fetch_assoc();
    
    if (!$request) throw new Exception('Request not found');
    if ($request['status'] !== 'approved') throw new Exception('Only approved requests can be finalized');
    
    $old_room_code = $request['current_room'];
    $reg_no = $request['reg_no'];
    
    $conn->begin_transaction();
    
    // 2. Fetch room details
    $r_stmt = $conn->prepare("SELECT id, hostel_name FROM hostel_rooms WHERE room_code = ?");
    $r_stmt->bind_param("s", $new_room_code);
    $r_stmt->execute();
    $r_info = $r_stmt->get_result()->fetch_assoc();
    $room_id_db = $r_info ? $r_info['id'] : 0;
    $hostel_name_db = $r_info ? $r_info['hostel_name'] : '';

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

    // Update Student Profile
    $up_profile = "UPDATE profile SET current_room_id = ?, room_allocation = ?, hostel_name = ? WHERE reg_no = ?";
    $up_stmt = $conn->prepare($up_profile);
    $up_stmt->bind_param("isss", $room_id_db, $new_room_code, $hostel_name_db, $reg_no);
    $up_stmt->execute();
    
    // 3. Update Occupancy for OLD room
    if ($old_room_code && $old_room_code !== 'N/A') {
        $conn->query("UPDATE hostel_rooms SET occupied_rooms = occupied_rooms - 1, available_rooms = available_rooms + 1 WHERE room_code = '$old_room_code'");
    }
    
    // 4. Update Occupancy for NEW room
    $conn->query("UPDATE hostel_rooms SET occupied_rooms = occupied_rooms + 1, available_rooms = available_rooms - 1 WHERE room_code = '$new_room_code'");
    
    // 5. Update Request Status
    $conn->query("UPDATE room_change_requests SET status = 'completed', updated_at = CURRENT_TIMESTAMP WHERE request_id = '$request_id'");
    
    $conn->commit();
    
    // Log activity
    logActivity(
        $data['warden_id'] ?? null,
        $data['warden_username'] ?? 'warden',
        'warden',
        'FINALIZE_ROOM_CHANGE',
        'room_change_requests & profile',
        json_encode(['status' => 'approved', 'room_allocation' => $old_room_code]),
        json_encode(['status' => 'completed', 'room_allocation' => $new_room_code])
    );
    
    echo json_encode(['success' => true, 'message' => 'Room change finalized successfully']);
    
} catch (Exception $e) {
    if (isset($conn)) $conn->rollback();
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => $e->getMessage()]);
}
?>
