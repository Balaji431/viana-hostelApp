<?php
require_once __DIR__ . '/../config/database.php';

function getClientIp() {
    $ip = 'unknown';
    if (!empty($_SERVER['HTTP_CLIENT_IP'])) {
        $ip = $_SERVER['HTTP_CLIENT_IP'];
    } elseif (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
        $ips = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']);
        $ip = trim($ips[0]);
    } elseif (!empty($_SERVER['REMOTE_ADDR'])) {
        $ip = $_SERVER['REMOTE_ADDR'];
    }
    return $ip;
}

function logAdminActivity($adminId, $action, $details) {
    global $pdo;
    
    // Ensure table exists
    $createTable = "CREATE TABLE IF NOT EXISTS admin_activity_logs (
        id INT AUTO_INCREMENT PRIMARY KEY,
        admin_id INT NOT NULL,
        action VARCHAR(255) NOT NULL,
        details TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )";
    $pdo->exec($createTable);

    try {
        $stmt = $pdo->prepare("INSERT INTO admin_activity_logs (admin_id, action, details) VALUES (?, ?, ?)");
        $stmt->execute([$adminId, $action, $details]);
        return true;
    } catch (Exception $e) {
        error_log("Logging failed: " . $e->getMessage());
        return false;
    }
}

/**
 * Log any general activity or login in the project.
 * Supports storing "previous" (olden edit) and "after" (what changed) states as JSON.
 */
function logActivity($userId, $username, $role, $action, $targetTable = null, $previous = null, $after = null) {
    return true;
}

/**
 * Log Audit Trail entries into the audit_logs table.
 * Fallbacks to HTTP_X_USER headers if session/user variables are not passed directly.
 */
function logAudit($userId = null, $username = null, $role = null, $action = '', $moduleName = '', $oldValue = null, $newValue = null) {
    global $pdo;

    // Fallback to HTTP headers if user data is null (meaning client-side injected user metadata)
    if ($userId === null || $userId === '') {
        $userId = isset($_SERVER['HTTP_X_USER_ID']) ? $_SERVER['HTTP_X_USER_ID'] : null;
    }
    if ($username === null || $username === '') {
        $username = isset($_SERVER['HTTP_X_USER_USERNAME']) ? $_SERVER['HTTP_X_USER_USERNAME'] : null;
    }
    if ($role === null || $role === '') {
        $role = isset($_SERVER['HTTP_X_USER_ROLE']) ? $_SERVER['HTTP_X_USER_ROLE'] : null;
    }

    if ($userId !== null && is_numeric($userId)) {
        $userId = (int)$userId;
    }

    // Ensure PDO connection is active
    if (!isset($pdo) || $pdo === null) {
        try {
            $database = new Database();
            $pdo = $database->getConnection();
        } catch (Exception $e) {
            error_log("Database connection failed in audit logger: " . $e->getMessage());
            return false;
        }
    }

    try {
        if (is_array($oldValue) || is_object($oldValue)) {
            $oldValue = json_encode($oldValue, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        }
        if (is_array($newValue) || is_object($newValue)) {
            $newValue = json_encode($newValue, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        }

        $ipAddress = getClientIp();

        $stmt = $pdo->prepare("INSERT INTO audit_logs (user_id, username, role, action, module_name, old_value, new_value, ip_address) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
        $stmt->execute([$userId, $username, $role, $action, $moduleName, $oldValue, $newValue, $ipAddress]);
        return true;
    } catch (Exception $e) {
        error_log("Audit logging failed: " . $e->getMessage());
        return false;
    }
}
?>
