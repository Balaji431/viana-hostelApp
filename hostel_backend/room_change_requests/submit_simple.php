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



require_once 'simple_storage.php';
try {
    // Get JSON input
    $json_input = file_get_contents('php://input');
    $data = json_decode($json_input, true);
    
    if (!$data) {
        throw new Exception('Invalid JSON data');
    }
    
    // Validate required fields
    $required_fields = ['student_id', 'current_room', 'requested_room', 'reason'];
    foreach ($required_fields as $field) {
        if (!isset($data[$field]) || empty(trim($data[$field]))) {
            throw new Exception("Missing required field: $field");
        }
    }
    
    // Generate unique request ID
    $request_id = 'RCR-' . str_pad(mt_rand(1, 999999), 6, '0', STR_PAD_LEFT);
    
    // Create storage instance
    $storage = new SimpleStorage();
    
    // Check if student already has a pending request
    $pending_requests = $storage->getRequests('pending');
    foreach ($pending_requests as $req) {
        if ($req['studentId'] == $data['student_id']) {
            throw new Exception('You already have a pending room change request');
        }
    }
    
    // Fetch real student details from database
    $student_id = (int)$data['student_id'];
    $student_query = "SELECT id, username FROM users WHERE id = ? AND role = 'student'";
    $student_stmt = $conn->prepare($student_query);
    $student_stmt->bind_param("i", $student_id);
    $student_stmt->execute();
    $student_result = $student_stmt->get_result();
    
    if ($student_result->num_rows === 0) {
        throw new Exception('Student not found');
    }
    
    $student_data = $student_result->fetch_assoc();
    $student_name = $student_data['username'] ?? 'Unknown Student';
    $student_reg_no = 'REG' . $student_id; // Fallback to student ID
    
    // Add the request with real student details
    $request = [
        'requestId' => $request_id,
        'studentId' => (int)$data['student_id'],
        'studentName' => $student_name,
        'studentRegNo' => $student_reg_no,
        'currentRoom' => $data['current_room'],
        'requestedRoom' => $data['requested_room'],
        'reason' => $data['reason'],
    ];
    
    $saved_request = $storage->addRequest($request);
    
    echo json_encode([
        'status' => 'success',
        'message' => 'Room change request submitted successfully',
        'data' => $saved_request
    ]);
    
} catch(Exception $e) {
    http_response_code(400);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}
?>
