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
require_once '../utils/activity_logger.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

$data = json_decode(file_get_contents("php://input"), true);

if (isset($data['student_id']) && isset($data['conduct'])) {
    $student_id = $conn->real_escape_string($data['student_id']);
    $conduct = $conn->real_escape_string($data['conduct']);
    $remarks = isset($data['remarks']) ? $conn->real_escape_string($data['remarks']) : '';

    // Fetch previous state
    $prev_sql = "SELECT conduct, conduct_remarks FROM users WHERE id = '$student_id'";
    $prev_res = $conn->query($prev_sql);
    $prev_row = $prev_res ? $prev_res->fetch_assoc() : null;
    $previous_state = $prev_row ? json_encode($prev_row) : null;

    $sql = "UPDATE users SET conduct = '$conduct', conduct_remarks = '$remarks' WHERE id = '$student_id'";

    if ($conn->query($sql) === TRUE) {
        logActivity(
            $data['warden_id'] ?? null,
            $data['warden_username'] ?? 'warden',
            'warden',
            'UPDATE_CONDUCT',
            'users',
            $previous_state,
            json_encode(['conduct' => $conduct, 'conduct_remarks' => $remarks])
        );
        echo json_encode(array("status" => "success", "success" => true, "message" => "Conduct updated successfully"));
    } else {
        echo json_encode(array("status" => "error", "success" => false, "message" => "Error updating conduct: " . $conn->error));
    }
} else {
    echo json_encode(array("status" => "error", "success" => false, "message" => "Invalid parameters"));
}

$conn->close();
?>
