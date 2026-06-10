<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
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

if (!$conn) {
    echo json_encode(array("status" => "error", "success" => false, "message" => "Database connection failed"));
    exit();
}

$data = json_decode(file_get_contents("php://input"), true);

if (!isset($data['student_id'])) {
    echo json_encode(array("status" => "error", "success" => false, "message" => "Student ID is required"));
    $conn->close();
    exit();
}

$student_id = (int)$data['student_id'];

$conn->begin_transaction();

try {
    // 1. Get the registration number (username) of the student
    $user_stmt = $conn->prepare("SELECT username FROM users WHERE id = ?");
    $user_stmt->bind_param("i", $student_id);
    $user_stmt->execute();
    $user_res = $user_stmt->get_result();
    
    if ($user_res->num_rows === 0) {
        throw new Exception("Student user account not found");
    }
    
    $user_row = $user_res->fetch_assoc();
    $reg_no = $user_row['username'];
    
    // 2. Fetch current allocation details from the student's profile
    $profile_stmt = $conn->prepare("SELECT room_allocation, current_room_id FROM profile WHERE reg_no = ?");
    $profile_stmt->bind_param("s", $reg_no);
    $profile_stmt->execute();
    $profile_res = $profile_stmt->get_result();
    
    $room_allocation = null;
    $current_room_id = null;
    
    if ($profile_res->num_rows > 0) {
        $profile_row = $profile_res->fetch_assoc();
        $room_allocation = $profile_row['room_allocation'];
        $current_room_id = $profile_row['current_room_id'];
    }

    // 3. Decrement occupied_rooms in hostel_rooms if an allocation existed
    if ($room_allocation && $room_allocation !== 'unallocated') {
        $update_room_sql = "UPDATE hostel_rooms 
                            SET occupied_rooms = GREATEST(0, occupied_rooms - 1), 
                                available_rooms = LEAST(total_capacity, available_rooms + 1) 
                            WHERE room_code = ?";
        $room_stmt = $conn->prepare($update_room_sql);
        $room_stmt->bind_param("s", $room_allocation);
        $room_stmt->execute();
    } elseif ($current_room_id && $current_room_id > 0) {
        $update_room_sql = "UPDATE hostel_rooms 
                            SET occupied_rooms = GREATEST(0, occupied_rooms - 1), 
                                available_rooms = LEAST(total_capacity, available_rooms + 1) 
                            WHERE id = ?";
        $room_stmt = $conn->prepare($update_room_sql);
        $room_stmt->bind_param("i", $current_room_id);
        $room_stmt->execute();
    }

    // 4. Update the profile table to clear room allocations
    $clear_profile_sql = "UPDATE profile 
                          SET current_room_id = NULL, 
                              room_allocation = NULL, 
                              hostel_name = NULL 
                          WHERE reg_no = ?";
    $clear_prof_stmt = $conn->prepare($clear_profile_sql);
    $clear_prof_stmt->bind_param("s", $reg_no);
    $clear_prof_stmt->execute();

    // 5. Mark active room allocations entries as checked out
    $update_alloc_sql = "UPDATE room_allocations 
                         SET allocation_status = 'checked_out' 
                         WHERE student_id = ? AND allocation_status IN ('approved', 'payment_pending')";
    $alloc_stmt = $conn->prepare($update_alloc_sql);
    $alloc_stmt->bind_param("i", $student_id);
    $alloc_stmt->execute();

    $conn->commit();
    
    $previous_state = json_encode(['room_allocation' => $room_allocation, 'current_room_id' => $current_room_id]);
    $after_state = json_encode(['room_allocation' => null, 'current_room_id' => null]);
    
    logActivity(
        $data['warden_id'] ?? null,
        $data['warden_username'] ?? 'warden',
        'warden',
        'DEALLOCATE_STUDENT',
        'profile & room_allocations',
        $previous_state,
        $after_state
    );

    echo json_encode(array("status" => "success", "success" => true, "message" => "Student deallocated and checked out successfully"));

} catch (Exception $e) {
    $conn->rollback();
    echo json_encode(array("status" => "error", "success" => false, "message" => "Deallocation failed: " . $e->getMessage()));
} finally {
    $conn->close();
}
?>
