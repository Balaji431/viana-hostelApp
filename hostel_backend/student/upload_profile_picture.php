<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();
} catch (Exception $e) {
    echo json_encode(['success' => false, 'message' => 'Database connection failed: ' . $e->getMessage()]);
    exit();
}

// 0. Ensure table user_profile_photos exists
try {
    $db->exec("CREATE TABLE IF NOT EXISTS `user_profile_photos` (
      `id` INT AUTO_INCREMENT PRIMARY KEY,
      `username` VARCHAR(100) NOT NULL UNIQUE,
      `photo_url` VARCHAR(255) NOT NULL,
      `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX (`username`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;");
} catch (Exception $eTbl) {
    // Continue even if table creation encounters permissions
}

$uploadDir = __DIR__ . '/../uploads/profiles/';
if (!file_exists($uploadDir)) {
    @mkdir($uploadDir, 0777, true);
}

// 1. Read input params
$regNo = $_POST['reg_no'] ?? $_POST['username'] ?? $_POST['student_id'] ?? null;
$action = $_POST['action'] ?? null;
$base64Data = $_POST['image_base64'] ?? $_POST['base64'] ?? $_POST['image'] ?? null;

if (empty($regNo) || (empty($action) && empty($base64Data))) {
    $rawInput = file_get_contents('php://input');
    $jsonData = json_decode($rawInput, true);
    if (is_array($jsonData)) {
        $regNo = $regNo ?? $jsonData['reg_no'] ?? $jsonData['username'] ?? $jsonData['student_id'] ?? null;
        $action = $action ?? $jsonData['action'] ?? null;
        $base64Data = $base64Data ?? $jsonData['base64'] ?? $jsonData['image_base64'] ?? $jsonData['image'] ?? null;
    }
}

require_once __DIR__ . '/../utils/auth_helper.php';
$authUser = requireAuth();

if (empty($regNo)) {
    echo json_encode(['success' => false, 'message' => 'Registration number or username is required']);
    exit();
}

// If caller is student, bind to authenticated student username
if (strtolower($authUser['role'] ?? '') === 'student') {
    $regNo = $authUser['username'];
}

$cleanReg = preg_replace('/[^A-Za-z0-9_-]/', '', (string)$regNo);
$isNumeric = ctype_digit((string)$regNo);

// 2. Handle Remove Action
if ($action === 'remove' || $action === 'delete') {
    try {
        $defaultPic = 'profile.png';

        // Remove from user_profile_photos table
        try {
            $delStmt = $db->prepare("DELETE FROM user_profile_photos WHERE username = :u");
            $delStmt->execute([':u' => $regNo]);
        } catch (Exception $eDel) {}

        // Safely update users & profile without string-to-int comparison errors
        if ($isNumeric) {
            $upUsers = $db->prepare("UPDATE users SET profileimage = :pic, profileimagestatus = 0 WHERE username = :reg OR id = :regId");
            $upUsers->execute([':pic' => $defaultPic, ':reg' => $regNo, ':regId' => (int)$regNo]);

            $upProfile = $db->prepare("UPDATE profile SET profile_pic = :pic WHERE reg_no = :reg OR user_id = :regId");
            $upProfile->execute([':pic' => $defaultPic, ':reg' => $regNo, ':regId' => (int)$regNo]);
        } else {
            $upUsers = $db->prepare("UPDATE users SET profileimage = :pic, profileimagestatus = 0 WHERE username = :reg");
            $upUsers->execute([':pic' => $defaultPic, ':reg' => $regNo]);

            $upProfile = $db->prepare("UPDATE profile SET profile_pic = :pic WHERE reg_no = :reg");
            $upProfile->execute([':pic' => $defaultPic, ':reg' => $regNo]);
        }

        echo json_encode([
            'success' => true,
            'message' => 'Profile picture removed successfully',
            'profile_pic' => $defaultPic,
            'is_default' => true
        ]);
        exit();
    } catch (Exception $e) {
        echo json_encode(['success' => false, 'message' => 'Failed to remove profile picture: ' . $e->getMessage()]);
        exit();
    }
}

// 3. Handle File Upload (Multipart Form Data)
$savedFileName = null;
$fileUploaded = false;

$uploadedFile = $_FILES['profile_photo'] ?? $_FILES['image'] ?? $_FILES['file'] ?? null;

if ($uploadedFile && isset($uploadedFile['tmp_name']) && $uploadedFile['error'] === UPLOAD_ERR_OK) {
    $fileTmpPath = $uploadedFile['tmp_name'];
    $originalName = $uploadedFile['name'];
    $fileExtension = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));

    $allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];
    if (!in_array($fileExtension, $allowedExtensions)) {
        $fileExtension = 'jpg';
    }

    $savedFileName = 'profile_' . $cleanReg . '_' . time() . '_' . rand(100, 999) . '.' . $fileExtension;
    $destPath = $uploadDir . $savedFileName;

    if (move_uploaded_file($fileTmpPath, $destPath)) {
        $fileUploaded = true;
    }
}

// 4. Handle Base64 Upload Fallback
if (!$fileUploaded && !empty($base64Data)) {
    $ext = 'jpg';
    if (preg_match('/^data:image\/(\w+);base64,/', $base64Data, $type)) {
        $base64Data = substr($base64Data, strpos($base64Data, ',') + 1);
        $extCandidate = strtolower($type[1]);
        if (in_array($extCandidate, ['jpg', 'jpeg', 'png', 'webp'])) {
            $ext = $extCandidate;
        }
    }

    $decoded = base64_decode($base64Data);
    if ($decoded !== false && strlen($decoded) > 0) {
        $savedFileName = 'profile_' . $cleanReg . '_' . time() . '_' . rand(100, 999) . '.' . $ext;
        $destPath = $uploadDir . $savedFileName;
        if (file_put_contents($destPath, $decoded) !== false) {
            $fileUploaded = true;
        }
    }
}

if (!$fileUploaded || empty($savedFileName)) {
    echo json_encode(['success' => false, 'message' => 'No image file or valid image data received']);
    exit();
}

// 5. Update Database Records
$relativePath = 'uploads/profiles/' . $savedFileName;

try {
    // 1. Store in user_profile_photos table
    try {
        $upsert = $db->prepare("INSERT INTO user_profile_photos (username, photo_url) VALUES (:u, :p) ON DUPLICATE KEY UPDATE photo_url = VALUES(photo_url), updated_at = NOW()");
        $upsert->execute([':u' => $regNo, ':p' => $relativePath]);
    } catch (Exception $eUpsert) {}

    // 2. Update users and profile tables safely
    if ($isNumeric) {
        $upUsers = $db->prepare("UPDATE users SET profileimage = :pic, profileimagestatus = 1 WHERE username = :reg OR id = :regId");
        $upUsers->execute([':pic' => $relativePath, ':reg' => $regNo, ':regId' => (int)$regNo]);

        $upProfile = $db->prepare("UPDATE profile SET profile_pic = :pic WHERE reg_no = :reg OR user_id = :regId");
        $upProfile->execute([':pic' => $relativePath, ':reg' => $regNo, ':regId' => (int)$regNo]);
    } else {
        $upUsers = $db->prepare("UPDATE users SET profileimage = :pic, profileimagestatus = 1 WHERE username = :reg");
        $upUsers->execute([':pic' => $relativePath, ':reg' => $regNo]);

        $upProfile = $db->prepare("UPDATE profile SET profile_pic = :pic WHERE reg_no = :reg");
        $upProfile->execute([':pic' => $relativePath, ':reg' => $regNo]);
    }

    echo json_encode([
        'success' => true,
        'message' => 'Profile picture updated successfully',
        'profile_pic' => $relativePath
    ]);
} catch (Exception $e) {
    echo json_encode(['success' => false, 'message' => 'Database update error: ' . $e->getMessage()]);
}
