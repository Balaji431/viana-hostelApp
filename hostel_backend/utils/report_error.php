<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

try {
    $data = json_decode(file_get_contents("php://input"));

    if ($data && !empty($data->error_message)) {
        $errorMessage = $data->error_message;
        $stackTrace = $data->stack_trace ?? '';
        $user = $data->user ?? 'Guest';
        $device = $data->device ?? 'Unknown';

        $query = "INSERT INTO app_errors (error_message, stack_trace, user, device) VALUES (?, ?, ?, ?)";
        $stmt = $db->prepare($query);

        if ($stmt->execute([$errorMessage, $stackTrace, $user, $device])) {
            echo json_encode(["success" => true, "message" => "Error reported successfully"]);
        } else {
            echo json_encode(["success" => false, "message" => "Database execution failed"]);
        }
    } else {
        echo json_encode(["success" => false, "message" => "Incomplete error data"]);
    }
} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Exception: " . $e->getMessage()]);
}
?>
