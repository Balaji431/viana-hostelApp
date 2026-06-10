<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

if (!$pdo) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

$data = json_decode(file_get_contents("php://input"), true);

if (empty($data['hostel_name'])) {
    echo json_encode(["success" => false, "message" => "Hostel name is required"]);
    exit();
}

try {
    $pdo->beginTransaction();

    // ==========================================
    // LEGACY TABLES: hostel_type & hostel_rooms
    // ==========================================
    $stmt = $pdo->prepare("INSERT INTO hostel_type (campus, hostel_name, hostel_type, building_code) VALUES (?, ?, ?, ?)");
    $stmt->execute([
        $data['campus'] ?? 'Thandalam Campus',
        $data['hostel_name'],
        $data['type'] ?? 'Girls',
        $data['building_code'] ?? ''
    ]);
    
    $legacy_hostel_id = $pdo->lastInsertId();

    if (!empty($data['rooms']) && is_array($data['rooms'])) {
        $roomStmt = $pdo->prepare("INSERT INTO hostel_rooms 
            (hostel_id, campus, campus_code, hostel_name, building_code, hostel_type, 
             room_type, location_name, floor_code, floor, room_no, wing_code, room_code, 
             facility, bath_attached, amount, total_capacity, available_rooms, occupied_rooms) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)");

        foreach ($data['rooms'] as $room) {
            $room_no = $room['room_number'];
            $building_code = $data['building_code'] ?? '';
            $floor_name = $room['floor'] ?? 'Ground';
            $floor_code = $room['floor_code'] ?? $floor_name;
            $wing_name = $room['wing'] ?? 'General';
            $wing_code = $room['wing_code'] ?? $wing_name;
            
            // Use the room_code sent from UI or generate it
            $room_code = $room['room_code'] ?? ($building_code . "-" . $floor_code . "-" . $wing_code . "-R" . $room_no);
            
            $roomStmt->execute([
                $legacy_hostel_id,
                $data['campus'] ?? 'Thandalam Campus',
                $data['campus_code'] ?? 'TC',
                $data['hostel_name'],
                $building_code,
                $data['type'] ?? 'Girls',
                $room['room_type'] ?? 'Standard',
                $wing_name, // location_name
                $floor_code,
                $floor_name,
                $room_no,
                $wing_code,
                $room_code,
                $room['facility'] ?? 'AC',
                $room['bath_attached'] ?? 'Yes',
                $room['amount'] ?? 100000.00,
                $room['capacity'] ?? 4,
                $room['capacity'] ?? 4
            ]);
        }
    }

    // ==========================================
    // NEW HIERARCHY TABLES: hostels, zones, sub_zones, rooms
    // ==========================================
    // Check if hostel already exists in master table to avoid duplicates
    $checkStmt = $pdo->prepare("SELECT id FROM hostels WHERE name = ?");
    $checkStmt->execute([$data['hostel_name']]);
    $existing_hostel_id = $checkStmt->fetchColumn();

    if ($existing_hostel_id) {
        $new_hostel_id = $existing_hostel_id;
    } else {
        $newHostelStmt = $pdo->prepare("INSERT INTO hostels (name) VALUES (?)");
        $newHostelStmt->execute([$data['hostel_name']]);
        $new_hostel_id = $pdo->lastInsertId();
    }

    // Map to keep track of created zones and sub_zones
    // format: wing_name => zone_id
    $zoneMap = [];
    // format: wing_name_floor_name => sub_zone_id
    $subZoneMap = [];

    // Pre-create zones from 'wings' array
    if (!empty($data['wings']) && is_array($data['wings'])) {
        $zoneStmt = $pdo->prepare("INSERT INTO zones (hostel_id, name) VALUES (?, ?)");
        foreach ($data['wings'] as $wing) {
            $zoneStmt->execute([$new_hostel_id, $wing]);
            $zoneMap[$wing] = $pdo->lastInsertId();
        }
    }

    if (!empty($data['rooms']) && is_array($data['rooms'])) {
        // FIX: rooms table uses 'floor_label' not 'floor'
        $newRoomStmt = $pdo->prepare("INSERT INTO rooms (sub_zone_id, room_number, capacity, floor_label) VALUES (?, ?, ?, ?)");
        $zoneStmt = $pdo->prepare("INSERT INTO zones (hostel_id, name) VALUES (?, ?)");
        $subZoneStmt = $pdo->prepare("INSERT INTO sub_zones (zone_id, name) VALUES (?, ?)");

        foreach ($data['rooms'] as $room) {
            $wing = $room['wing'] ?? 'Default Wing';
            $floor = $room['floor'] ?? 'Default Floor';

            // 1. Ensure zone (wing) exists
            if (!isset($zoneMap[$wing])) {
                $zoneStmt->execute([$new_hostel_id, $wing]);
                $zoneMap[$wing] = $pdo->lastInsertId();
            }
            $zone_id = $zoneMap[$wing];

            // 2. Ensure sub_zone (floor) exists for this zone
            $subZoneKey = $wing . "_" . $floor;
            if (!isset($subZoneMap[$subZoneKey])) {
                $subZoneStmt->execute([$zone_id, $floor]);
                $subZoneMap[$subZoneKey] = $pdo->lastInsertId();
            }
            $sub_zone_id = $subZoneMap[$subZoneKey];

            // 3. Insert room using correct column 'floor_label'
            $newRoomStmt->execute([
                $sub_zone_id,
                $room['room_number'],
                $room['capacity'] ?? 4,
                $floor
            ]);
        }
    }

    $pdo->commit();
    echo json_encode(["success" => true, "message" => "Hostel and rooms created successfully", "id" => $legacy_hostel_id]);

} catch (Exception $e) {
    $pdo->rollBack();
    echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
}
?>
