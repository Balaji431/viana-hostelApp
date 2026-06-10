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
        'message' => 'Hostel ID is required'
    ]);
    exit;
}

$hostel_id = $data->id;
$name = isset($data->name) ? $data->name : '';
$description = isset($data->description) ? $data->description : '';
$total_blocks = isset($data->total_blocks) ? $data->total_blocks : 0;
$total_capacity = isset($data->total_capacity) ? $data->total_capacity : 0;

if (empty($name)) {
    echo json_encode([
        'success' => false,
        'message' => 'Hostel name is required'
    ]);
    exit;
}

$query = "UPDATE hostels 
          SET name = ?, description = ?, total_blocks = ?, total_capacity = ?, updated_at = CURRENT_TIMESTAMP
          WHERE id = ?";

$stmt = $db->prepare($query);
$stmt->bindParam(1, $name);
$stmt->bindParam(2, $description);
$stmt->bindParam(3, $total_blocks);
$stmt->bindParam(4, $total_capacity);
$stmt->bindParam(5, $hostel_id);

if ($stmt->execute()) {
    echo json_encode([
        'success' => true,
        'message' => 'Hostel updated successfully'
    ]);
} else {
    echo json_encode([
        'success' => false,
        'message' => 'Failed to update hostel'
    ]);
}
?>
