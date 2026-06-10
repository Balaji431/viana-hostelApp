<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, DELETE, PUT, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

require_once __DIR__ . '/expire_holds.php';

$method = $_SERVER['REQUEST_METHOD'];
$student_id = isset($_GET['student_id']) ? (int)$_GET['student_id'] : 0;

if ($student_id <= 0) {
    echo json_encode(["success" => false, "message" => "Student ID required"]);
    exit();
}

try {
    if ($method === 'GET') {
        // 1. Get current allocation status with room details if applicable
        $alloc_query = "SELECT ra.*, hr.room_no, hr.building_code, hr.floor, hr.room_type, hr.facility, hr.amount
                        FROM room_allocations ra
                        LEFT JOIN hostel_rooms hr ON ra.allocated_room_id = hr.id
                        WHERE ra.student_id = ?";
        $stmt = $conn->prepare($alloc_query);
        $stmt->bind_param("i", $student_id);
        $stmt->execute();
        $allocation = $stmt->get_result()->fetch_assoc();

        // 2. Get preferences
        $pref_query = "SELECT rp.*, hr.room_no, hr.building_code, hr.floor, hr.room_type, hr.facility, hr.amount
                       FROM room_preferences rp
                       JOIN hostel_rooms hr ON rp.room_id = hr.id
                       WHERE rp.student_id = ?
                       ORDER BY rp.priority_order ASC";
        $stmt = $conn->prepare($pref_query);
        $stmt->bind_param("i", $student_id);
        $stmt->execute();
        $result = $stmt->get_result();
        
        $preferences = [];
        while ($row = $result->fetch_assoc()) {
            $preferences[] = $row;
        }

        $first_priority_held_by_pending = false;
        $has_second_priority = false;

        if (count($preferences) > 0) {
            $first_pref = $preferences[0];
            $first_room_id = (int)$first_pref['room_id'];

            $cap_query = "SELECT total_capacity, occupied_rooms,
                          (SELECT COUNT(*) FROM room_allocations WHERE allocated_room_id = hr.id AND allocation_status = 'payment_pending' AND payment_deadline > NOW()) as hold_count
                          FROM hostel_rooms hr
                          WHERE id = ?";
            $cap_stmt = $conn->prepare($cap_query);
            $cap_stmt->bind_param("i", $first_room_id);
            $cap_stmt->execute();
            $room_cap = $cap_stmt->get_result()->fetch_assoc();

            if ($allocation && isset($allocation['notified_of_conflict']) && (int)$allocation['notified_of_conflict'] === 1) {
                $first_priority_held_by_pending = true;
            }

            if (count($preferences) > 1) {
                $has_second_priority = true;
            }
        }

        echo json_encode([
            "success" => true, 
            "allocation" => $allocation,
            "preferences" => $preferences,
            "first_priority_held_by_pending" => $first_priority_held_by_pending,
            "has_second_priority" => $has_second_priority
        ]);

    } elseif ($method === 'POST') {
        $data = json_decode(file_get_contents('php://input'), true);
        $room_id = (int)($data['room_id'] ?? 0);

        // Check if already submitted
        $check_sub = "SELECT allocation_status FROM room_allocations WHERE student_id = ?";
        $stmt = $conn->prepare($check_sub);
        $stmt->bind_param("i", $student_id);
        $stmt->execute();
        $status_row = $stmt->get_result()->fetch_assoc();
        
        if ($status_row && !in_array($status_row['allocation_status'], ['draft', 'none', 'rejected', 'payment_expired'])) {
            throw new Exception("Cannot modify preferences after submission");
        }

        // Check count
        $count_res = $conn->query("SELECT COUNT(*) as count FROM room_preferences WHERE student_id = $student_id");
        $count = $count_res->fetch_assoc()['count'];
        if ($count >= 5) throw new Exception("Maximum 5 preferences allowed");

        // Check duplicate
        $dup_res = $conn->query("SELECT id FROM room_preferences WHERE student_id = $student_id AND room_id = $room_id");
        if ($dup_res->num_rows > 0) throw new Exception("Room already in preferences");

        $priority = $count + 1;
        $ins = $conn->prepare("INSERT INTO room_preferences (student_id, room_id, priority_order) VALUES (?, ?, ?)");
        $ins->bind_param("iii", $student_id, $room_id, $priority);
        $ins->execute();

        echo json_encode(["success" => true, "message" => "Preference added"]);

    } elseif ($method === 'DELETE') {
        $room_id = (int)($_GET['room_id'] ?? 0);
        
        // Check if draft
        $check_sub = "SELECT allocation_status FROM room_allocations WHERE student_id = ?";
        $stmt = $conn->prepare($check_sub);
        $stmt->bind_param("i", $student_id);
        $stmt->execute();
        $status_row = $stmt->get_result()->fetch_assoc();
        if ($status_row && !in_array($status_row['allocation_status'], ['draft', 'none', 'rejected', 'payment_expired'])) {
            throw new Exception("Cannot delete after submission");
        }

        $conn->query("DELETE FROM room_preferences WHERE student_id = $student_id AND room_id = $room_id");
        
        // Re-number
        $res = $conn->query("SELECT id FROM room_preferences WHERE student_id = $student_id ORDER BY priority_order ASC");
        $p = 1;
        while ($row = $res->fetch_assoc()) {
            $conn->query("UPDATE room_preferences SET priority_order = $p WHERE id = {$row['id']}");
            $p++;
        }

        echo json_encode(["success" => true, "message" => "Preference removed"]);

    } elseif ($method === 'PUT') {
        // Reorder
        $data = json_decode(file_get_contents('php://input'), true);
        $priorities = $data['priorities'] ?? []; 

        $conn->begin_transaction();
        try {
            // Step 1: Set to temporary values to avoid unique constraint collisions
            foreach ($priorities as $item) {
                $rid = (int)$item['room_id'];
                $temp_up = $conn->prepare("UPDATE room_preferences SET priority_order = priority_order + 100 WHERE student_id = ? AND room_id = ?");
                $temp_up->bind_param("ii", $student_id, $rid);
                $temp_up->execute();
            }

            // Step 2: Set to final values
            foreach ($priorities as $item) {
                $rid = (int)$item['room_id'];
                $po = (int)$item['priority_order'];
                $up = $conn->prepare("UPDATE room_preferences SET priority_order = ? WHERE student_id = ? AND room_id = ?");
                $up->bind_param("iii", $po, $student_id, $rid);
                if (!$up->execute()) {
                    throw new Exception("Update failed for room $rid: " . $conn->error);
                }
            }
            $conn->commit();
            echo json_encode(["success" => true, "message" => "Priorities reordered"]);
        } catch (Exception $e) {
            $conn->rollback();
            throw $e;
        }
    }

} catch (Exception $e) {
    if ($method === 'PUT') $conn->rollback();
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
?>
