<?php
ini_set('display_errors', 0);
error_reporting(E_ALL);

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/response.php';

$database = new Database();
$db = $database->getConnection();

if ($db === null) {
    sendResponse(false, "Database connection failed", null, 500);
    exit();
}

$raw_input = file_get_contents("php://input");
$data = !empty($raw_input) ? json_decode($raw_input, true) : null;
if (!is_array($data) || empty($data)) {
    $data = $_POST;
}

$issue_id = isset($data['issue_id']) ? intval($data['issue_id']) : (isset($data['id']) ? intval($data['id']) : (isset($_POST['issue_id']) ? intval($_POST['issue_id']) : null));
$status = trim($data['status'] ?? $_POST['status'] ?? '');
$admin_notes = trim($data['admin_notes'] ?? $_POST['admin_notes'] ?? '');
$user_role = strtolower(trim($data['role'] ?? $_POST['role'] ?? ''));

if (!empty($user_role) && $user_role !== 'developer') {
    sendResponse(false, "Forbidden: Only developers are authorized to update issue statuses.", null, 403);
    exit();
}

if (!$issue_id || empty($status)) {
    sendResponse(false, "Issue ID and new status are required.", null, 400);
    exit();
}

$allowedStatuses = ['Pending', 'In Progress', 'Resolved', 'Closed'];
$foundStatus = null;
foreach ($allowedStatuses as $st) {
    if (strtolower($st) === strtolower($status)) {
        $foundStatus = $st;
        break;
    }
}

if (!$foundStatus) {
    sendResponse(false, "Invalid status provided. Allowed: Pending, In Progress, Resolved, Closed", null, 400);
    exit();
}

try {
    $query = "UPDATE `issues` SET `status` = :status, `admin_notes` = :admin_notes, `updated_at` = NOW() WHERE `id` = :id";
    $stmt = $db->prepare($query);
    $stmt->bindParam(':status', $foundStatus);
    $stmt->bindParam(':admin_notes', $admin_notes);
    $stmt->bindParam(':id', $issue_id, PDO::PARAM_INT);

    if ($stmt->execute()) {
        sendResponse(true, "Issue status updated successfully", [
            'issue_id' => $issue_id,
            'status' => $foundStatus,
            'admin_notes' => $admin_notes
        ]);
    } else {
        sendResponse(false, "Failed to update issue status.", null, 500);
    }
} catch (Exception $e) {
    sendResponse(false, "Database error: " . $e->getMessage(), null, 500);
}
