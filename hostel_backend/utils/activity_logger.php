<?php
require_once __DIR__ . '/../config/database.php';

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
    global $pdo;
    
    // Ensure PDO connection is active
    if (!isset($pdo) || $pdo === null) {
        try {
            $database = new Database();
            $pdo = $database->getConnection();
        } catch (Exception $e) {
            error_log("Database connection failed in logger: " . $e->getMessage());
            return false;
        }
    }

    try {
        // If previous or after is an array/object, convert to JSON
        if (is_array($previous) || is_object($previous)) {
            $previous = json_encode($previous, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        }
        if (is_array($after) || is_object($after)) {
            $after = json_encode($after, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        }

        $stmt = $pdo->prepare("INSERT INTO activity_logs (user_id, username, role, action, target_table, previous, after) VALUES (?, ?, ?, ?, ?, ?, ?)");
        $stmt->execute([$userId, $username, $role, $action, $targetTable, $previous, $after]);
        return true;
    } catch (Exception $e) {
        error_log("Logging failed: " . $e->getMessage());
        return false;
    }
}
?>
