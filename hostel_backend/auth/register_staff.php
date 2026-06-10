<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

if (!empty($data->full_name) && !empty($data->username) && !empty($data->password) && !empty($data->role)) {
    try {
        // 1. Check if username already exists
        $check = $db->prepare("SELECT id FROM users WHERE username = ? LIMIT 1");
        $check->execute([$data->username]);
        if ($check->fetch()) {
            echo json_encode(["success" => false, "message" => "Username already exists"]);
            exit;
        }

        // 2. Hash the password for security (Matches login.php)
        $hashed_password = password_hash($data->password, PASSWORD_DEFAULT);
        
        $role = strtolower($data->role);
        $phone = $data->phone ?? '';

        $query = "INSERT INTO users (full_name, username, password, role, phone_number, Campus, Status) 
                  VALUES (:name, :username, :password, :role, :phone, 'SIMATS1', 'active')";
        
        $stmt = $db->prepare($query);
        $stmt->bindValue(':name', $data->full_name);
        $stmt->bindValue(':username', $data->username);
        $stmt->bindValue(':password', $hashed_password);
        $stmt->bindValue(':role', $role);
        $stmt->bindValue(':phone', $phone);

        if ($stmt->execute()) {
            echo json_encode([
                "success" => true, 
                "message" => "Staff member registered successfully",
                "user_id" => $db->lastInsertId()
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
