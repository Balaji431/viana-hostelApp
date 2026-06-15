<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once '../config/database.php';
require_once '../utils/activity_logger.php';

function extractCapacity($roomType) {
    $type = strtoupper($roomType);
    if (preg_match('/(\d+)\s*IN\s*1/', $type, $matches)) {
        return intval($matches[1]);
    }
    if (strpos($type, 'DOUBLE') !== false) {
        return 2;
    }
    if (strpos($type, 'SINGLE') !== false) {
        return 1;
    }
    if (preg_match('/DORM\s*(\d+)/', $type, $matches)) {
        return intval($matches[1]);
    }
    return 0;
}

try {
    $database = new Database();
    $db = $database->getConnection();

    $json = file_get_contents('php://input');
    $data = json_decode($json, true);

    if (empty($data)) {
        echo json_encode([
            "status" => "error",
            "success" => false,
            "message" => "No data received"
        ]);
        exit();
    }

    // Support bulk room master import
    if (isset($data['rooms']) && is_array($data['rooms'])) {
        $db->beginTransaction();
        $inserted = 0;
        $updated = 0;
        foreach ($data['rooms'] as $room) {
            $locationName = $room['location_name'] ?? '';
            $buildingCode = $room['building_code'] ?? '';
            $floorNo = $room['floor_no'] ?? '';
            $blockNo = $room['block_no'] ?? '';
            $roomNo = $room['room_no'] ?? '';
            $roomCode = $room['room_code'] ?? '';
            $roomType = $room['room_type'] ?? '';
            
            $roomCapacity = isset($room['room_capacity']) ? intval($room['room_capacity']) : 0;
            $extractedCapacity = extractCapacity($roomType);
            if ($extractedCapacity > 0) {
                $roomCapacity = $extractedCapacity;
            }

            if (empty($locationName) || empty($buildingCode) || empty($floorNo) || empty($blockNo) || empty($roomNo)) {
                continue; // Skip invalid rows
            }

            // Check for duplicate room
            $checkSql = "SELECT id FROM room_master WHERE location_name = ? AND building_code = ? AND floor_no = ? AND block_no = ? AND room_no = ?";
            $checkStmt = $db->prepare($checkSql);
            $checkStmt->execute([$locationName, $buildingCode, $floorNo, $blockNo, $roomNo]);
            
            if ($existing = $checkStmt->fetch()) {
                $existingId = intval($existing['id']);
                
                // Fetch old values for audit logging
                $old_stmt = $db->prepare("SELECT * FROM room_master WHERE id = ?");
                $old_stmt->execute([$existingId]);
                $old_room = $old_stmt->fetch(PDO::FETCH_ASSOC);

                // Update existing record
                $sql = "UPDATE room_master SET 
                            room_code = ?, 
                            room_type = ?, 
                            room_capacity = ? 
                        WHERE id = ?";
                $stmt = $db->prepare($sql);
                $stmt->execute([$roomCode, $roomType, $roomCapacity, $existingId]);
                logAudit(null, null, null, "UPDATE_ROOM", "Room Master", $old_room, $room);
                $updated++;
            } else {
                // Insert new record
                $sql = "INSERT INTO room_master (location_name, building_code, floor_no, block_no, room_no, room_code, room_type, room_capacity) 
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
                $stmt = $db->prepare($sql);
                $stmt->execute([$locationName, $buildingCode, $floorNo, $blockNo, $roomNo, $roomCode, $roomType, $roomCapacity]);
                $id = $db->lastInsertId();
                logAudit(null, null, null, "CREATE_ROOM", "Room Master", null, $room);
                $inserted++;
            }
        }
        $db->commit();
        echo json_encode([
            "status" => "success",
            "success" => true,
            "message" => "Bulk import completed successfully.",
            "inserted" => $inserted,
            "updated" => $updated
        ]);
        exit();
    }

    $id = isset($data['id']) ? intval($data['id']) : 0;
    $locationName = $data['location_name'] ?? '';
    $buildingCode = $data['building_code'] ?? '';
    $floorNo = $data['floor_no'] ?? '';
    $blockNo = $data['block_no'] ?? '';
    $roomNo = $data['room_no'] ?? '';
    $roomCode = $data['room_code'] ?? '';
    $roomType = $data['room_type'] ?? '';
    
    $roomCapacity = isset($data['room_capacity']) ? intval($data['room_capacity']) : 0;
    $extractedCapacity = extractCapacity($roomType);
    if ($extractedCapacity > 0) {
        $roomCapacity = $extractedCapacity;
    }


    if (empty($locationName) || empty($buildingCode) || empty($floorNo) || empty($blockNo) || empty($roomNo)) {
        echo json_encode([
            "status" => "error",
            "success" => false,
            "message" => "Location Name, Building Code, Floor No, Block No, and Room No are required"
        ]);
        exit();
    }

    if ($id > 0) {
        // Fetch old values for audit logging
        $old_stmt = $db->prepare("SELECT * FROM room_master WHERE id = ?");
        $old_stmt->execute([$id]);
        $old_room = $old_stmt->fetch(PDO::FETCH_ASSOC);

        // Update existing record
        $sql = "UPDATE room_master SET 
                    location_name = ?, 
                    building_code = ?, 
                    floor_no = ?, 
                    block_no = ?, 
                    room_no = ?, 
                    room_code = ?, 
                    room_type = ?, 
                    room_capacity = ? 
                WHERE id = ?";
        $stmt = $db->prepare($sql);
        $stmt->execute([$locationName, $buildingCode, $floorNo, $blockNo, $roomNo, $roomCode, $roomType, $roomCapacity, $id]);
        logAudit(null, null, null, "UPDATE_ROOM", "Room Master", $old_room, $data);
    } else {
        // Check for duplicate room
        $checkSql = "SELECT id FROM room_master WHERE location_name = ? AND building_code = ? AND floor_no = ? AND block_no = ? AND room_no = ?";
        $checkStmt = $db->prepare($checkSql);
        $checkStmt->execute([$locationName, $buildingCode, $floorNo, $blockNo, $roomNo]);
        
        if ($existing = $checkStmt->fetch()) {
            $existingId = intval($existing['id']);
            
            // Fetch old values for audit logging
            $old_stmt = $db->prepare("SELECT * FROM room_master WHERE id = ?");
            $old_stmt->execute([$existingId]);
            $old_room = $old_stmt->fetch(PDO::FETCH_ASSOC);

            // Update existing record
            $sql = "UPDATE room_master SET 
                        location_name = ?, 
                        building_code = ?, 
                        floor_no = ?, 
                        block_no = ?, 
                        room_no = ?, 
                        room_code = ?, 
                        room_type = ?, 
                        room_capacity = ? 
                    WHERE id = ?";
            $stmt = $db->prepare($sql);
            $stmt->execute([$locationName, $buildingCode, $floorNo, $blockNo, $roomNo, $roomCode, $roomType, $roomCapacity, $existingId]);
            logAudit(null, null, null, "UPDATE_ROOM", "Room Master", $old_room, $data);
            $id = $existingId;
        } else {
            // Insert new record
            $sql = "INSERT INTO room_master (location_name, building_code, floor_no, block_no, room_no, room_code, room_type, room_capacity) 
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
            $stmt = $db->prepare($sql);
            $stmt->execute([$locationName, $buildingCode, $floorNo, $blockNo, $roomNo, $roomCode, $roomType, $roomCapacity]);
            $id = $db->lastInsertId();
            logAudit(null, null, null, "CREATE_ROOM", "Room Master", null, $data);
        }
    }

    echo json_encode([
        "status" => "success",
        "success" => true,
        "message" => $id > 0 && isset($data['id']) ? "Room updated successfully" : "Room created successfully",
        "id" => $id
    ]);

} catch (PDOException $e) {
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => "Database error: " . $e->getMessage()
    ]);
} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
