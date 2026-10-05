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
require_once __DIR__ . '/../utils/auth_helper.php';

$authHeader = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
if (empty($authHeader) && function_exists('apache_request_headers')) {
    $headers = apache_request_headers();
    $authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? '';
}
$token = '';
if (preg_match('/Bearer\s+(\S+)/i', $authHeader, $matches)) {
    $token = $matches[1];
}

$payload = validateJWT($token);
if (!$payload) {
    http_response_code(401);
    echo json_encode(["status" => "error", "message" => "Unauthorized. Valid login token required."]);
    exit();
}

$reqUserId = (int)($payload['id'] ?? 0);
$reqUsername = trim($payload['username'] ?? '');
$reqRole = strtolower(trim($payload['role'] ?? ''));
$isPrivileged = in_array($reqRole, ['admin', 'super_admin', 'warden', 'developer', 'it']);

$student_id = $_GET['student_id'] ?? null;
$reg_no = $_GET['reg_no'] ?? null;

if (!$student_id && !$reg_no) {
    echo json_encode(["status" => "error", "message" => "student_id or reg_no is required"]);
    exit();
}

if (!$isPrivileged) {
    $matchesUser = false;
    if ($student_id && (int)$student_id === $reqUserId) {
        $matchesUser = true;
    }
    if ($reg_no && strtolower(trim($reg_no)) === strtolower($reqUsername)) {
        $matchesUser = true;
    }
    if (!$matchesUser) {
        http_response_code(403);
        echo json_encode(["status" => "error", "message" => "Forbidden. You cannot view another student's payment history."]);
        exit();
    }
}

try {
    $database = new Database();
    $db = $database->getConnection();

    $query = "SELECT DISTINCT p.* FROM payment p 
              LEFT JOIN users u ON (p.user_id = u.id OR TRIM(u.username) COLLATE utf8mb4_unicode_ci = TRIM(p.registerNumber) COLLATE utf8mb4_unicode_ci)
              WHERE u.id = ? OR p.user_id = ? OR p.registerNumber = ?
              ORDER BY COALESCE(p.paid_at, p.created_at, p.booking_date) ASC";
              
    $stmt = $db->prepare($query);
    $stmt->execute([$student_id, $student_id, $reg_no ?: $student_id]);

    $results = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode(["status" => "success", "data" => $results]);

} catch (Exception $e) {
    echo json_encode(["status" => "error", "message" => $e->getMessage()]);
}
?>
