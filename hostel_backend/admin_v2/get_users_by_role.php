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

try {
    $database = new Database();
    $db = $database->getConnection();

    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $role = isset($_GET['role']) ? $_GET['role'] : 'warden';

    // Fetch users by role
    $query = "SELECT id, full_name, username, phone_number as phone FROM users WHERE LOWER(role) = ? ORDER BY full_name ASC";
    $stmt = $db->prepare($query);
    $stmt->execute([strtolower($role)]);
    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Ensure UTF-8 encoding for each value
    foreach ($users as &$user) {
        foreach ($user as $key => $val) {
            if (is_string($val)) {
                $user[$key] = mb_convert_encoding($val, 'UTF-8', 'UTF-8');
            }
        }
    }

    echo json_encode(array("status" => "success", "data" => $users, "success" => true));

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(array("status" => "error", "message" => $e->getMessage(), "success" => false));
}
?>
