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
    // Fetch requested room location details
    $loc_query = "SELECT hr.hostel_name, hr.floor, hr.wing_code
                  FROM hostel_rooms hr 
                  WHERE hr.room_code = ? LIMIT 1";
    $loc_stmt = $conn->prepare($loc_query);
    $loc_stmt->bind_param("s", $data['requested_room']);
    $loc_stmt->execute();
    $loc_result = $loc_stmt->get_result();
    
    $has_warden = false;
    if ($loc_result->num_rows > 0) {
        $location = $loc_result->fetch_assoc();
        $h_name = $location['hostel_name'];
        $f_name = $location['floor'];
        $w_name = $location['wing_code'];
        
        // Search for matching floorwise warden in mapping_staff
        $staff_query = "SELECT ms.name, ms.username 
                        FROM mapping_staff ms
                        WHERE LOWER(TRIM(ms.role)) COLLATE utf8mb4_general_ci = 'warden' COLLATE utf8mb4_general_ci
                        AND (
                            LOWER(TRIM(ms.hostel_name)) COLLATE utf8mb4_general_ci = LOWER(TRIM(?)) COLLATE utf8mb4_general_ci
                            OR LOWER(TRIM(ms.hostel_name)) COLLATE utf8mb4_general_ci LIKE CONCAT('%', LOWER(TRIM(?)) COLLATE utf8mb4_general_ci, '%')
                            OR LOWER(TRIM(?)) COLLATE utf8mb4_general_ci LIKE CONCAT('%', LOWER(TRIM(ms.hostel_name)) COLLATE utf8mb4_general_ci, '%')
                            OR ms.hostel_name IS NULL OR ms.hostel_name = ''
                        )
                        AND (
                            LOWER(TRIM(ms.floor_name)) COLLATE utf8mb4_general_ci = LOWER(TRIM(?)) COLLATE utf8mb4_general_ci
                            OR (? COLLATE utf8mb4_general_ci IN ('f00', 'ground', 'ground floor') AND LOWER(TRIM(ms.floor_name)) COLLATE utf8mb4_general_ci IN ('f00', 'ground', 'ground floor'))
                            OR (? COLLATE utf8mb4_general_ci IN ('f01', '1st floor') AND LOWER(TRIM(ms.floor_name)) COLLATE utf8mb4_general_ci IN ('f01', '1st floor'))
                            OR (? COLLATE utf8mb4_general_ci IN ('f02', '2nd floor') AND LOWER(TRIM(ms.floor_name)) COLLATE utf8mb4_general_ci IN ('f02', '2nd floor'))
                            OR (? COLLATE utf8mb4_general_ci IN ('f03', '3rd floor') AND LOWER(TRIM(ms.floor_name)) COLLATE utf8mb4_general_ci IN ('f03', '3rd floor'))
                            OR (? COLLATE utf8mb4_general_ci IN ('f04', '4th floor', 'fourth') AND LOWER(TRIM(ms.floor_name)) COLLATE utf8mb4_general_ci IN ('f04', '4th floor', 'fourth'))
                            OR ms.floor_name IS NULL OR ms.floor_name = ''
                        )
                        AND (LOWER(TRIM(ms.wing_name)) COLLATE utf8mb4_general_ci = LOWER(TRIM(?)) COLLATE utf8mb4_general_ci OR ms.wing_name IS NULL OR ms.wing_name = '')
                        ORDER BY 
                            (CASE WHEN LOWER(TRIM(ms.wing_name)) COLLATE utf8mb4_general_ci = LOWER(TRIM(?)) COLLATE utf8mb4_general_ci THEN 10 ELSE 0 END) +
                            (CASE WHEN LOWER(TRIM(ms.floor_name)) COLLATE utf8mb4_general_ci = LOWER(TRIM(?)) COLLATE utf8mb4_general_ci 
                                  OR (? COLLATE utf8mb4_general_ci IN ('f00', 'ground') AND LOWER(TRIM(ms.floor_name)) COLLATE utf8mb4_general_ci IN ('f00', 'ground'))
                                  OR (? COLLATE utf8mb4_general_ci IN ('f01', '1st floor') AND LOWER(TRIM(ms.floor_name)) COLLATE utf8mb4_general_ci IN ('f01', '1st floor'))
                                  THEN 5 ELSE 0 END) +
                            (CASE WHEN LOWER(TRIM(ms.hostel_name)) COLLATE utf8mb4_general_ci = LOWER(TRIM(?)) COLLATE utf8mb4_general_ci THEN 1 ELSE 0 END) DESC
                        LIMIT 1";
        
        $staff_stmt = $conn->prepare($staff_query);
        $staff_stmt->bind_param(
            "sssssssssssssss",
            $h_name, $h_name, $h_name,
            $f_name, $f_name, $f_name, $f_name, $f_name, $f_name,
            $w_name, $w_name,
            $f_name, $f_name, $f_name,
            $h_name
        );
        $staff_stmt->execute();
        $staff_result = $staff_stmt->get_result();
        if ($staff_result->num_rows > 0) {
            $has_warden = true;
        }
    }
    
    if (!$has_warden) {
        throw new Exception('Warden not assigned. You cannot request a room change until a floorwise warden is assigned.');
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
    
    // Insert the room change request into database
    $insert_query = "INSERT INTO room_change_requests (
        request_id, student_id, student_name, student_reg_no, 
        current_room, requested_room, requested_room_type, reason, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending')";
    
    $insert_stmt = $conn->prepare($insert_query);
    $requested_room_type = $data['requested_room_type'] ?? 'Standard';
    $insert_stmt->bind_param(
        "sissssss", 
        $request_id, 
        $student_id, 
        $student_name, 
        $student_reg_no, 
        $data['current_room'], 
        $data['requested_room'], 
        $requested_room_type,
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
