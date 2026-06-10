<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../../config/database.php';

$database = new Database();
$db = $database->getConnection();

try {

// Get hostel_id from query parameter
$hostel_id = isset($_GET['hostel_id']) ? $_GET['hostel_id'] : '';

if (empty($hostel_id)) {
    echo json_encode([
        'success' => false,
        'message' => 'Hostel ID is required'
    ]);
    exit;
}

$query = "SELECT id, name, floor_number, total_wings, created_at, updated_at 
          FROM zones 
          WHERE hostel_id = ? 
          ORDER BY floor_number ASC, created_at ASC";

$stmt = $db->prepare($query);
$stmt->bindParam(1, $hostel_id);
$stmt->execute();

$zones_arr = array();
$zones_arr["success"] = true;
$zones_arr["data"] = array();

while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
    $zone_item = array(
        "id" => $row['id'],
        "name" => $row['name'],
        "floor_number" => $row['floor_number'],
        "total_wings" => $row['total_wings'],
        "created_at" => $row['created_at'],
        "updated_at" => $row['updated_at']
    );
    
    array_push($zones_arr["data"], $zone_item);
}

echo json_encode($zones_arr);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(["success" => false, "message" => "Error retrieving zones: " . $e->getMessage()]);
}
?>
