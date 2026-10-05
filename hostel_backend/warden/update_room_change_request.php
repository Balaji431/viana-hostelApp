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

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit(0);
}

try {
    // Get JSON input
    $json_input = file_get_contents('php://input');
    $data = json_decode($json_input, true);
    
    if (!$data) {
        throw new Exception('Invalid JSON data');
    }
    
    // Validate required fields
    $required_fields = ['request_id', 'status'];
    foreach ($required_fields as $field) {
        if (!isset($data[$field]) || empty(trim($data[$field]))) {
            throw new Exception("Missing required field: $field");
        }
    }
    
    $request_id = trim($data['request_id']);
    $status = trim($data['status']);
    $warden_id = !empty($data['warden_id']) ? (int)$data['warden_id'] : (int)$authUser['id'];
    $remarks = isset($data['remarks']) ? trim($data['remarks']) : null;
    
    // Validate status
    if (!in_array($status, ['approved', 'rejected', 'completed'])) {
        throw new Exception('Invalid status. Must be: approved, rejected, or completed');
    }
    
    // Validate warden exists
    $check_warden = $conn->prepare("SELECT id FROM users WHERE id = ? AND role = 'warden'");
    $check_warden->bind_param("i", $warden_id);
    $check_warden->execute();
    $warden_result = $check_warden->get_result();
    
    if ($warden_result->num_rows === 0) {
        throw new Exception('Warden not found or unauthorized');
    }
    
    // Check if request exists and is pending
    $check_request = $conn->prepare("
        SELECT id, student_id, current_room, requested_room, status 
        FROM request1 
        WHERE request_id = ? AND request_type = 'room_change'
    ");
    $check_request->bind_param("s", $request_id);
    $check_request->execute();
    $request_result = $check_request->get_result();
    
    if ($request_result->num_rows === 0) {
        throw new Exception('Room change request not found');
    }
    
    $request_data = $request_result->fetch_assoc();
    
    // Start transaction
    $conn->begin_transaction();
    
    try {
        // Update the request status
        $update_request = $conn->prepare("
            UPDATE request1 
            SET status = ?, updated_at = NOW() 
            WHERE request_id = ?
        ");
        $update_request->bind_param("ss", $status, $request_id);
        $update_request->execute();
        
        // If approved, update student's room allocation
        if ($status === 'approved') {
            // Note: student's room allocation is managed in the profile table
        }
        
        // Add remarks if provided (you might want to add a remarks column to the table)
        if ($remarks) {
            // For now, we'll just log this - you can add a remarks table or column
            error_log("Request $request_id remarks by warden $warden_id: $remarks");
        }
        
        // Commit transaction
        $conn->commit();
        
        $previous_state = json_encode(['status' => $request_data['status']]);
        $after_state = json_encode(['status' => $status]);
        
        logActivity(
            $warden_id,
            'warden',
            'warden',
            'UPDATE_ROOM_CHANGE_REQUEST',
            'request1',
            $previous_state,
            $after_state
        );
        
        // Get updated request details
        $updated_request = [
            'request_id' => $request_id,
            'status' => $status,
            'updated_at' => date('Y-m-d H:i:s'),
            'processed_by' => $warden_id
        ];
        
        echo json_encode([
            'status' => 'success',
            'message' => "Room change request $status successfully",
            'data' => $updated_request
        ]);
        
    } catch (Exception $e) {
        // Rollback transaction on error
        $conn->rollback();
        throw $e;
    }
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}

$conn->close();
?>
