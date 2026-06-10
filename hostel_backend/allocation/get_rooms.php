<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
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
    // Fetch all rooms with availability
    $query = "SELECT hr.id, hr.room_no as number, hr.building_code as block, hr.floor, 
                     hr.total_capacity as capacity, hr.occupied_rooms as occupied,
                     hr.room_type, hr.facility, hr.amount, hr.hostel_name, hr.hostel_type,
                     (hr.total_capacity - hr.occupied_rooms - (
                        SELECT COUNT(*) FROM room_allocations 
                        WHERE allocated_room_id = hr.id 
                        AND allocation_status = 'payment_pending' 
                        AND payment_deadline > NOW()
                     )) as available
              FROM hostel_rooms hr
              ORDER BY hr.building_code, hr.floor_code, hr.room_no";
    
    $result = $conn->query($query);
    $rooms = [];
    
    while ($row = $result->fetch_assoc()) {
        $rooms[] = [
            "id" => $row['id'],
            "number" => $row['number'],
            "block" => $row['block'],
            "floor" => $row['floor'],
            "capacity" => (int)$row['capacity'],
            "occupied" => (int)$row['occupied'],
            "available" => (int)$row['available'],
            "room_type" => $row['room_type'],
            "facility" => $row['facility'],
            "amount" => $row['amount'],
            "hostel_name" => $row['hostel_name'],
            "hostel_type" => $row['hostel_type'],
            "amenities" => ["WiFi", "AC"] // Mock amenities as requested
        ];
    }

    // Fetch dynamic hostels from hostel_type table
    $hostels_res = $conn->query("SELECT id, campus, hostel_name, hostel_type, building_code FROM hostel_type ORDER BY hostel_name");
    $hostels = [];
    while ($h = $hostels_res->fetch_assoc()) {
        $hostels[] = [
            "id" => (int)$h['id'],
            "campus" => $h['campus'],
            "hostel_name" => $h['hostel_name'],
            "hostel_type" => $h['hostel_type'],
            "building_code" => $h['building_code']
        ];
    }

    echo json_encode([
        "success" => true, 
        "rooms" => $rooms, 
        "hostels" => $hostels
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
?>
