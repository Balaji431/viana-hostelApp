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

$database = new Database();
$db = $database->getConnection();

// Get sub_zone_id from query parameter
$sub_zone_id = isset($_GET['sub_zone_id']) ? $_GET['sub_zone_id'] : '';

if (empty($sub_zone_id)) {
    echo json_encode([
        'success' => false,
        'message' => 'Sub-Zone ID is required'
    ]);
    exit;
}

$query = "SELECT id, room_number, floor, capacity, room_type, status, created_at, updated_at 
          FROM rooms 
          WHERE sub_zone_id = ? 
          ORDER BY room_number ASC";

$stmt = $db->prepare($query);
$stmt->bindParam(1, $sub_zone_id);
$stmt->execute();

$rooms_arr = array();
$rooms_arr["success"] = true;
$rooms_arr["data"] = array();

while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
    $room_item = array(
        "id" => $row['id'],
        "room_number" => $row['room_number'],
        "floor" => $row['floor'],
        "capacity" => $row['capacity'],
        "room_type" => $row['room_type'],
        "status" => $row['status'],
        "created_at" => $row['created_at'],
        "updated_at" => $row['updated_at']
    );
    
    array_push($rooms_arr["data"], $room_item);
}

echo json_encode($rooms_arr);
?>
