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

// Enable error reporting for debugging
error_reporting(E_ALL);
ini_set('display_errors', 0);

$hostelId = isset($_GET['hostel_id']) ? intval($_GET['hostel_id']) : 0;

if ($hostelId == 0) {
    echo json_encode(['status' => 'error', 'message' => 'Hostel ID required', 'success' => false]);
    exit;
}

try {
    $database = new Database();
    $conn = $database->getConnection();
    
    if (!$conn) {
        echo json_encode(['status' => 'error', 'message' => 'Database connection failed', 'success' => false]);
        exit;
    }
    
    // Get hostel info - use hostel_name as name for Dart compatibility
    $hostelStmt = $conn->prepare("SELECT id, hostel_name AS name, hostel_type AS type FROM hostel_type WHERE id = :id");
    $hostelStmt->bindParam(':id', $hostelId, PDO::PARAM_INT);
    $hostelStmt->execute();
    $hostel = $hostelStmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$hostel) {
        echo json_encode(['status' => 'error', 'message' => 'Hostel not found', 'success' => false]);
        exit;
    }
    
    // Get rooms grouped by WING first, then floor (Wing → Floor → Room hierarchy)
    $stmt = $conn->prepare("
        SELECT 
            id, room_no, floor, floor_code, wing_code, 
            total_capacity AS capacity, -- In DB total_capacity is actually the max capacity
            available_rooms AS vacancy, 
            occupied_rooms, 
            amount, 
            facility AS facilities
        FROM hostel_rooms 
        WHERE hostel_id = :hostel_id
        ORDER BY wing_code, floor_code, room_no
    ");
    $stmt->bindParam(':hostel_id', $hostelId, PDO::PARAM_INT);
    $stmt->execute();
    
    $wings = [];
    
    while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $wingCode = $row['wing_code'] ?: 'DEFAULT';
        $floorCode = $row['floor_code'] ?: 'DEFAULT';
        
        // Initialize wing if not exists
        if (!isset($wings[$wingCode])) {
            $wings[$wingCode] = [
                'wing_code' => $wingCode,
                'wing_name' => $wingCode == 'DEFAULT' ? 'Main Wing' : str_replace('_', ' ', $wingCode),
                'floors' => []
            ];
        }
        
        // Initialize floor if not exists
        if (!isset($wings[$wingCode]['floors'][$floorCode])) {
            $wings[$wingCode]['floors'][$floorCode] = [
                'floor_code' => $floorCode,
                'floor_name' => $row['floor'] ?: 'Zone ' . $floorCode,
                'rooms' => []
            ];
        }
        
        // Add room to floor
        $wings[$wingCode]['floors'][$floorCode]['rooms'][] = [
            'id' => $row['id'],
            'room_no' => $row['room_no'],
            'total_capacity' => intval($row['capacity']),
            'total_occupied' => intval($row['occupied_rooms']),
            'available_rooms' => intval($row['vacancy']),
            'amount' => floatval($row['amount']),
            'facilities' => $row['facilities']
        ];
    }
    
    // Convert associative arrays to indexed arrays
    $wingList = [];
    foreach ($wings as $wingCode => $wingData) {
        $floorList = [];
        foreach ($wingData['floors'] as $floorCode => $floorData) {
            $floorList[] = $floorData;
        }
        $wingData['floors'] = $floorList;
        $wingList[] = $wingData;
    }
    
    echo json_encode([
        'status' => 'success',
        'success' => true,
        'hostel' => $hostel,
        'wings' => $wingList
    ]);
    
} catch (Exception $e) {
    echo json_encode(['status' => 'error', 'message' => $e->getMessage(), 'success' => false]);
}
?>
