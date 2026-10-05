<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/activity_logger.php';
require_once __DIR__ . '/../utils/auth_helper.php';

// Manual student registration strictly requires authorized admin or warden token
$authUser = requireAuth(['admin', 'super_admin', 'warden']);

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

if($data && !empty($data->full_name) && !empty($data->register_no) && !empty($data->password)) {
    try {
        // 1. Check if user already exists
        $check_query = "SELECT id FROM users WHERE username = :username";
        $check_stmt = $db->prepare($check_query);
        $check_stmt->bindParam(':username', $data->register_no);
        $check_stmt->execute();
        
        if ($check_stmt->rowCount() > 0) {
            echo json_encode(["success" => false, "message" => "Registration Number already exists"]);
            exit;
        }

        // 2. Insert into users table
        $query_u = "INSERT INTO users (full_name, username, password, role, email, phone_number, Status) 
                    VALUES (:full_name, :username, :password, 'student', :email, :phone, 'Active')";
        $stmt_u = $db->prepare($query_u);
        
        $email = $data->email ?? "";
        $phone = $data->phone ?? "";
        $hashed_password = password_hash($data->password, PASSWORD_DEFAULT);
        
        $stmt_u->bindParam(':full_name', $data->full_name);
        $stmt_u->bindParam(':username', $data->register_no);
        $stmt_u->bindParam(':password', $hashed_password);
        $stmt_u->bindParam(':email', $email);
        $stmt_u->bindParam(':phone', $phone);
        
        if($stmt_u->execute()) {
            $user_id = $db->lastInsertId();
            
            // Log REGISTER_STUDENT audit trail entry
            logAudit(
                $user_id,
                $data->register_no,
                'student',
                'REGISTER_STUDENT',
                'Authentication',
                null,
                [
                    'registered_by' => $authUser['username'] ?? 'admin',
                    'full_name' => $data->full_name,
                    'email' => $email,
                    'phone_number' => $phone
                ]
            );
            
            // 3. Insert into profile table
            $query_p = "INSERT INTO profile (reg_no, full_name, email, personal_phone, institution) 
                        VALUES (:reg_no, :full_name, :email, :phone, :institution)";
            $stmt_p = $db->prepare($query_p);
            
            $institution = $data->institution ?? "Saveetha Institute of Medical and Technical Sciences";
            
            $stmt_p->bindParam(':reg_no', $data->register_no);
            $stmt_p->bindParam(':full_name', $data->full_name);
            $stmt_p->bindParam(':email', $email);
            $stmt_p->bindParam(':phone', $phone);
            $stmt_p->bindParam(':institution', $institution);
            $stmt_p->execute();

            echo json_encode(["success" => true, "message" => "Student registered successfully", "user_id" => $user_id]);
        } else {
            echo json_encode(["success" => false, "message" => "Failed to register student"]);
        }
    } catch (Exception $e) {
        echo json_encode(["success" => false, "message" => "Server error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Incomplete registration data"]);
}
?>
