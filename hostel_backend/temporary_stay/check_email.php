<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

$email = trim($_GET['email'] ?? $_POST['email'] ?? '');

if (empty($email)) {
    echo json_encode(["success" => false, "message" => "Email address is required"]);
    exit();
}

try {
    // 1. Check if email has an active temporary stay request
    $stmtTemp = $db->prepare("SELECT * FROM temporary_stay_requests WHERE LOWER(email) = LOWER(?) ORDER BY id DESC LIMIT 1");
    $stmtTemp->execute([$email]);
    $tempRow = $stmtTemp->fetch(PDO::FETCH_ASSOC);

    if ($tempRow) {
        $reqStatus = ucfirst($tempRow['status'] ?? 'Pending');
        echo json_encode([
            "success" => true,
            "registered" => true,
            "has_request" => true,
            "request_id" => $tempRow['request_id'],
            "status" => $tempRow['status'],
            "payment_status" => $tempRow['payment_status'] ?? 'unpaid',
            "amount" => (float)($tempRow['amount'] ?? 0),
            "request_details" => $tempRow,
            "message" => "A temporary stay request ($reqStatus) with this email ($email) is registered in the system."
        ]);
        exit();
    }

    // 2. Check if email exists in standard users table (enrolled students/staff, excluding auto-created TEMP_ accounts)
    $stmtUsers = $db->prepare("SELECT id, username, role FROM users WHERE LOWER(email) = LOWER(?) AND username NOT LIKE 'TEMP_%' LIMIT 1");
    $stmtUsers->execute([$email]);
    $userRow = $stmtUsers->fetch(PDO::FETCH_ASSOC);

    if ($userRow) {
        $roleName = ucfirst($userRow['role'] ?? 'User');
        echo json_encode([
            "success" => true,
            "registered" => true,
            "role" => $userRow['role'],
            "message" => "This email ($email) is already registered as $roleName in the system. Please go for login."
        ]);
        exit();
    }

    // Email is not registered -> free for temporary stay booking
    echo json_encode([
        "success" => true,
        "registered" => false,
        "message" => "Email is available for temporary stay booking."
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Database check error: " . $e->getMessage()
    ]);
}
?>
