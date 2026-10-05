<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/activity_logger.php';
require_once __DIR__ . '/../utils/auth_helper.php';

// Strictly require administrator authentication to register new staff members
$authUser = requireAuth(['admin', 'super_admin']);

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

$full_name = !empty($data->full_name) ? $data->full_name : (!empty($data->name) ? $data->name : null);
$username = !empty($data->username) ? $data->username : (!empty($data->email) ? $data->email : null);
$password = $data->password ?? null;
$role = $data->role ?? null;

if (!empty($full_name) && !empty($username) && !empty($password) && !empty($role)) {
    try {
        // 1. Check if username already exists
        $check = $db->prepare("SELECT id FROM users WHERE username = ? LIMIT 1");
        $check->execute([$username]);
        if ($check->fetch()) {
            echo json_encode(["success" => false, "message" => "Username already exists"]);
            exit;
        }

        // 2. Hash the password for security (Matches login.php)
        $hashed_password = password_hash($password, PASSWORD_DEFAULT);
        
        $role = strtolower($role);
        $phone = $data->phone ?? '';

        $query = "INSERT INTO users (full_name, username, password, role, phone_number, Campus, Status) 
                  VALUES (:name, :username, :password, :role, :phone, 'SIMATS1', 'active')";
        
        $stmt = $db->prepare($query);
        $stmt->bindValue(':name', $full_name);
        $stmt->bindValue(':username', $username);
        $stmt->bindValue(':password', $hashed_password);
        $stmt->bindValue(':role', $role);
        $stmt->bindValue(':phone', $phone);

        if ($stmt->execute()) {
            $user_id = $db->lastInsertId();
            
            // Log REGISTER_STAFF audit trail entry
            logAudit(
                $user_id,
                $data->username,
                $role,
                'REGISTER_STAFF',
                'Authentication',
                null,
                [
                    'registered_by' => $authUser['username'] ?? 'admin',
                    'full_name' => $data->full_name,
                    'phone_number' => $phone
                ]
            );

            echo json_encode([
                "success" => true, 
                "message" => "Staff member registered successfully",
                "user_id" => $user_id
            ]);
        } else {
            echo json_encode(["success" => false, "message" => "Database insertion failed"]);
        }
    } catch (Exception $e) {
        echo json_encode(["success" => false, "message" => "Server error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Incomplete data. Required: full_name, username, password, role"]);
}
?>
