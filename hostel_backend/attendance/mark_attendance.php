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

// Initialize database connection
$database = new DatabaseMysqli();
$conn = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

if(!empty($data->student_id) && !empty($data->status)) {
    // Only 'IN' or 'OUT' allowed (supporting uppercase and lowercase)
    $status = strtoupper($data->status);
    if ($status !== 'IN' && $status !== 'OUT' && $status !== 'PRESENT') {
        echo json_encode(["success" => false, "status" => "error", "message" => "Invalid status: " . $status]);
        exit;
    }

    $student_id = $conn->real_escape_string($data->student_id);
    $status = $conn->real_escape_string($status);

    $query = "INSERT INTO attendance (student_id, status) VALUES (?, ?)";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $student_id, $status);

    if($stmt->execute()) {
        echo json_encode(["success" => true, "status" => "success", "message" => "Attendance marked: " . $status, "current_status" => $status]);
    } else {
        echo json_encode(["success" => false, "status" => "error", "message" => "Server Error: Unable to mark attendance - " . $conn->error]);
    }
    $stmt->close();
} else {
    echo json_encode(["success" => false, "status" => "error", "message" => "Missing data: student_id or status"]);
}

$conn->close();
?>
