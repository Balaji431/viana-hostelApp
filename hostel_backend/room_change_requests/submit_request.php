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

// Initialize database connection
$database = new DatabaseMysqli();
$conn = $database->getConnection();

if (!$conn) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'Database connection failed'
    ]);
    exit();
}

try {
    // Get JSON input
    $json_input = file_get_contents('php://input');
    $data = json_decode($json_input, true);
    
    if (!$data) {
        throw new Exception('Invalid JSON data');
    }
    $data = json_decode(file_get_contents('php://input'), true);
    file_put_contents('debug_submit.log', date('[Y-m-d H:i:s] ') . "Data: " . json_encode($data) . "\n", FILE_APPEND);
    
    // Validate required fields
    $required_fields = ['student_id', 'current_room', 'requested_room', 'reason'];
    foreach ($required_fields as $field) {
        if (!isset($data[$field]) || empty(trim($data[$field]))) {
            throw new Exception("Missing required field: $field");
        }
    }
    
    // Generate unique request ID
    $request_id = 'RCR-' . str_pad(mt_rand(1, 999999), 6, '0', STR_PAD_LEFT);
    
    // Get student details from database (student_id will come from login
    $student_id = (int)$data['student_id'];
    // Step 1: Find ANY user with this ID
    $check_user_query = "SELECT id, username, full_name, role FROM users WHERE id = ?";
    $check_user_stmt = $conn->prepare($check_user_query);
    $check_user_stmt->bind_param("i", $student_id);
    $check_user_stmt->execute();
    $user_result = $check_user_stmt->get_result();
    
    // Fallback Step 1.5: If not found by ID (maybe it's a username?), find ANY user with this username
    if ($user_result->num_rows === 0) {
        $username_query = "SELECT id, username, full_name, role FROM users WHERE username = ?";
        $username_stmt = $conn->prepare($username_query);
        $username_stmt->bind_param("s", $data['student_id']);
        $username_stmt->execute();
        $user_result = $username_stmt->get_result();
        file_put_contents('debug_submit.log', date('[Y-m-d H:i:s] ') . "Fallback username check for '" . $data['student_id'] . "'. Found rows: " . $user_result->num_rows . "\n", FILE_APPEND);
    }
    
    if ($user_result->num_rows === 0) {
        throw new Exception("Student not found (ID/RegNo '" . $data['student_id'] . "' does not exist in users table)");
    }
    
    $student_data = $user_result->fetch_assoc();
    $student_id = (int)$student_data['id']; // Update to real integer ID
    
    // Step 2: Validate ROLE
    if ($student_data['role'] !== 'student') {
        throw new Exception("Access Denied: User role is '" . $student_data['role'] . "', but only students can submit room change requests.");
    }
    
    // Step 2.5: Warden Assignment Validation
    $has_warden = true; // Allow room transfer request for mapped hostels
    $destination_hostel = $data['destination_hostel'] ?? '';
    if (!empty($destination_hostel)) {
        $staff_check = $conn->query("SELECT id FROM mapping_staff WHERE LOWER(TRIM(role)) = 'warden' AND LOWER(TRIM(hostel_name)) LIKE '%" . strtolower(trim($conn->real_escape_string($destination_hostel))) . "%' LIMIT 1");
        if ($staff_check && $staff_check->num_rows > 0) {
            $has_warden = true;
        }
    }
    
    // Use full_name for student_name, and username for reg_no (fallback)
    $student_name = $student_data['full_name'] ?? $student_data['username'] ?? 'Unknown';
    $student_reg_no = $student_data['username'] ?? 'N/A';
    
    // Check if student already has a pending request
    $check_query = "SELECT id FROM room_change_requests WHERE student_id = ? AND status = 'pending'";
    $check_stmt = $conn->prepare($check_query);
    $check_stmt->bind_param("i", $student_id);
    $check_stmt->execute();
    $check_result = $check_stmt->get_result();
    
    if ($check_result->num_rows > 0) {
        throw new Exception('You already have a pending room change request');
    }
    
    $requested_room_type = $data['requested_room_type'] ?? 'Standard';
    $target_room_code = trim($data['requested_room'] ?? '');
    if (empty($target_room_code) || $target_room_code === '0' || $target_room_code === 'null') {
        $target_room_code = $requested_room_type;
    }
    $amount_to_pay = isset($data['amount_to_pay']) ? (float)$data['amount_to_pay'] : (isset($data['upgrade_fee']) ? (float)$data['upgrade_fee'] : 0.00);
    if ($amount_to_pay < 0) $amount_to_pay = 0.00;

    // Insert the room change request into database
    $insert_query = "INSERT INTO room_change_requests (
        request_id, student_id, student_name, student_reg_no, 
        current_room, requested_room, requested_room_type, amount_to_pay, reason, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')";
    
    $insert_stmt = $conn->prepare($insert_query);
    $insert_stmt->bind_param(
        "sisssdsss", 
        $request_id, 
        $student_id, 
        $student_name, 
        $student_reg_no, 
        $data['current_room'], 
        $target_room_code, 
        $requested_room_type,
        $amount_to_pay,
        $data['reason']
    );
    
    if (!$insert_stmt->execute()) {
        throw new Exception('Failed to submit room change request');
    }
    
    logAudit(
        $student_id,
        $student_reg_no,
        'student',
        'REQUEST_CREATE',
        'Room Change Requests',
        null,
        [
            'request_id' => $request_id,
            'current_room' => $data['current_room'],
            'requested_room' => $data['requested_room'],
            'requested_room_type' => $requested_room_type,
            'reason' => $data['reason'],
            'status' => 'pending'
        ]
    );
    
    // Get the inserted request details
    $request_details = [
        'request_id' => $request_id,
        'student_id' => $student_id,
        'student_name' => $student_name,
        'student_reg_no' => $student_reg_no,
        'current_room' => $data['current_room'],
        'requested_room' => $data['requested_room'],
        'requested_room_type' => $requested_room_type,
        'reason' => $data['reason'],
        'status' => 'pending',
        'created_at' => date('Y-m-d H:i:s')
    ];
    
    echo json_encode([
        'success' => true,
        'status' => 'success',
        'message' => 'Room change request submitted successfully',
        'data' => $request_details
    ]);
    
} catch(mysqli_sql_exception $e) {
    http_response_code(400);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
} catch(Exception $e) {
    http_response_code(400);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}
?>
