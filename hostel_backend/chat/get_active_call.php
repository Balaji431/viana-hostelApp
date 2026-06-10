<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json');

require_once '../config/database.php';

$target_id = $_GET['target_id'] ?? null;
$check_ended = isset($_GET['check_ended']) && $_GET['check_ended'] === 'true';

if (!$target_id) {
    echo json_encode(["success" => false, "message" => "Target ID required"]);
    exit;
}

$database = new Database();
$db = $database->getConnection();

if ($check_ended) {
    // Check if the MOST RECENT call for this user was ended in the last minute
    $query = "SELECT status FROM active_calls WHERE target_id = :tid OR caller_id = :tid ORDER BY created_at DESC LIMIT 1";
    $stmt = $db->prepare($query);
    $stmt->bindParam(':tid', $target_id);
    $stmt->execute();
    $call = $stmt->fetch(PDO::FETCH_ASSOC);
    
    echo json_encode([
        "success" => true,
        "status" => $call ? $call['status'] : 'idle'
    ]);
    exit;
}

// Original logic: Check for active ringing calls for this user
$query = "SELECT * FROM active_calls WHERE target_id = :tid AND status = 'ringing' AND created_at > (NOW() - INTERVAL 1 MINUTE) ORDER BY created_at DESC LIMIT 1";
$stmt = $db->prepare($query);
$stmt->bindParam(':tid', $target_id);
$stmt->execute();
$call = $stmt->fetch(PDO::FETCH_ASSOC);

if ($call) {
    echo json_encode([
        "success" => true,
        "call" => [
            "caller_name" => $call['caller_name'],
            "channel_name" => $call['channel_name'],
            "id" => $call['id']
        ]
    ]);
} else {
    echo json_encode(["success" => false, "message" => "No active calls"]);
}
?>
