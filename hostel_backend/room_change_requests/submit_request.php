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
    
    // Get student details from database
    $student_id = (int)$data['student_id'];
    
    // Step 1: Find user with this ID
    $check_user_query = "SELECT id, username, full_name, role, RoomType FROM users WHERE id = ?";
    $check_user_stmt = $conn->prepare($check_user_query);
    $check_user_stmt->bind_param("i", $student_id);
    $check_user_stmt->execute();
    $user_result = $check_user_stmt->get_result();
    
    // Fallback Step 1.5: If not found by ID, find user with this username
    if ($user_result->num_rows === 0) {
        $username_query = "SELECT id, username, full_name, role, RoomType FROM users WHERE username = ?";
        $username_stmt = $conn->prepare($username_query);
        $username_stmt->bind_param("s", $data['student_id']);
        $username_stmt->execute();
        $user_result = $username_stmt->get_result();
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
    $has_warden = true;
    $destination_hostel = $data['destination_hostel'] ?? '';
    if (!empty($destination_hostel)) {
        $staff_check = $conn->query("SELECT id FROM mapping_staff WHERE LOWER(TRIM(role)) = 'warden' AND LOWER(TRIM(hostel_name)) LIKE '%" . strtolower(trim($conn->real_escape_string($destination_hostel))) . "%' LIMIT 1");
        if ($staff_check && $staff_check->num_rows > 0) {
            $has_warden = true;
        }
    }
    
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
    
    // =========================================================================
    // 🔒 SERVER-SIDE AUTHORITATIVE FEE CALCULATION
    // =========================================================================
    
    // 1. Resolve Student's Current Room Type and Current Paid Amount from DB
    $curr_room_stmt = $conn->prepare("
        SELECT 
            p.room_allocation,
            p.hostel_name,
            u.RoomType as u_room_type,
            rgd.room_type as rgd_room_type,
            rgd.amount as rgd_amount
        FROM users u
        LEFT JOIN profile p ON u.username = p.reg_no
        LEFT JOIN rooms_groups_details rgd ON (
            TRIM(rgd.room_number) = TRIM(p.room_allocation) 
            OR REPLACE(REPLACE(TRIM(rgd.room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(p.room_allocation), ' ', ''), '-', '')
        )
        WHERE u.id = ?
        LIMIT 1
    ");
    $curr_room_stmt->bind_param("i", $student_id);
    $curr_room_stmt->execute();
    $curr_row = $curr_room_stmt->get_result()->fetch_assoc();

    $current_room_type = trim($curr_row['rgd_room_type'] ?? $curr_row['u_room_type'] ?? '');
    $current_paid_amount = (float)($curr_row['rgd_amount'] ?? 0.0);

    // Fallback if current amount is 0: look up from rooms_groups_details by current room type name
    if ($current_paid_amount <= 0 && !empty($current_room_type)) {
        $amt_stmt = $conn->prepare("SELECT MAX(amount) as amt FROM rooms_groups_details WHERE LOWER(TRIM(room_type)) = LOWER(TRIM(?)) AND amount > 0");
        $amt_stmt->bind_param("s", $current_room_type);
        $amt_stmt->execute();
        $amt_row = $amt_stmt->get_result()->fetch_assoc();
        if ($amt_row && $amt_row['amt'] > 0) {
            $current_paid_amount = (float)$amt_row['amt'];
        }
    }

    // 2. Resolve New Requested Room Type and New Room Amount from DB
    $requested_room_type = trim($data['requested_room_type'] ?? '');
    $target_room_code = trim($data['requested_room'] ?? '');
    $new_room_amount = 0.0;

    // Check by specific physical room number first
    if (!empty($target_room_code) && $target_room_code !== '0' && $target_room_code !== 'null') {
        $new_stmt = $conn->prepare("
            SELECT room_type, amount 
            FROM rooms_groups_details 
            WHERE TRIM(room_number) = TRIM(?) 
               OR REPLACE(REPLACE(TRIM(room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(?), ' ', ''), '-', '')
            LIMIT 1
        ");
        $new_stmt->bind_param("ss", $target_room_code, $target_room_code);
        $new_stmt->execute();
        $new_row = $new_stmt->get_result()->fetch_assoc();
        if ($new_row) {
            $new_room_amount = (float)($new_row['amount'] ?? 0.0);
            if (empty($requested_room_type)) {
                $requested_room_type = trim($new_row['room_type'] ?? '');
            }
        }
    }

    // If amount is still 0, look up by requested room type name
    if ($new_room_amount <= 0 && !empty($requested_room_type)) {
        $new_type_stmt = $conn->prepare("
            SELECT MAX(amount) as amt 
            FROM rooms_groups_details 
            WHERE LOWER(TRIM(room_type)) = LOWER(TRIM(?)) AND amount > 0
        ");
        $new_type_stmt->bind_param("s", $requested_room_type);
        $new_type_stmt->execute();
        $new_type_row = $new_type_stmt->get_result()->fetch_assoc();
        if ($new_type_row && $new_type_row['amt'] > 0) {
            $new_room_amount = (float)$new_type_row['amt'];
        }
    }

    if (empty($requested_room_type)) {
        $requested_room_type = 'Standard Room';
    }
    if (empty($target_room_code) || $target_room_code === '0' || $target_room_code === 'null') {
        $target_room_code = $requested_room_type;
    }

    // 3. Exact Fee Formula:
    // IF new_room_amount > current_paid_amount: Extra Fee = new_room_amount - current_paid_amount
    // ELSE: Extra Fee = 0.00
    // Strictly disallow negative fees, refunds, and charging full price.
    $amount_to_pay = ($new_room_amount > $current_paid_amount) ? ($new_room_amount - $current_paid_amount) : 0.00;

    // Insert the room change request into database
    $insert_query = "INSERT INTO room_change_requests (
        request_id, student_id, student_name, student_reg_no, 
        current_room, requested_room, requested_room_type, amount_to_pay, reason, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')";
    
    $insert_stmt = $conn->prepare($insert_query);
    $insert_stmt->bind_param(
        "sisssssds", 
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
            'current_room_type' => $current_room_type,
            'current_paid_amount' => $current_paid_amount,
            'requested_room' => $target_room_code,
            'requested_room_type' => $requested_room_type,
            'new_room_amount' => $new_room_amount,
            'amount_to_pay' => $amount_to_pay,
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
        'current_room_type' => $current_room_type,
        'current_paid_amount' => $current_paid_amount,
        'requested_room' => $target_room_code,
        'requested_room_type' => $requested_room_type,
        'new_room_amount' => $new_room_amount,
        'amount_to_pay' => $amount_to_pay,
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
