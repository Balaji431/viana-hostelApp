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
        'message' => 'Sub-Zone ID is required'
    ]);
    exit;
}

$sub_zone_id = $data->id;
$name = isset($data->name) ? $data->name : '';
$wing_code = isset($data->wing_code) ? $data->wing_code : '';
$total_rooms = isset($data->total_rooms) ? $data->total_rooms : 0;

if (empty($name)) {
    echo json_encode([
        'success' => false,
        'message' => 'Wing name is required'
    ]);
    exit;
}

$query = "UPDATE sub_zones 
          SET name = ?, wing_code = ?, total_rooms = ?, updated_at = CURRENT_TIMESTAMP
          WHERE id = ?";

$stmt = $db->prepare($query);
$stmt->bindParam(1, $name);
$stmt->bindParam(2, $wing_code);
$stmt->bindParam(3, $total_rooms);
$stmt->bindParam(4, $sub_zone_id);

if ($stmt->execute()) {
    echo json_encode([
        'success' => true,
        'message' => 'Wing updated successfully'
    ]);
} else {
    echo json_encode([
        'success' => false,
        'message' => 'Failed to update wing'
    ]);
}
?>
