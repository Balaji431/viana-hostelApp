<?php
ini_set('display_errors', 0);
error_reporting(E_ALL);

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept, X-User-Id, X-User-Username, X-User-Role');
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

// Auto-create issues table if it doesn't exist
try {
    $createSql = "CREATE TABLE IF NOT EXISTS `issues` (
      `id` INT AUTO_INCREMENT PRIMARY KEY,
      `user_id` INT NULL,
      `username` VARCHAR(100) NOT NULL,
      `user_name` VARCHAR(150) NULL,
      `user_role` VARCHAR(50) NOT NULL,
      `email` VARCHAR(150) NULL,
      `phone` VARCHAR(50) NULL,
      `hostel_name` VARCHAR(100) NULL,
      `room_no` VARCHAR(50) NULL,
      `issue_description` TEXT NOT NULL,
      `attachment_url` VARCHAR(500) NULL,
      `attachment_type` VARCHAR(50) NULL,
      `attachment_name` VARCHAR(255) NULL,
      `status` VARCHAR(50) NOT NULL DEFAULT 'Pending',
      `admin_notes` TEXT NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX `idx_issues_role` (`user_role`),
      INDEX `idx_issues_status` (`status`),
      INDEX `idx_issues_created_at` (`created_at`),
      INDEX `idx_issues_username` (`username`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;";
    $db->exec($createSql);
} catch (Exception $e) {
    // Proceed even if check fails
}

// Collect input from POST or JSON
$raw_input = file_get_contents("php://input");
$json_data = !empty($raw_input) ? json_decode($raw_input, true) : [];

$username = trim($_POST['username'] ?? $json_data['username'] ?? $_SERVER['HTTP_X_USER_USERNAME'] ?? '');
$user_name = trim($_POST['user_name'] ?? $json_data['user_name'] ?? '');
$user_role = trim(strtolower($_POST['user_role'] ?? $json_data['user_role'] ?? $_SERVER['HTTP_X_USER_ROLE'] ?? 'student'));
$email = trim($_POST['email'] ?? $json_data['email'] ?? '');
$phone = trim($_POST['phone'] ?? $json_data['phone'] ?? '');
$hostel_name = trim($_POST['hostel_name'] ?? $json_data['hostel_name'] ?? '');
$room_no = trim($_POST['room_no'] ?? $json_data['room_no'] ?? '');
$issue_description = trim($_POST['issue_description'] ?? $json_data['issue_description'] ?? '');
$user_id = isset($_POST['user_id']) ? intval($_POST['user_id']) : (isset($json_data['user_id']) ? intval($json_data['user_id']) : null);

if (empty($issue_description)) {
    sendResponse(false, "Please provide an issue description.", null, 400);
    exit();
}

if (empty($username)) {
    $username = 'Anonymous';
}

// Ensure upload directory exists
$uploadDir = __DIR__ . '/../uploads/issues/';
if (!is_dir($uploadDir)) {
    mkdir($uploadDir, 0777, true);
}

$attachment_url = null;
$attachment_type = null;
$attachment_name = null;

// 1. Process Multipart file upload if present
if (isset($_FILES['attachment']) && $_FILES['attachment']['error'] === UPLOAD_ERR_OK) {
    $fileTmpPath = $_FILES['attachment']['tmp_name'];
    $originalName = $_FILES['attachment']['name'];
    $fileSize = $_FILES['attachment']['size'];
    $fileExtension = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));

    $allowedExtensions = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];
    if (in_array($fileExtension, $allowedExtensions)) {
        $safeName = 'issue_' . time() . '_' . uniqid() . '.' . $fileExtension;
        $destination = $uploadDir . $safeName;

        if (move_uploaded_file($fileTmpPath, $destination)) {
            $attachment_url = 'uploads/issues/' . $safeName;
            $attachment_type = ($fileExtension === 'pdf') ? 'pdf' : 'image';
            $attachment_name = $originalName;
        }
    }
}

// 2. Base64 fallback if multipart wasn't used but base64 was sent
if (!$attachment_url && !empty($_POST['attachment_base64'] ?? $json_data['attachment_base64'] ?? '')) {
    $base64Data = $_POST['attachment_base64'] ?? $json_data['attachment_base64'];
    $sentFileName = $_POST['attachment_name'] ?? $json_data['attachment_name'] ?? 'attachment';
    $fileExtension = strtolower(pathinfo($sentFileName, PATHINFO_EXTENSION));

    if (empty($fileExtension)) {
        $fileExtension = (strpos($base64Data, 'data:application/pdf') !== false) ? 'pdf' : 'png';
    }

    $allowedExtensions = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];
    if (in_array($fileExtension, $allowedExtensions)) {
        if (strpos($base64Data, ',') !== false) {
            $base64Data = explode(',', $base64Data)[1];
        }
        $decoded = base64_decode($base64Data);
        if ($decoded !== false) {
            $safeName = 'issue_' . time() . '_' . uniqid() . '.' . $fileExtension;
            $destination = $uploadDir . $safeName;
            if (file_put_contents($destination, $decoded)) {
                $attachment_url = 'uploads/issues/' . $safeName;
                $attachment_type = ($fileExtension === 'pdf') ? 'pdf' : 'image';
                $attachment_name = $sentFileName;
            }
        }
    }
}

try {
    $query = "INSERT INTO `issues` 
        (`user_id`, `username`, `user_name`, `user_role`, `email`, `phone`, `hostel_name`, `room_no`, `issue_description`, `attachment_url`, `attachment_type`, `attachment_name`, `status`, `created_at`) 
        VALUES 
        (:user_id, :username, :user_name, :user_role, :email, :phone, :hostel_name, :room_no, :issue_description, :attachment_url, :attachment_type, :attachment_name, 'Pending', NOW())";

    $stmt = $db->prepare($query);
    $stmt->bindParam(':user_id', $user_id, PDO::PARAM_INT);
    $stmt->bindParam(':username', $username);
    $stmt->bindParam(':user_name', $user_name);
    $stmt->bindParam(':user_role', $user_role);
    $stmt->bindParam(':email', $email);
    $stmt->bindParam(':phone', $phone);
    $stmt->bindParam(':hostel_name', $hostel_name);
    $stmt->bindParam(':room_no', $room_no);
    $stmt->bindParam(':issue_description', $issue_description);
    $stmt->bindParam(':attachment_url', $attachment_url);
    $stmt->bindParam(':attachment_type', $attachment_type);
    $stmt->bindParam(':attachment_name', $attachment_name);

    if ($stmt->execute()) {
        $newId = $db->lastInsertId();
        sendResponse(true, "Issue submitted successfully! Developer has been notified.", [
            'issue_id' => $newId,
            'attachment_url' => $attachment_url,
            'status' => 'Pending'
        ]);
    } else {
        sendResponse(false, "Failed to submit issue to database.", null, 500);
    }
} catch (Exception $e) {
    sendResponse(false, "Database error: " . $e->getMessage(), null, 500);
}
