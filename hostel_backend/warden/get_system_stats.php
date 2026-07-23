<?php
header('Access-Control-Allow-Origin: *');
header('Content-Type: application/json');

require_once '../config/database.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

try {
    // 1. Room Stats
    $room_query = "SELECT 
                    COUNT(*) as total_rooms, 
                    SUM(total_capacity) as total_capacity, 
                    SUM(occupied_rooms) as total_occupied, 
                    SUM(available_rooms) as total_available 
                   FROM hostel_rooms";
    $room_res = $conn->query($room_query)->fetch_assoc();
    
    // 2. Student Count
    $student_query = "SELECT COUNT(*) as total_students FROM users WHERE role = 'student'";
    $student_res = $conn->query($student_query)->fetch_assoc();
    
    // 3. Pending Room Change Requests
    $pending_rc_query = "SELECT COUNT(*) as pending_room_changes FROM room_change_requests WHERE status = 'pending'";
    $pending_rc_res = $conn->query($pending_rc_query)->fetch_assoc();
    
    // 4. Pending Renewals (Assuming status 'pending' in a renewal table or similar)
    // Looking at common table names in previous context
    $pending_ren_query = "SELECT COUNT(*) as pending_renewals FROM renewal_requests WHERE status = 'pending'";
    $pending_ren_res = @$conn->query($pending_ren_query);
    $pending_renewals = $pending_ren_res ? $pending_ren_res->fetch_assoc()['pending_renewals'] : 0;
    
    echo json_encode([
        'success' => true,
        'data' => [
            'total_rooms' => (int)$room_res['total_rooms'],
            'total_capacity' => (int)$room_res['total_capacity'],
            'total_occupied' => (int)$room_res['total_occupied'],
            'total_available' => (int)$room_res['total_available'],
            'total_students' => (int)$student_res['total_students'],
            'pending_room_changes' => (int)$pending_rc_res['pending_room_changes'],
            'pending_renewals' => (int)$pending_renewals
        ]
    ]);

} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage()
    ]);
}
?>
