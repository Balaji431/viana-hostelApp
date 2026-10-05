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
require_once '../utils/auth_helper.php';

/**
 * Hostel Rooms API
 * CRUD operations for hostel_rooms table
 */

// Set headers
// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// Get database connection
$database = new Database();
$database = new Database(); $conn = $database->getConnection();

// Get the request method
$method = $_SERVER['REQUEST_METHOD'];

// Get input data
$input = json_decode(file_get_contents('php://input'), true);

// Get action from query parameter or determine from method
$action = isset($_GET['action']) ? $_GET['action'] : '';

switch ($method) {
    case 'GET':
        if (isset($_GET['id'])) {
            // Get single room by ID
            getRoomById($conn, $_GET['id']);
        } elseif (isset($_GET['hostel_id'])) {
            // Get all rooms for a specific hostel
            getRoomsByHostel($conn, $_GET['hostel_id']);
        } elseif (isset($_GET['floor'])) {
            // Get rooms by floor
            getRoomsByFloor($conn, $_GET['floor']);
        } else {
            // Get all rooms (with optional filters)
            getAllRooms($conn, $_GET);
        }
        break;

    case 'POST':
        requireAuth(['admin', 'super_admin']);
        if ($action === 'bulk_insert') {
            // Bulk insert rooms
            bulkInsertRooms($conn, $input);
        } else {
            // Create single room
            createRoom($conn, $input);
        }
        break;

    case 'PUT':
        requireAuth(['admin', 'super_admin']);
        if (isset($_GET['id'])) {
            updateRoom($conn, $_GET['id'], $input);
        } else {
            http_response_code(400);
            echo json_encode(['status' => 'error', 'message' => 'Room ID required']);
        }
        break;

    case 'DELETE':
        requireAuth(['admin', 'super_admin']);
        if (isset($_GET['id'])) {
            deleteRoom($conn, $_GET['id']);
        } else {
            http_response_code(400);
            echo json_encode(['status' => 'error', 'message' => 'Room ID required']);
        }
        break;

    default:
        http_response_code(405);
        echo json_encode(['status' => 'error', 'message' => 'Method not allowed']);
}

/**
 * Get all rooms with optional filters
 */
