<?php
ini_set('display_errors', 0);
error_reporting(E_ALL);

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"), true);

$username = $data['username'] ?? null;
$fcm_token = $data['fcm_token'] ?? null;

// DEBUG
file_put_contents(__DIR__ . '/../token_debug.log', date('Y-m-d H:i:s') . 
" USER: $username TOKEN: $fcm_token\n", FILE_APPEND);

if(!empty($username)) {
    $clear = empty($fcm_token) || $fcm_token === 'clear' || $fcm_token === 'null';
    $token_value = $clear ? null : $fcm_token;
    try {
        // 1. Check in standard users table
        $check_query = "SELECT id FROM users WHERE username = ?";
        $check_stmt = $db->prepare($check_query);
        $check_stmt->execute([$username]);
        
        if ($check_stmt->rowCount() > 0) {
            $query = "UPDATE users SET fcm_token = ? WHERE username = ?";
            $stmt = $db->prepare($query);
            $stmt->execute([$token_value, $username]);
            echo json_encode(["success" => true, "message" => $clear ? "Token cleared from users table" : "Token saved to users table"]);
        } else {
            // 2. Check in parent_users table
            $p_check = $db->prepare("SELECT id FROM parent_users WHERE parent_id = ?");
            $p_check->execute([$username]);
            
            if ($p_check->rowCount() > 0) {
                $p_upd = $db->prepare("UPDATE parent_users SET fcm_token = ? WHERE parent_id = ?");
                $p_upd->execute([$token_value, $username]);
                echo json_encode(["success" => true, "message" => $clear ? "Token cleared from parent_users table" : "Token saved to parent_users table"]);
            } else {
                echo json_encode(["success" => false, "message" => "User not found ($username)"]);
            }
        }
    } catch (PDOException $e) {
        file_put_contents(__DIR__ . '/../token_debug.log', date('Y-m-d H:i:s') . " - PDO Exception: " . $e->getMessage() . "\n", FILE_APPEND);
        echo json_encode(["success" => false, "message" => "Database error: " . $e->getMessage()]);
    }
} else {
    file_put_contents(__DIR__ . '/../token_debug.log', date('Y-m-d H:i:s') . " - Incomplete data received: USER: $username TOKEN: $fcm_token\n", FILE_APPEND);
    echo json_encode(["success" => false, "message" => "Incomplete data"]);
}
?>
