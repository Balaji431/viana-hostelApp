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

$database = new DatabaseMysqli();
$conn = $database->getConnection();

$method = $_SERVER['REQUEST_METHOD'];

try {
    if ($method !== 'POST') {
        throw new Exception("Only POST requests allowed");
    }

    $data = json_decode(file_get_contents('php://input'), true);
    $student_id = isset($data['student_id']) ? (int)$data['student_id'] : 0;

    if ($student_id <= 0) {
        throw new Exception("Student ID is required");
    }

    // 1. Fetch student's current allocation record
    $alloc_query = "SELECT id, allocation_status FROM room_allocations WHERE student_id = ?";
    $stmt = $conn->prepare($alloc_query);
    $stmt->bind_param("i", $student_id);
    $stmt->execute();
    $alloc = $stmt->get_result()->fetch_assoc();

    if (!$alloc) {
        throw new Exception("No active room allocation request found for this student");
    }

    if ($alloc['allocation_status'] !== 'submitted' && $alloc['allocation_status'] !== 'under_review') {
        throw new Exception("Allocation is already in state: " . $alloc['allocation_status']);
    }

    // 2. Fetch the 2nd priority room preference
    $pref_query = "SELECT rp.room_id, hr.amount, hr.room_no, hr.building_code, hr.floor, hr.total_capacity, hr.occupied_rooms,
                   (SELECT COUNT(*) FROM room_allocations WHERE allocated_room_id = hr.id AND allocation_status = 'payment_pending' AND payment_deadline > NOW()) as hold_count
                   FROM room_preferences rp
                   JOIN hostel_rooms hr ON rp.room_id = hr.id
                   WHERE rp.student_id = ? AND rp.priority_order = 2 LIMIT 1";
    $stmt = $conn->prepare($pref_query);
    $stmt->bind_param("i", $student_id);
    $stmt->execute();
    $pref = $stmt->get_result()->fetch_assoc();

    if (!$pref) {
        throw new Exception("You do not have a 2nd priority room preference added.");
    }

    $room_id = (int)$pref['room_id'];
    $capacity = (int)$pref['total_capacity'];
    $occupied = (int)$pref['occupied_rooms'];
    $holds = (int)$pref['hold_count'];

    // 3. Capacity Guard for 2nd Priority Room
    if (($occupied + $holds) >= $capacity) {
        throw new Exception("Unfortunately, your 2nd priority Room " . $pref['room_no'] . " is also full or reserved.");
    }

    // 4. Update the student's allocation to payment_pending on the 2nd priority room!
    $conn->begin_transaction();
    try {
        $now = new DateTime();
        $now_str = $now->format('Y-m-d H:i:s');
        
        $deadline = clone $now;
        $deadline->modify('+24 hours');
        $deadline_str = $deadline->format('Y-m-d H:i:s');

        // We use warden_id = 1 (System / Admin) as the approver
        $update_query = "UPDATE room_allocations 
                         SET allocated_room_id = ?, 
                             allocation_status = 'payment_pending', 
                             payment_deadline = ?,
                             approved_by = 1,
                             approved_at = ?,
                             notified_of_conflict = 0
                         WHERE student_id = ?";
        $up_stmt = $conn->prepare($update_query);
        $up_stmt->bind_param("issi", $room_id, $deadline_str, $now_str, $student_id);
        $up_stmt->execute();

        $conn->commit();
        echo json_encode([
            "success" => true, 
            "message" => "Successfully continued to 2nd Priority Room! Your 24-hour payment window is active.",
            "room_no" => $pref['room_no'],
            "deadline" => $deadline_str
        ]);
    } catch (Exception $e) {
        $conn->rollback();
        throw $e;
    }

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
?>