function getAllRooms($conn, $filters = []) {
    try {
        $sql = "SELECT * FROM hostel_rooms WHERE 1=1";
        $params = [];

        if (!empty($filters['campus'])) {
            $sql .= " AND campus = ?";
            $params[] = $filters['campus'];
        }

        if (!empty($filters['hostel_name'])) {
            $sql .= " AND hostel_name = ?";
            $params[] = $filters['hostel_name'];
        }

        if (!empty($filters['room_type'])) {
            $sql .= " AND room_type = ?";
            $params[] = $filters['room_type'];
        }

        if (!empty($filters['facility'])) {
            $sql .= " AND facility = ?";
            $params[] = $filters['facility'];
        }

        if (isset($filters['available_only']) && $filters['available_only'] === 'true') {
            $sql .= " AND available_rooms > 0";
        }

        $sql .= " ORDER BY hostel_id, floor_code, room_no";

        $stmt = $conn->prepare($sql);
        $stmt->execute($params);
        $rooms = $stmt->fetchAll(PDO::FETCH_ASSOC);

        echo json_encode([
            'status' => 'success',
            'count' => count($rooms),
            'data' => $rooms
        ]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
    }
}

/**
 * Get room by ID
 */
function getRoomById($conn, $id) {
    try {
        $stmt = $conn->prepare("SELECT * FROM hostel_rooms WHERE id = ?");
        $stmt->execute([$id]);
        $room = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($room) {
            echo json_encode(['status' => 'success', 'data' => $room]);
        } else {
            http_response_code(404);
            echo json_encode(['status' => 'error', 'message' => 'Room not found']);
        }
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
    }
}

/**
 * Get rooms by hostel ID
 */
function getRoomsByHostel($conn, $hostelId) {
    try {
        $sql = "SELECT * FROM hostel_rooms WHERE hostel_id = ? ORDER BY floor_code, room_no";
        $stmt = $conn->prepare($sql);
        $stmt->execute([$hostelId]);
        $rooms = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Group rooms by floor
        $groupedRooms = [];
        foreach ($rooms as $room) {
            $floor = $room['floor'];
            if (!isset($groupedRooms[$floor])) {
                $groupedRooms[$floor] = [];
            }
            $groupedRooms[$floor][] = $room;
        }

        echo json_encode([
            'status' => 'success',
            'count' => count($rooms),
            'data' => $groupedRooms
        ]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
    }
}

/**
 * Get rooms by floor
 */
function getRoomsByFloor($conn, $floor) {
    try {
        $stmt = $conn->prepare("SELECT * FROM hostel_rooms WHERE floor_code = ? ORDER BY room_no");
        $stmt->execute([$floor]);
        $rooms = $stmt->fetchAll(PDO::FETCH_ASSOC);

        echo json_encode([
            'status' => 'success',
            'count' => count($rooms),
            'data' => $rooms
        ]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
    }
}

/**
 * Create a new room
 */
function createRoom($conn, $data) {
    try {
        $required = ['hostel_id', 'campus', 'campus_code', 'hostel_name', 'building_code', 
                     'room_type', 'location_name', 'floor_code', 'floor', 'room_no', 
                     'wing_code', 'room_code', 'facility', 'bath_attached', 'amount', 
                     'total_capacity', 'available_rooms'];

        foreach ($required as $field) {
            if (empty($data[$field])) {
                http_response_code(400);
                echo json_encode(['status' => 'error', 'message' => "Missing required field: $field"]);
                return;
            }
        }

        $sql = "INSERT INTO hostel_rooms 
                (hostel_id, campus, campus_code, hostel_name, building_code, hostel_type,
                 room_type, location_name, floor_code, floor, room_no, wing_code, room_code,
                 facility, bath_attached, amount, caution_dept, total_capacity, available_rooms, occupied_rooms)
                VALUES 
                (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

        $stmt = $conn->prepare($sql);
        $stmt->execute([
            $data['hostel_id'],
            $data['campus'],
            $data['campus_code'],
            $data['hostel_name'],
            $data['building_code'],
            $data['hostel_type'] ?? 'Girls',
            $data['room_type'],
            $data['location_name'],
            $data['floor_code'],
            $data['floor'],
            $data['room_no'],
            $data['wing_code'],
            $data['room_code'],
            $data['facility'],
            $data['bath_attached'],
            $data['amount'],
            $data['caution_dept'] ?? 5000.00,
            $data['total_capacity'],
            $data['available_rooms'],
            $data['occupied_rooms'] ?? 0
        ]);

        $newId = $conn->lastInsertId();

        echo json_encode([
            'status' => 'success',
            'message' => 'Room created successfully',
            'id' => $newId
        ]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
    }
}

/**
 * Bulk insert rooms
 */
function bulkInsertRooms($conn, $data) {
    try {
        if (empty($data['rooms']) || !is_array($data['rooms'])) {
            http_response_code(400);
            echo json_encode(['success' => false, 'message' => 'Rooms array required']);
            return;
        }

        $conn->beginTransaction();

        $sql = "INSERT INTO hostel_rooms 
                (hostel_id, campus, campus_code, hostel_name, building_code, hostel_type,
                 room_type, location_name, floor_code, floor, room_no, wing_code, room_code,
                 facility, bath_attached, amount, caution_dept, total_capacity, available_rooms, occupied_rooms)
                VALUES 
                (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

        $stmt = $conn->prepare($sql);
        $checkStmt = $conn->prepare("SELECT id FROM hostel_rooms WHERE hostel_id = ? AND room_code = ? LIMIT 1");
        $count = 0;
        $skipped = 0;

        foreach ($data['rooms'] as $room) {
            $checkStmt->execute([$room['hostel_id'], $room['room_code']]);
            if ($checkStmt->fetch(PDO::FETCH_ASSOC)) {
                $skipped++;
                continue;
            }

            $stmt->execute([
                $room['hostel_id'],
                $room['campus'],
                $room['campus_code'],
                $room['hostel_name'],
                $room['building_code'],
                $room['hostel_type'] ?? 'Girls',
                $room['room_type'],
                $room['location_name'],
                $room['floor_code'],
                $room['floor'],
                $room['room_no'],
                $room['wing_code'],
                $room['room_code'],
                $room['facility'],
                $room['bath_attached'],
                $room['amount'],
                $room['caution_dept'] ?? 5000.00,
                $room['total_capacity'],
                $room['available_rooms'],
                $room['occupied_rooms'] ?? 0
            ]);
            $count++;
        }

        $conn->commit();

        echo json_encode([
            'success' => true,
            'message' => "$count rooms inserted successfully" . ($skipped > 0 ? ", $skipped duplicates skipped" : ""),
            'count' => $count,
            'skipped' => $skipped
        ]);
    } catch (PDOException $e) {
        $conn->rollBack();
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => $e->getMessage()]);
    }
}

/**
 * Update a room
 */
function updateRoom($conn, $id, $data) {
    try {
        // Build dynamic update query
        $fields = [];
        $values = [];

        $allowedFields = [
            'hostel_id', 'campus', 'campus_code', 'hostel_name', 'building_code',
            'hostel_type', 'room_type', 'location_name', 'floor_code', 'floor',
            'room_no', 'wing_code', 'room_code', 'facility', 'bath_attached',
            'amount', 'caution_dept', 'total_capacity', 'available_rooms', 'occupied_rooms'
        ];

        foreach ($allowedFields as $field) {
            if (isset($data[$field])) {
                $fields[] = "$field = ?";
                $values[] = $data[$field];
            }
        }

        if (empty($fields)) {
            http_response_code(400);
            echo json_encode(['status' => 'error', 'message' => 'No fields to update']);
            return;
        }

        $values[] = $id;
        $sql = "UPDATE hostel_rooms SET " . implode(', ', $fields) . " WHERE id = ?";

        $stmt = $conn->prepare($sql);
        $stmt->execute($values);

        if ($stmt->rowCount() > 0) {
            echo json_encode([
                'status' => 'success',
                'message' => 'Room updated successfully'
            ]);
        } else {
            echo json_encode([
                'status' => 'success',
                'message' => 'No changes made'
            ]);
        }
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
    }
}

/**
 * Delete a room
 */
function deleteRoom($conn, $id) {
    try {
        // First check if the room has active occupants
        $checkStmt = $conn->prepare("SELECT occupied_rooms, room_code FROM hostel_rooms WHERE id = ?");
        $checkStmt->execute([$id]);
        $room = $checkStmt->fetch(PDO::FETCH_ASSOC);
        
        if ($room && (int)$room['occupied_rooms'] > 0) {
            http_response_code(400);
            echo json_encode([
                'status' => 'error',
                'message' => 'Cannot delete room ' . $room['room_code'] . ' because it currently has active student occupants. Please unassign students first.'
            ]);
            return;
        }

        $stmt = $conn->prepare("DELETE FROM hostel_rooms WHERE id = ?");
        $stmt->execute([$id]);

        if ($stmt->rowCount() > 0) {
            echo json_encode([
                'status' => 'success',
                'message' => 'Room deleted successfully'
            ]);
        } else {
            http_response_code(404);
            echo json_encode(['status' => 'error', 'message' => 'Room not found']);
        }
    } catch (PDOException $e) {
        http_response_code(400); // Return 400 bad request for user-resolvable constraint conflicts
        $msg = $e->getMessage();
        if (strpos($msg, 'foreign key constraint fails') !== false) {
            $msg = 'Cannot delete this room because it is currently linked to student allocations or bookings. Please unassign students first.';
        }
        echo json_encode(['status' => 'error', 'message' => $msg]);
    }
}
