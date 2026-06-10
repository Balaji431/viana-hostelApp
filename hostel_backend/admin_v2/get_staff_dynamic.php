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

// Get all staff members with their assigned hostels from hostel_type table
$query = "SELECT s.id, s.name, s.email, s.phone, s.role, s.employee_id, s.status, s.created_at, s.updated_at,
                 h.hostel_name as hostel_name, h.campus as hostel_location
          FROM staff_members s 
          LEFT JOIN hostel_type h ON s.assigned_hostel_id = h.id 
          ORDER BY s.created_at DESC";

$result = $conn->query($query);

$staff = array();

if ($result && $result->num_rows > 0) {
    while($row = $result->fetch_assoc()) {
        $staff[] = array(
            "id" => $row['id'],
            "name" => $row['name'],
            "email" => $row['email'],
            "phone" => $row['phone'],
            "role" => $row['role'],
            "employee_id" => $row['employee_id'],
            "status" => $row['status'],
            "hostel_name" => $row['hostel_name'],
            "hostel_location" => $row['hostel_location'],
            "created_at" => $row['created_at'],
            "updated_at" => $row['updated_at']
        );
    }
    
    echo json_encode(array("status" => "success", "success" => true, "data" => $staff));
} else {
    echo json_encode(array("status" => "error", "success" => false, "message" => "No staff members found"));
}

$conn->close();
?>
