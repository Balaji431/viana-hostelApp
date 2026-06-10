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

$database = new DatabaseMysqli();
$conn = $database->getConnection();

try {
    // Get optional filters
    $hostel_name = isset($_GET['hostel_name']) ? $_GET['hostel_name'] : null;
    $room_type = isset($_GET['room_type']) ? $_GET['room_type'] : null;
    
    // Build base query with dynamic calculations
    $sql = "
        SELECT 
            hr.room_code,
            hr.room_no,
            hr.hostel_name,
            hr.total_capacity as capacity,
            hr.room_type,
            hr.facility,
            hr.amount,
            hr.campus,
            hr.building_code,
            hr.wing_code,
            hr.floor_code,
            
            -- occupied (REAL calculation)
            (
                SELECT COUNT(*) 
                FROM profile p 
                WHERE p.room_allocation = hr.room_code
            ) AS occupied,
            
            -- pending room change requests
            (
                SELECT COUNT(*) 
                FROM room_change_requests rcr 
                WHERE rcr.requested_room = hr.room_code 
                AND rcr.status = 'pending'
            ) AS pending
        FROM hostel_rooms hr
    ";
    
    // Add filters if provided
    $conditions = [];
    if ($hostel_name) {
        $conditions[] = "hr.hostel_name = '" . $conn->real_escape_string($hostel_name) . "'";
    }
    if ($room_type) {
        $conditions[] = "hr.room_type = '" . $conn->real_escape_string($room_type) . "'";
    }
    
    if (!empty($conditions)) {
        $sql .= " WHERE " . implode(" AND ", $conditions);
    }
    
    $sql .= " ORDER BY hr.hostel_name, hr.room_no";
    
    $result = $conn->query($sql);
    
    $data = [];
    while ($row = $result->fetch_assoc()) {
        // Calculate available dynamically
        $room = [
            'room_code' => $row['room_code'],
            'room_no' => $row['room_no'],
            'hostel_name' => $row['hostel_name'],
            'capacity' => (int)$row['capacity'],
            'room_type' => $row['room_type'],
            'facility' => $row['facility'],
            'amount' => (float)$row['amount'],
            'campus' => $row['campus'],
            'building_code' => $row['building_code'],
            'wing_code' => $row['wing_code'],
            'floor_code' => $row['floor_code'],
            'occupied' => (int)$row['occupied'],
            'pending' => (int)$row['pending'],
        ];
        
        // Calculate available
        $room['available'] = $room['capacity'] - ($room['occupied'] + $room['pending']);
        $room['is_full'] = $room['available'] <= 0;
        
        $data[] = $room;
    }
    
    echo json_encode([
        "success" => true,
        "status" => "success",
        "message" => "Rooms retrieved successfully",
        "data" => $data
    ]);
    
} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "status" => "error",
        "message" => $e->getMessage()
    ]);
}
?>
