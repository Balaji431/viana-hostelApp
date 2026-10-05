<?php
/**
 * cleanup_audit_logs.php
 *
 * Automated retention cleanup for student_audit_logs:
 * - LOGIN_FAILED: retained for 7 days
 * - All other actions (LOGIN_SUCCESS, Requests, Allocations, Payments, etc.): retained for 30 days
 *
 * Usage:
 *   php cleanup_audit_logs.php            (Executes deletion)
 *   php cleanup_audit_logs.php --dry-run  (Counts rows without deleting)
 */

if (php_sapi_name() !== 'cli') {
    http_response_code(403);
    die(json_encode(['status' => 'error', 'message' => 'CLI only']));
}

$isDryRun = in_array('--dry-run', $argv ?? []);

$dbFile = __DIR__ . '/../config/database.php';
if (!file_exists($dbFile)) {
    $dbFile = '/var/www/html/config/database.php';
}
require_once $dbFile;

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo "[" . date('Y-m-d H:i:s') . "] ERROR: Database connection failed.\n";
    exit(1);
}

echo "[" . date('Y-m-d H:i:s') . "] === Starting Audit Log Retention Cleanup ===\n";
if ($isDryRun) {
    echo "[" . date('Y-m-d H:i:s') . "] MODE: DRY RUN (No rows will be deleted)\n";
}

try {
    $totalBefore = (int)$db->query("SELECT COUNT(*) FROM student_audit_logs")->fetchColumn();
    echo "[" . date('Y-m-d H:i:s') . "] Total rows before cleanup: {$totalBefore}\n";

    // 1. Check candidate counts by action
    $countSql = "
        SELECT action, module_name, COUNT(*) as cnt, MIN(created_at) as oldest, MAX(created_at) as newest
        FROM student_audit_logs
        WHERE (action = 'LOGIN_FAILED' AND created_at < NOW() - INTERVAL 7 DAY)
           OR (action != 'LOGIN_FAILED' AND created_at < NOW() - INTERVAL 30 DAY)
        GROUP BY action, module_name
        ORDER BY cnt DESC
    ";
    $stmt = $db->query($countSql);
    $rowsToDelete = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $totalCandidates = 0;
    echo "--- Candidate Rows to Delete ---\n";
    foreach ($rowsToDelete as $row) {
        $totalCandidates += (int)$row['cnt'];
        echo sprintf("  %-25s | %-20s | Count: %-5d | Range: %s -> %s\n",
            $row['action'], $row['module_name'], $row['cnt'], $row['oldest'], $row['newest']);
    }

    if ($totalCandidates === 0) {
        echo "No records match retention expiration criteria.\n";
        exit(0);
    }

    echo "[" . date('Y-m-d H:i:s') . "] Total candidate rows to delete: {$totalCandidates}\n";

    if ($isDryRun) {
        echo "[" . date('Y-m-d H:i:s') . "] Dry run complete. Exiting without deleting.\n";
        exit(0);
    }

    // 2. Perform deletion
    $delSql = "
        DELETE FROM student_audit_logs
        WHERE (action = 'LOGIN_FAILED' AND created_at < NOW() - INTERVAL 7 DAY)
           OR (action != 'LOGIN_FAILED' AND created_at < NOW() - INTERVAL 30 DAY)
    ";
    $delStmt = $db->prepare($delSql);
    $delStmt->execute();
    $deletedCount = $delStmt->rowCount();

    $totalAfter = (int)$db->query("SELECT COUNT(*) FROM student_audit_logs")->fetchColumn();

    echo "[" . date('Y-m-d H:i:s') . "] Successfully deleted: {$deletedCount} rows\n";
    echo "[" . date('Y-m-d H:i:s') . "] Total rows after cleanup: {$totalAfter}\n";
    echo "[" . date('Y-m-d H:i:s') . "] === Cleanup Finished Successfully ===\n";

} catch (Exception $e) {
    echo "[" . date('Y-m-d H:i:s') . "] ERROR: " . $e->getMessage() . "\n";
    exit(1);
}
