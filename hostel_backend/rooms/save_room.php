<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once '../config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();

    $data = json_decode(file_get_contents("php://input"), true);

    if (isset($data['hostel_name']) && isset($data['room_number']) && isset($data['room_type'])) {
        $hostelId = isset($data['hostel_id']) ? intval($data['hostel_id']) : null;
        $hostelName = $data['hostel_name'];
        $roomNumber = $data['room_number'];
        $floor = $data['floor'] ?? '';
        $block = $data['block'] ?? '';
        $roomType = $data['room_type'];
        $capacity = isset($data['capacity']) ? intval($data['capacity']) : 0;
        $availableBeds = isset($data['available_beds']) ? intval($data['available_beds']) : $capacity;
        $status = $data['status'] ?? 'active';
        $roomId = isset($data['id']) ? intval($data['id']) : 0;

        if ($roomId > 0) {
            // Update existing room
            $stmt = $db->prepare("UPDATE rooms SET hostel_id = ?, hostel_name = ?, room_number = ?, floor = ?, block = ?, room_type = ?, capacity = ?, available_beds = ?, status = ? WHERE id = ?");
            $stmt->execute([$hostelId, $hostelName, $roomNumber, $floor, $block, $roomType, $capacity, $availableBeds, $status, $roomId]);
            
            echo json_encode([
                "status" => "success",
                "success" => true,
                "message" => "Room updated successfully",
                "id" => $roomId
            ]);
        } else {
            // Check for duplicate room in same hostel
            $checkStmt = $db->prepare("SELECT id FROM rooms WHERE hostel_name = ? AND room_number = ?");
            $checkStmt->execute([$hostelName, $roomNumber]);
            
            if ($checkStmt->fetch(PDO::FETCH_ASSOC)) {
                echo json_encode([
                    "status" => "error",
                    "success" => false,
                    "message" => "Room with this number already exists in this hostel"
                ]);
                exit();
            }
            
            // Insert new room
            $stmt = $db->prepare("INSERT INTO rooms (hostel_id, hostel_name, room_number, floor, block, room_type, capacity, available_beds, occupied_beds, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)");
            $stmt->execute([$hostelId, $hostelName, $roomNumber, $floor, $block, $roomType, $capacity, $availableBeds, $status]);
            
            $newRoomId = $db->lastInsertId();
            
            echo json_encode([
                "status" => "success",
                "success" => true,
                "message" => "Room created successfully",
                "id" => $newRoomId
            ]);
        }
    } else {
        echo json_encode([
            "status" => "error",
            "success" => false,
            "message" => "Required fields: hostel_name, room_number, room_type"
        ]);
    }
} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
