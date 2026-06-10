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

$complaint_id = $data['complaint_id'] ?? null;
$status = $data['status'] ?? null;
$reply = $data['reply'] ?? null;

if (!$complaint_id || !$status) {
    echo json_encode(["success" => false, "message" => "Missing required fields"]);
    exit;
}

$allowed_statuses = ['Pending', 'Under Review', 'Resolved'];
if (!in_array($status, $allowed_statuses)) {
    echo json_encode(["success" => false, "message" => "Invalid status value"]);
    exit;
}

try {
    $database = new Database();
    $db = $database->getConnection();

    $query = "UPDATE complaints 
              SET status = :status, 
                  admin_reply = :reply, 
                  admin_replied_at = NOW() 
              WHERE id = :id";
              
    $stmt = $db->prepare($query);
    $stmt->bindParam(':status', $status);
    $stmt->bindParam(':reply', $reply);
    $stmt->bindParam(':id', $complaint_id);

    if ($stmt->execute()) {
        echo json_encode([
            "success" => true,
            "message" => "Complaint status updated successfully"
        ]);
    } else {
        echo json_encode(["success" => false, "message" => "Failed to update complaint status"]);
    }

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Server error: " . $e->getMessage()]);
}
?>
