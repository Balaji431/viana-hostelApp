<?php
/**
 * Admin API: Set or clear the email_override flag for a student.
 * 
 * When email_override = 1: The 15-minute sync will NOT overwrite
 * that student's email or phone_number from the external API.
 * 
 * POST body (JSON):
 * {
 *   "username": "192511250",   // student roll number / username
 *   "email_override": 1,       // 1 = protect, 0 = allow API to sync
 *   "new_email": "test@apple.com"  // optional: also update the email
 * }
 * 
 * GET ?username=192511250 → returns current override status
 */

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/auth_helper.php';

$authUser = requireAuth(['admin', 'super_admin']);

try {
    $db = (new Database())->getConnection();

    if ($_SERVER['REQUEST_METHOD'] === 'GET') {
        $username = trim($_GET['username'] ?? '');
        if (empty($username)) {
            echo json_encode(['success' => false, 'message' => 'username is required']);
            exit();
        }
        $stmt = $db->prepare("SELECT username, email, phone_number, email_override FROM users WHERE username = ?");
        $stmt->execute([$username]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            echo json_encode(['success' => false, 'message' => "Student '$username' not found"]);
            exit();
        }
        echo json_encode(['success' => true, 'data' => $row]);
        exit();
    }

    // POST
    $body = json_decode(file_get_contents('php://input'), true) ?? [];
    $username = trim($body['username'] ?? '');
    $overrideFlag = isset($body['email_override']) ? (int)$body['email_override'] : null;
    $newEmail = isset($body['new_email']) ? trim($body['new_email']) : null;

    if (empty($username)) {
        echo json_encode(['success' => false, 'message' => 'username is required']);
        exit();
    }
    if ($overrideFlag === null) {
        echo json_encode(['success' => false, 'message' => 'email_override (0 or 1) is required']);
        exit();
    }

    // Build dynamic update
    if (!empty($newEmail)) {
        $stmt = $db->prepare("UPDATE users SET email_override = ?, email = ? WHERE username = ?");
        $stmt->execute([$overrideFlag, $newEmail, $username]);
        // Also update profile
        $db->prepare("UPDATE profile SET email = ? WHERE reg_no = ?")->execute([$newEmail, $username]);
    } else {
        $stmt = $db->prepare("UPDATE users SET email_override = ? WHERE username = ?");
        $stmt->execute([$overrideFlag, $username]);
    }

    if ($stmt->rowCount() === 0) {
        echo json_encode(['success' => false, 'message' => "Student '$username' not found or no change made"]);
        exit();
    }

    echo json_encode([
        'success' => true,
        'message' => $overrideFlag === 1
            ? "Email override ENABLED for '$username'. API sync will no longer overwrite their email."
            : "Email override DISABLED for '$username'. API sync will resume updating their email.",
        'email_updated' => !empty($newEmail) ? $newEmail : null
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => $e->getMessage()]);
}
?>
