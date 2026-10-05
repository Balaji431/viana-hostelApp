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
require_once '../utils/auth_helper.php';

$authUser = requireAuth(['warden', 'admin', 'super_admin']);

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

// Create table if it doesn't exist
$conn->query("CREATE TABLE IF NOT EXISTS checkout_students (
    id INT AUTO_INCREMENT PRIMARY KEY,
    student_id INT NOT NULL,
    reg_no VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    hostel_name VARCHAR(255) NULL,
    room_code VARCHAR(255) NULL,
    conduct VARCHAR(255) NULL,
    conduct_remarks TEXT NULL,
    checked_out_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    checked_out_by VARCHAR(255) NULL,
    profile_data TEXT NULL,
    user_data TEXT NULL
)");

$conn->begin_transaction();

try {
    // 1. Fetch user account details
    $user_stmt = $conn->prepare("SELECT * FROM users WHERE id = ?");
    $user_stmt->bind_param("i", $student_id);
    $user_stmt->execute();
    $user_row = $user_stmt->get_result()->fetch_assoc();
    
    if (!$user_row) {
        throw new Exception("Student user account not found");
    }
    
    $reg_no = $user_row['username'];
    $conduct = $user_row['conduct'] ?? 'Good';
    $conduct_remarks = $user_row['conduct_remarks'] ?? '';
    
    // 2. Fetch profile details
    $profile_stmt = $conn->prepare("SELECT * FROM profile WHERE reg_no = ?");
    $profile_stmt->bind_param("s", $reg_no);
    $profile_stmt->execute();
    $profile_row = $profile_stmt->get_result()->fetch_assoc();
    
    $full_name = $profile_row ? ($profile_row['full_name'] ?? 'Unknown') : 'Unknown';
    $room_allocation = $profile_row ? ($profile_row['room_allocation'] ?? null) : null;
    $current_room_id = $profile_row ? ($profile_row['current_room_id'] ?? null) : null;
    $hostel_name = $profile_row ? ($profile_row['hostel_name'] ?? null) : null;

    // 3. Insert into checkout_students
    $warden_user = $authUser['username'] ?? 'warden';
    $profile_json = json_encode($profile_row);
    $user_json = json_encode($user_row);
    
    $insert_stmt = $conn->prepare("INSERT INTO checkout_students (student_id, reg_no, full_name, hostel_name, room_code, conduct, conduct_remarks, checked_out_by, profile_data, user_data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
    $insert_stmt->bind_param("isssssssss", $student_id, $reg_no, $full_name, $hostel_name, $room_allocation, $conduct, $conduct_remarks, $warden_user, $profile_json, $user_json);
    if (!$insert_stmt->execute()) {
        throw new Exception("Failed to record checkout information: " . $insert_stmt->error);
    }

    // 4. Decrement occupied_rooms in hostel_rooms and rooms_groups_details if an allocation existed
    if ($room_allocation && $room_allocation !== 'unallocated') {
        $update_room_sql = "UPDATE hostel_rooms 
                            SET occupied_rooms = GREATEST(0, occupied_rooms - 1), 
                                available_rooms = LEAST(total_capacity, available_rooms + 1) 
                            WHERE room_code = ?";
        $room_stmt = $conn->prepare($update_room_sql);
        $room_stmt->bind_param("s", $room_allocation);
        $room_stmt->execute();

        $update_rgd_sql = "UPDATE rooms_groups_details 
                           SET occupied_beds = GREATEST(0, occupied_beds - 1), 
                               available_beds = LEAST(total_beds, available_beds + 1) 
                           WHERE TRIM(room_number) = TRIM(?)";
        $rgd_stmt = $conn->prepare($update_rgd_sql);
        $rgd_stmt->bind_param("s", $room_allocation);
        $rgd_stmt->execute();
    } elseif ($current_room_id && $current_room_id > 0) {
        $update_room_sql = "UPDATE hostel_rooms 
                            SET occupied_rooms = GREATEST(0, occupied_rooms - 1), 
                                available_rooms = LEAST(total_capacity, available_rooms + 1) 
                            WHERE id = ?";
        $room_stmt = $conn->prepare($update_room_sql);
        $room_stmt->bind_param("i", $current_room_id);
        $room_stmt->execute();
    }

    // 5. Delete records from all student-related tables
    // users
    $stmt1 = $conn->prepare("DELETE FROM users WHERE id = ?");
    $stmt1->bind_param("i", $student_id);
    $stmt1->execute();
    
    // profile
    $stmt2 = $conn->prepare("DELETE FROM profile WHERE reg_no = ?");
    $stmt2->bind_param("s", $reg_no);
    $stmt2->execute();
    
    // allocation_requests
    $stmt3 = $conn->prepare("DELETE FROM allocation_requests WHERE student_id = ? OR student_reg_no = ?");
    $stmt3->bind_param("is", $student_id, $reg_no);
    $stmt3->execute();
    
    // room_change_requests
    $stmt4 = $conn->prepare("DELETE FROM room_change_requests WHERE student_id = ? OR student_reg_no = ?");
    $stmt4->bind_param("is", $student_id, $reg_no);
    $stmt4->execute();
    
    // chat_messages
    $stmt5 = $conn->prepare("DELETE FROM chat_messages WHERE sender_id = ? OR receiver_id = ?");
    $stmt5->bind_param("ss", $reg_no, $reg_no);
    $stmt5->execute();
    
    // complaints
    $stmt6 = $conn->prepare("DELETE FROM complaints WHERE student_id = ?");
    $stmt6->bind_param("i", $student_id);
    $stmt6->execute();
    
    // feedbacks
    $stmt7 = $conn->prepare("DELETE FROM feedbacks WHERE student_id = ?");
    $stmt7->bind_param("i", $student_id);
    $stmt7->execute();
    
    // attendance
    $stmt8 = $conn->prepare("DELETE FROM attendance WHERE student_id = ?");
    $stmt8->bind_param("i", $student_id);
    $stmt8->execute();
    
    // parent_student_map
    $stmt9 = $conn->prepare("DELETE FROM parent_student_map WHERE student_id = ?");
    $stmt9->bind_param("s", $reg_no);
    $stmt9->execute();
    
    // payments
    $stmt10 = $conn->prepare("DELETE FROM payments WHERE student_id = ? OR reg_number = ? OR user_id = ?");
    $stmt10->bind_param("isi", $student_id, $reg_no, $student_id);
    $stmt10->execute();
    
    // renewal_requests
    $stmt11 = $conn->prepare("DELETE FROM renewal_requests WHERE student_id = ? OR student_reg_no = ?");
    $stmt11->bind_param("is", $student_id, $reg_no);
    $stmt11->execute();
    
    // room_preferences
    $stmt12 = $conn->prepare("DELETE FROM room_preferences WHERE student_id = ?");
    $stmt12->bind_param("i", $student_id);
    $stmt12->execute();

    $conn->commit();
    
    logActivity(
        $data['warden_id'] ?? null,
        $data['warden_username'] ?? 'warden',
        'warden',
        'DEALLOCATE_STUDENT',
        'profile & users & allocations deleted',
        json_encode(['reg_no' => $reg_no, 'name' => $full_name]),
        json_encode(['status' => 'fully_checked_out_and_archived'])
    );

    echo json_encode(array("status" => "success", "success" => true, "message" => "Student checked out successfully and records archived"));

} catch (Exception $e) {
    $conn->rollback();
    echo json_encode(array("status" => "error", "success" => false, "message" => "Checkout failed: " . $e->getMessage()));
} finally {
    $conn->close();
}
?>
