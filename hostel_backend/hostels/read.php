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

// Fetch all hostels from hostel_type table instead of hostels
$query = "SELECT id, hostel_name as name, campus as location, building_code, hostel_type as gender_type 
          FROM hostel_type 
          ORDER BY campus, hostel_name";

$result = $conn->query($query);

$hostels = array();

if ($result && $result->num_rows > 0) {
    while($row = $result->fetch_assoc()) {
        $hostels[] = array(
            "id" => $row['id'],
            "name" => $row['name'],
            "location" => $row['location'],
            "building_code" => $row['building_code'],
            "gender_type" => $row['gender_type'],
            "status" => "active"
        );
    }
    echo json_encode(array("success" => true, "status" => "success", "data" => $hostels));
} else {
    echo json_encode(array("success" => false, "status" => "error", "message" => "No hostels found"));
}

$conn->close();
?>
