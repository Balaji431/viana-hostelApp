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
    
    // Validate required fields (request_id is optional)
    $required_fields = ['student_id', 'current_room', 'requested_room', 'reason'];
    foreach ($required_fields as $field) {
        if (!isset($data[$field]) || empty(trim($data[$field]))) {
            throw new Exception("Missing required field: $field");
        }
    }
    
    $student_id = (int)$data['student_id'];
    $current_room = trim($data['current_room']);
    $requested_room = trim($data['requested_room']);
    $reason = trim($data['reason']);
    
    // Generate unique request ID or use provided one
    $request_id = isset($data['request_id']) && !empty(trim($data['request_id'])) 
        ? trim($data['request_id']) 
        : 'RCR-' . str_pad(mt_rand(1, 999999), 6, '0', STR_PAD_LEFT);
    
    // Get student details from database
    $student_query = "SELECT id, username, RegisterNumber FROM users WHERE id = ? AND role = 'student'";
    $student_stmt = $conn->prepare($student_query);
    $student_stmt->bind_param("i", $student_id);
    $student_stmt->execute();
    $student_result = $student_stmt->get_result();
    
    file_put_contents('debug_student_submit.log', date('[Y-m-d H:i:s] ') . "Querying student ID $student_id. Rows found: " . $student_result->num_rows . "\n", FILE_APPEND);
    
    if ($student_result->num_rows === 0) {
        throw new Exception("Student with ID $student_id not found in 'users' table");
    }
    
    $student_data = $student_result->fetch_assoc();
    $student_name = $student_data['username'] ?? 'Unknown Student';
    $student_reg_no = $student_data['RegisterNumber'] ?? 'REG' . $student_id;
    
    // Check if there's already a pending room change request for this student in room_change_requests table
    $check_pending = $conn->prepare("SELECT id FROM room_change_requests WHERE student_id = ? AND status = 'pending'");
    $check_pending->bind_param("i", $student_id);
    $check_pending->execute();
    $pending_result = $check_pending->get_result();
    
    if ($pending_result->num_rows > 0) {
        throw new Exception('You already have a pending room change request');
    }
    
    // Insert the room change request into room_change_requests table
    $insert_request = $conn->prepare("
        INSERT INTO room_change_requests (
            request_id, 
            student_id, 
            student_name,
            student_reg_no,
            current_room, 
            requested_room, 
            reason, 
            status, 
            created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', NOW())
    ");
    
    $insert_request->bind_param("sisssss", $request_id, $student_id, $student_name, $student_reg_no, $current_room, $requested_room, $reason);
    
    if (!$insert_request->execute()) {
        throw new Exception('Failed to submit room change request');
    }
    
    // Get the inserted request details
    $request_details = [
        'request_id' => $request_id,
        'student_id' => $student_id,
        'student_name' => $student_name,
        'student_reg_no' => $student_reg_no,
        'current_room' => $current_room,
        'requested_room' => $requested_room,
        'reason' => $reason,
        'status' => 'pending',
        'created_at' => date('Y-m-d H:i:s')
    ];
    
    // Return success response
    echo json_encode([
        'success' => true,
        'status' => 'success',
        'message' => 'Room change request submitted successfully',
        'data' => $request_details
    ]);
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}

$conn->close();
?>
