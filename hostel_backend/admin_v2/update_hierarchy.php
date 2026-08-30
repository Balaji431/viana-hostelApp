<?php
// Suppress warnings that could corrupt JSON output
ini_set('display_errors', 0);
error_reporting(E_ALL);
date_default_timezone_set('Asia/Kolkata');
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
require_once '../utils/activity_logger.php';

if (!$pdo) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

$data = json_decode(file_get_contents("php://input"), true);
$action = isset($data['action']) ? trim($data['action']) : '';

if (!$action) {
    echo json_encode(["success" => false, "message" => "Action is required"]);
    exit();
}

// DEBUG: Log action to check for hidden characters
file_put_contents('action_debug.txt', "Action: [$action], Hex: " . bin2hex($action) . "\n", FILE_APPEND);

try {
    switch ($action) {
        case 'update_hostel':
            $id = $data['id'];
            $name = $data['name'];
            $type = $data['type'] ?? 'Girls';
            $building = $data['building_code'] ?? '';
            
            $pdo->beginTransaction();
            
            // 0. Get old name first
            $old_stmt = $pdo->prepare("SELECT hostel_name FROM hostel_type WHERE id = ?");
            $old_stmt->execute([$id]);
            $oldName = $old_stmt->fetchColumn();

            // 1. Update hostel_type
            $stmt = $pdo->prepare("UPDATE hostel_type SET hostel_name = ?, hostel_type = ?, building_code = ? WHERE id = ?");
            $stmt->execute([$name, $type, $building, $id]);
            
            // 2. Update denormalized names in hostel_rooms
            $stmt = $pdo->prepare("UPDATE hostel_rooms SET hostel_name = ?, hostel_type = ?, building_code = ? WHERE hostel_id = ?");
            $stmt->execute([$name, $type, $building, $id]);

            // 3. Update profile table and hierarchy master
            if ($oldName && $oldName !== $name) {
                $p_stmt = $pdo->prepare("UPDATE profile SET hostel_name = ? WHERE hostel_name = ?");
                $p_stmt->execute([$name, $oldName]);
                
                $h_stmt = $pdo->prepare("UPDATE hostels SET name = ? WHERE name = ?");
                $h_stmt->execute([$name, $oldName]);

                // 4. Log the activity
                logAdminActivity($data['admin_id'] ?? 1, "Renamed Hostel", "Changed '$oldName' to '$name'");
            }

            $pdo->commit();
            break;

        case 'update_floor':
            $hostelId = $data['hostel_id'];
            $oldFloor = $data['old_name'];
            $newFloor = $data['new_name'];
            
            $stmt = $pdo->prepare("UPDATE hostel_rooms SET floor = ?, floor_code = ? WHERE hostel_id = ? AND (floor = ? OR floor_code = ?)");
            $stmt->execute([$newFloor, $newFloor, $hostelId, $oldFloor, $oldFloor]);
            break;

        case 'update_wing':
            $hostelId = $data['hostel_id'];
            $floorName = $data['wing_name']; // Provider sends parent as wing_name
            $oldWing = $data['old_name'];
            $newWing = $data['new_name'];
            
            $stmt = $pdo->prepare("UPDATE hostel_rooms SET wing_code = ? WHERE hostel_id = ? AND floor = ? AND wing_code = ?");
            $stmt->execute([$newWing, $hostelId, $floorName, $oldWing]);
            break;

        case 'update_room':
            $roomId = $data['id'];
            $inputRoom = $data['room_no'];
            $capacity = $data['capacity'];
            $amount = $data['amount'] ?? 0;
            
            $pdo->beginTransaction();
            
            $old_stmt = $pdo->prepare("SELECT * FROM hostel_rooms WHERE id = ?");
            $old_stmt->execute([$roomId]);
            $oldRoom = $old_stmt->fetch(PDO::FETCH_ASSOC);
            $oldRoomCode = $oldRoom ? $oldRoom['room_code'] : null;
            
            $roomNo = $inputRoom;
            if (strpos($inputRoom, '-R') !== false) {
                $parts = explode('-R', $inputRoom);
                $roomNo = end($parts);
            }
            
            // Build new room code using building-floor-wing-Rno pattern
            $roomCode = ($oldRoom['building_code'] ?? 'B00') . '-' . ($oldRoom['floor'] ?? 'F00') . '-' . ($oldRoom['wing_code'] ?? 'W00') . '-R' . $roomNo;

            $stmt = $pdo->prepare("UPDATE hostel_rooms SET room_no = ?, room_code = ?, total_capacity = ?, available_rooms = ?, amount = ? WHERE id = ?");
            $stmt->execute([$roomNo, $roomCode, $capacity, $capacity, $amount, $roomId]);
            
            if ($oldRoomCode && $oldRoomCode != $roomCode) {
                $pdo->prepare("UPDATE profile SET room_allocation = ? WHERE room_allocation = ?")->execute([$roomCode, $oldRoomCode]);
                $pdo->prepare("UPDATE room_change_requests SET current_room = ? WHERE current_room = ?")->execute([$roomCode, $oldRoomCode]);
                $pdo->prepare("UPDATE room_change_requests SET requested_room = ? WHERE requested_room = ?")->execute([$roomCode, $oldRoomCode]);
            }
            
            $pdo->commit();
            break;

        case 'add_floor':
            $hostelId = $data['hostel_id'];
            $floorName = $data['name'];
            
            $h_stmt = $pdo->prepare("SELECT * FROM hostel_type WHERE id = ?");
            $h_stmt->execute([$hostelId]);
            $hostel = $h_stmt->fetch(PDO::FETCH_ASSOC);
            $campus = trim($hostel['campus']);
            $campus_code = substr($campus, 0, 10);
            
            $sql = "INSERT INTO hostel_rooms 
                    (hostel_id, campus, campus_code, hostel_name, building_code, hostel_type, room_type, location_name, 
                     floor_code, floor, room_no, wing_code, room_code, facility, bath_attached, amount, total_capacity, available_rooms) 
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
            $stmt = $pdo->prepare($sql);
            $stmt->execute([
                $hostelId, $campus, $campus_code, $hostel['hostel_name'], $hostel['building_code'], $hostel['hostel_type'], 
                'Structural', 'Main', 
                $floorName, $floorName, 'New Floor', 'General', 'FLOOR-' . time(), '', 'No', 0, 0, 0
            ]);
            break;

        case 'add_wing':
            $hostelId = $data['hostel_id'];
            $floorName = $data['wing_name']; // Parent
            $wingName = $data['name'];
            
            $h_stmt = $pdo->prepare("SELECT * FROM hostel_type WHERE id = ?");
            $h_stmt->execute([$hostelId]);
            $hostel = $h_stmt->fetch(PDO::FETCH_ASSOC);
            $campus = trim($hostel['campus']);
            $campus_code = substr($campus, 0, 10);
            
            $sql = "INSERT INTO hostel_rooms 
                    (hostel_id, campus, campus_code, hostel_name, building_code, hostel_type, room_type, location_name, 
                     floor_code, floor, room_no, wing_code, room_code, facility, bath_attached, amount, total_capacity, available_rooms) 
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
            $stmt = $pdo->prepare($sql);
            $stmt->execute([
                $hostelId, $campus, $campus_code, $hostel['hostel_name'], $hostel['building_code'], $hostel['hostel_type'], 
                'Structural', 'Main',
                $floorName, $floorName, 'New Wing', $wingName, 'WING-' . time(), '', 'No', 0, 0, 0
            ]);
            break;

        case 'add_room':
            $hostelId = $data['hostel_id'];
            $floorName = $data['wing_name']; // Parent
            $wingName = $data['floor_name']; // Child
            $floorCode = $data['floor_code'] ?? $floorName;
            $wingCode = $data['wing_code'] ?? $wingName;
            $roomNo = $data['room_no'];
            $capacity = $data['capacity'];
            $amount = $data['amount'] ?? 0;
            $facility = $data['facility'] ?? 'AC';
            
            $h_stmt = $pdo->prepare("SELECT * FROM hostel_type WHERE id = ?");
            $h_stmt->execute([$hostelId]);
            $hostel = $h_stmt->fetch(PDO::FETCH_ASSOC);
            
            // Build new room code using building-floor-wing-Rno pattern
            $roomCode = $hostel['building_code'] . '-' . $floorCode . '-' . $wingCode . '-R' . $roomNo;
            
            $sql = "INSERT INTO hostel_rooms 
                    (hostel_id, campus, campus_code, hostel_name, building_code, hostel_type, floor, floor_code, wing_code, room_no, room_code, room_type, facility, location_name, bath_attached, total_capacity, available_rooms, amount) 
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
            $stmt = $pdo->prepare($sql);
            $stmt->execute([
                $hostelId, $hostel['campus'], substr($hostel['campus'],0,10), $hostel['hostel_name'], $hostel['building_code'], $hostel['hostel_type'],
                $floorName, $floorCode, $wingCode, $roomNo, $roomCode, 'Standard', $facility, 'Main', 'Yes', $capacity, $capacity, $amount
            ]);
            break;

        case 'add_hostel':
            $name = $data['name'];
            $campus = $data['campus'] ?? 'Main Campus';
            $type = $data['type'] ?? 'Girls';
            $building = $data['building_code'] ?? '';
            
            $pdo->beginTransaction();
            // 1. Insert into hostel_type
            $stmt = $pdo->prepare("INSERT INTO hostel_type (hostel_name, campus, hostel_type, building_code) VALUES (?, ?, ?, ?)");
            $stmt->execute([$name, $campus, $type, $building]);
            $hostelId = $pdo->lastInsertId();
            
            // 2. Create initial structural row (Wing A, Ground Floor)
            $campus_code = substr(trim($campus), 0, 10);
            $sql = "INSERT INTO hostel_rooms 
                    (hostel_id, campus, campus_code, hostel_name, building_code, hostel_type, room_type, location_name, 
                     floor_code, floor, room_no, wing_code, room_code, facility, bath_attached, amount, total_capacity, available_rooms) 
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
            $stmt = $pdo->prepare($sql);
            $stmt->execute([
                $hostelId, $campus, $campus_code, $name, $building, $type, 
                'Structural', 'Main',
                '', '', 'New Hostel Placeholder', 'Wing A', 'WING-' . time(), '', 'No', 0, 0, 0
            ]);

            // 3. Sync with hostels table
            $sync_stmt = $pdo->prepare("INSERT INTO hostels (name) SELECT ? WHERE NOT EXISTS (SELECT 1 FROM hostels WHERE name = ?)");
            $sync_stmt->execute([$name, $name]);

            $pdo->commit();
            break;

        case 'delete_hostel':
            $id = $data['id'] ?? '';
            if (empty($id)) {
                echo json_encode(["success" => false, "message" => "Hostel ID/Name is required for deletion."]);
                exit();
            }

            // Resolve exact hostel name
            $hostelName = is_string($id) ? trim($id) : '';
            
            if (is_numeric($id)) {
                $name_stmt = $pdo->prepare("SELECT hostel_name FROM hostel_type WHERE id = ?");
                $name_stmt->execute([$id]);
                $found = $name_stmt->fetchColumn();
                if ($found) $hostelName = $found;

                if (!$found) {
                    $h_stmt = $pdo->prepare("SELECT name FROM hostels WHERE id = ?");
                    $h_stmt->execute([$id]);
                    $foundH = $h_stmt->fetchColumn();
                    if ($foundH) $hostelName = $foundH;
                }
            }

            if (empty($hostelName)) {
                $hostelName = (string)$id;
            }

            // Check if any students are currently allotted/assigned to this hostel
            $occupiedCount = 0;

            // 1. Check occupied beds in rooms_groups_details
            $checkRgd = $pdo->prepare("SELECT COALESCE(SUM(occupied_beds), 0) FROM rooms_groups_details WHERE hostel_name = ?");
            $checkRgd->execute([$hostelName]);
            $occupiedCount += (int)($checkRgd->fetchColumn() ?? 0);

            // 2. Check occupied beds in room_master
            $checkRm = $pdo->prepare("SELECT COALESCE(SUM(occupied_beds), 0) FROM room_master WHERE location_name = ?");
            $checkRm->execute([$hostelName]);
            $occupiedCount += (int)($checkRm->fetchColumn() ?? 0);

            // 3. Check legacy hostel_rooms if present
            try {
                $checkLegacy = $pdo->prepare("SELECT COALESCE(SUM(occupied_rooms), 0) FROM hostel_rooms WHERE hostel_name = ? OR hostel_id = ?");
                $checkLegacy->execute([$hostelName, is_numeric($id) ? (int)$id : 0]);
                $occupiedCount += (int)($checkLegacy->fetchColumn() ?? 0);
            } catch (Exception $e) {}

            // 4. Check active student bookings / users assigned to this hostel
            try {
                $checkUsers = $pdo->prepare("SELECT COUNT(*) FROM users WHERE hostel_name = ? OR (HostelType = ? AND room_no IS NOT NULL AND TRIM(room_no) != '')");
                $checkUsers->execute([$hostelName, $hostelName]);
                $occupiedCount += (int)($checkUsers->fetchColumn() ?? 0);
            } catch (Exception $e) {}

            if ($occupiedCount > 0) {
                echo json_encode([
                    "success" => false,
                    "message" => "Cannot delete '$hostelName' because students are currently assigned to it ($occupiedCount active allocation(s)). Please unassign all students before deleting."
                ]);
                exit();
            }

            // Perform clean cascading delete across all hierarchy and room master tables
            $pdo->beginTransaction();

            // 1. Delete from zones / sub_zones / rooms hierarchy (respecting FK constraints)
            $hStmt = $pdo->prepare("SELECT id FROM hostels WHERE name = ? OR id = ?");
            $hStmt->execute([$hostelName, is_numeric($id) ? (int)$id : 0]);
            $hostelDbIds = $hStmt->fetchAll(PDO::FETCH_COLUMN);

            if (!empty($hostelDbIds)) {
                foreach ($hostelDbIds as $hDbId) {
                    $zStmt = $pdo->prepare("SELECT id FROM zones WHERE hostel_id = ?");
                    $zStmt->execute([$hDbId]);
                    $zoneIds = $zStmt->fetchAll(PDO::FETCH_COLUMN);

                    if (!empty($zoneIds)) {
                        $inZones = implode(',', array_map('intval', $zoneIds));
                        $szStmt = $pdo->query("SELECT id FROM sub_zones WHERE zone_id IN ($inZones)");
                        $subZoneIds = $szStmt->fetchAll(PDO::FETCH_COLUMN);

                        if (!empty($subZoneIds)) {
                            $inSubZones = implode(',', array_map('intval', $subZoneIds));
                            $pdo->exec("DELETE FROM rooms WHERE sub_zone_id IN ($inSubZones)");
                            $pdo->exec("DELETE FROM sub_zones WHERE id IN ($inSubZones)");
                        }
                        $pdo->exec("DELETE FROM zones WHERE id IN ($inZones)");
                    }
                    $pdo->prepare("DELETE FROM hostels WHERE id = ?")->execute([$hDbId]);
                }
            }
            // Delete by name from hostels
            $pdo->prepare("DELETE FROM hostels WHERE name = ?")->execute([$hostelName]);

            // 2. Delete from rooms_groups_details
            $pdo->prepare("DELETE FROM rooms_groups_details WHERE hostel_name = ?")->execute([$hostelName]);

            // 3. Delete from room_master
            $pdo->prepare("DELETE FROM room_master WHERE location_name = ?")->execute([$hostelName]);

            // 4. Delete from hostel_type
            $pdo->prepare("DELETE FROM hostel_type WHERE hostel_name = ? OR id = ?")->execute([$hostelName, is_numeric($id) ? (int)$id : 0]);

            // 5. Delete from legacy hostel_rooms
            try {
                $pdo->prepare("DELETE FROM hostel_rooms WHERE hostel_name = ? OR hostel_id = ?")->execute([$hostelName, is_numeric($id) ? (int)$id : 0]);
            } catch (Exception $e) {}

            $pdo->commit();
            break;

        case 'delete_wing':
            $hostelId = $data['hostel_id'];
            $wing = $data['name'];
            $floor = isset($data['wing_name']) ? $data['wing_name'] : null;
            
            if ($floor) {
                $stmt = $pdo->prepare("DELETE FROM hostel_rooms WHERE hostel_id = ? AND floor = ? AND wing_code = ?");
                $stmt->execute([$hostelId, $floor, $wing]);
            } else {
                // Handle 'General' wing case where wing_code might be empty/null
                if ($wing === 'General') {
                    $stmt = $pdo->prepare("DELETE FROM hostel_rooms WHERE hostel_id = ? AND (wing_code = ? OR wing_code = '' OR wing_code IS NULL)");
                    $stmt->execute([$hostelId, $wing]);
                } else {
                    $stmt = $pdo->prepare("DELETE FROM hostel_rooms WHERE hostel_id = ? AND wing_code = ?");
                    $stmt->execute([$hostelId, $wing]);
                }
            }
            break;

        case 'delete_floor':
            $hostelId = $data['hostel_id'];
            $floor = $data['name'];
            $stmt = $pdo->prepare("DELETE FROM hostel_rooms WHERE hostel_id = ? AND (floor = ? OR floor_code = ?)");
            $stmt->execute([$hostelId, $floor, $floor]);
            break;


        default:
            echo json_encode(["success" => false, "message" => "Unknown action: $action"]);
            exit();
    }

    echo json_encode(["success" => true, "message" => ucfirst(str_replace('_', ' ', $action)) . " successful"]);

} catch (Exception $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    $msg = $e->getMessage();
    if (strpos($msg, 'foreign key constraint fails') !== false) {
        $msg = "Cannot complete deletion because this resource is linked to active student registrations, allocations, or request histories. Please clear dependencies first.";
    }
    echo json_encode(["success" => false, "message" => "Error: " . $msg]);
}
?>
