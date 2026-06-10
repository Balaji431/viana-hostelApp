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

// Handle preflight OPTIONS request
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

$database = new Database();
$db = $database->getConnection();

// Get POST data
$data = json_decode(file_get_contents("php://input"));

if (!isset($data->id) || empty($data->id)) {
    echo json_encode([
        'success' => false,
        'message' => 'Room ID is required'
    ]);
    exit;
}

$room_id = $data->id;
$room_number = isset($data->room_number) ? $data->room_number : '';
$floor = isset($data->floor) ? $data->floor : '';
$capacity = isset($data->capacity) ? $data->capacity : 1;
$room_type = isset($data->room_type) ? $data->room_type : 'single';

if (empty($room_number)) {
    echo json_encode([
        'success' => false,
        'message' => 'Room number is required'
    ]);
    exit;
}

$query = "UPDATE rooms 
          SET room_number = ?, floor = ?, capacity = ?, room_type = ?, updated_at = CURRENT_TIMESTAMP
          WHERE id = ?";

$stmt = $db->prepare($query);
$stmt->bindParam(1, $room_number);
$stmt->bindParam(2, $floor);
$stmt->bindParam(3, $capacity);
$stmt->bindParam(4, $room_type);
$stmt->bindParam(5, $room_id);

if ($stmt->execute()) {
    echo json_encode([
        'success' => true,
        'message' => 'Room updated successfully'
    ]);
} else {
    echo json_encode([
        'success' => false,
        'message' => 'Failed to update room'
    ]);
}
?>
