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

if ($conn->connect_error) {
    die("Connection failed: " . $conn->connect_error);
}

$role = isset($_GET['role']) ? $_GET['role'] : null;

$query = "SELECT id, name, email, phone, role, employee_id, status, created_at, updated_at 
          FROM staff_members";

if ($role !== null) {
    $query .= " WHERE role = '" . $conn->real_escape_string($role) . "'";
}

$result = $conn->query($query);

$staff_arr = array();
$staff_arr["success"] = true;
$staff_arr["message"] = "Staff members retrieved successfully.";
$staff_arr["data"] = array();

if ($result) {
    while ($row = $result->fetch_assoc()) {
        $staff_item = array(
            "id" => $row['id'],
            "name" => $row['name'],
            "email" => $row['email'],
            "phone" => $row['phone'],
            "role" => $row['role'],
            "employee_id" => $row['employee_id'],
            "status" => $row['status'],
            "created_at" => $row['created_at'],
            "updated_at" => $row['updated_at']
        );
        
        array_push($staff_arr["data"], $staff_item);
    }
}

echo json_encode($staff_arr);

$conn->close();
?>
