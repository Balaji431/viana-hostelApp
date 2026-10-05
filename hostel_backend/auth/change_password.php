<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/auth_helper.php';

$authUser = requireAuth();

$raw_input = file_get_contents("php://input");
$data = json_decode($raw_input);

$user_id = $data->user_id ?? null;
$old_password = $data->old_password ?? null;
$new_password = $data->new_password ?? null;

if (!$user_id || !$new_password) {
    echo json_encode(['success' => false, 'message' => 'Missing required fields']);
    exit;
}

$isAdmin = in_array(strtolower($authUser['role'] ?? ''), ['admin', 'super_admin']);

// Non-admins can only change their own password and MUST supply their old password
if (!$isAdmin) {
    if ((int)$user_id !== (int)($authUser['id'] ?? 0)) {
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'Forbidden: You cannot change another user\'s password.']);
        exit;
    }
    if (empty($old_password)) {
        echo json_encode(['success' => false, 'message' => 'Current password is required']);
        exit;
    }
}

if (strlen($new_password) < 6) {
    echo json_encode(['success' => false, 'message' => 'New password must be at least 6 characters long']);
    exit;
}

try {
    $database = new Database();
    $db = $database->getConnection();

    // Determine the correct table based on role
    $role = $data->role ?? ($authUser['role'] ?? 'student');
    $table = (strtolower($role) === 'parent') ? 'parent_users' : 'users';

    // 1. Fetch current password hash
    $query = "SELECT password FROM $table WHERE id = :id LIMIT 1";
    $stmt = $db->prepare($query);
    $stmt->bindParam(':id', $user_id);
    $stmt->execute();

    if ($stmt->rowCount() == 0) {
        echo json_encode(['success' => false, 'message' => "User not found in $table"]);
        exit;
    }

    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    $current_hash = $row['password'];

    // 2. Verify old password for non-admin requests
    if (!$isAdmin) {
        if (!password_verify($old_password, $current_hash) && $old_password !== $current_hash) {
            echo json_encode(['success' => false, 'message' => 'Incorrect old password']);
            exit;
        }
    }

    // 3. Hash and update new password
    $new_hash = password_hash($new_password, PASSWORD_DEFAULT);
    $update_query = "UPDATE $table SET password = :password WHERE id = :id";
    $update_stmt = $db->prepare($update_query);
    $update_stmt->bindParam(':password', $new_hash);
    $update_stmt->bindParam(':id', $user_id);

    if ($update_stmt->execute()) {
        echo json_encode(['success' => true, 'message' => 'Password changed successfully']);
    } else {
        echo json_encode(['success' => false, 'message' => 'Failed to update password']);
    }

} catch (Exception $e) {
    echo json_encode(['success' => false, 'message' => 'Server error: ' . $e->getMessage()]);
}
?>
