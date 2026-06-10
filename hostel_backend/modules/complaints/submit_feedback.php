<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../../config/database.php';

$data = json_decode(file_get_contents("php://input"), true);

$student_id = $data['student_id'] ?? null;
$staff_username = $data['staff_username'] ?? null;
$staff_role = $data['staff_role'] ?? null;
$rating = $data['rating'] ?? null;
$message = $data['message'] ?? null;

if (!$student_id || !$staff_username || !$staff_role || !$rating) {
    echo json_encode(["success" => false, "message" => "Missing required fields"]);
    exit;
}

$rating = intval($rating);
if ($rating < 1 || $rating > 5) {
    echo json_encode(["success" => false, "message" => "Rating must be between 1 and 5"]);
    exit;
}

try {
    $database = new Database();
    $db = $database->getConnection();

    $insert_query = "INSERT INTO feedbacks (student_id, staff_username, staff_role, rating, message) 
                     VALUES (:student_id, :staff_username, :staff_role, :rating, :message)";
    $insert_stmt = $db->prepare($insert_query);
    $insert_stmt->bindParam(':student_id', $student_id);
    $insert_stmt->bindParam(':staff_username', $staff_username);
    $insert_stmt->bindParam(':staff_role', $staff_role);
    $insert_stmt->bindParam(':rating', $rating);
    $insert_stmt->bindParam(':message', $message);

    if ($insert_stmt->execute()) {
        echo json_encode([
            "success" => true,
            "message" => "Feedback submitted successfully. Thank you!"
        ]);
    } else {
        echo json_encode(["success" => false, "message" => "Failed to submit feedback"]);
    }

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Server error: " . $e->getMessage()]);
}
?>
