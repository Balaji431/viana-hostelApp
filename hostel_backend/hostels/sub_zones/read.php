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

$zone_id = isset($_GET['zone_id']) ? $_GET['zone_id'] : '';

if (empty($zone_id)) {
    echo json_encode([
        'success' => false,
        'message' => 'Zone ID is required'
    ]);
    exit;
}

$query = "SELECT id, zone_id, sub_zone_name as name, sub_zone_code, capacity, floor, created_at, updated_at 
          FROM sub_zones 
          WHERE zone_id = ? 
          ORDER BY sub_zone_name ASC";

$stmt = $db->prepare($query);
$stmt->bindParam(1, $zone_id);
$stmt->execute();

$sub_zones = array();
while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
    $sub_zones[] = $row;
}

echo json_encode([
    "success" => true,
    "data" => $sub_zones
]);
?>
