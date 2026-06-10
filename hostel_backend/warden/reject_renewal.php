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

$data = json_decode(file_get_contents("php://input"), true);

$renewalId = $data['renewal_id'];
$wardenId = $data['warden_id'] ?? null;

try {
    // Get warden name
    $wardenName = null;
    if ($wardenId) {
        $stmt = $conn->prepare("SELECT full_name FROM users WHERE id=?");
        $stmt->bind_param("i", $wardenId);
        $stmt->execute();
        $res = $stmt->get_result();
        $warden = $res->fetch_assoc();
        $wardenName = $warden['full_name'] ?? null;
    }

    $stmt2 = $conn->prepare("
        UPDATE renewal_requests 
        SET status='rejected',
            processed_by=?,
            processed_by_name=?,
            processed_at=NOW()
        WHERE id=?
    ");

    $stmt2->bind_param("isi", $wardenId, $wardenName, $renewalId);
    $stmt2->execute();

    echo json_encode([
        "success" => true,
        "status" => "success",
        "message" => "Renewal rejected"
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "status" => "error",
        "message" => $e->getMessage()
    ]);
}
?>
