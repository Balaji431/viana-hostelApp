<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

$database = new Database();
$db = $database->getConnection();

// Default retention days for active table (e.g. 45 days)
$days = isset($_GET['days']) ? (int)$_GET['days'] : 45;
if ($days < 7) $days = 7; // Safety minimum: never archive less than 7 days

try {
    // 1. Ensure Archive Table Exists with identical structure
    $createArchiveTable = "
        CREATE TABLE IF NOT EXISTS `chat_messages_archive` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `request_id` varchar(100) DEFAULT NULL,
            `sender_id` varchar(100) DEFAULT NULL,
            `receiver_id` varchar(100) DEFAULT NULL,
            `message` text DEFAULT NULL,
            `message_type` varchar(50) DEFAULT 'text',
            `status` varchar(20) DEFAULT 'sent',
            `timestamp` datetime DEFAULT current_timestamp(),
            `archived_at` datetime DEFAULT current_timestamp(),
            PRIMARY KEY (`id`),
            KEY `idx_archive_request` (`request_id`),
            KEY `idx_archive_timestamp` (`timestamp`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ";
    $db->exec($createArchiveTable);

    // 2. Count rows before archiving
    $countStmt = $db->query("SELECT COUNT(*) as total FROM chat_messages");
    $totalBefore = (int)$countStmt->fetch(PDO::FETCH_ASSOC)['total'];

    // 3. Move old messages OR messages belonging to resolved/closed requests
    $archiveQuery = "
        INSERT INTO chat_messages_archive (id, request_id, sender_id, receiver_id, message, message_type, status, timestamp)
        SELECT m.id, m.request_id, m.sender_id, m.receiver_id, m.message, m.message_type, m.status, m.timestamp
        FROM chat_messages m
        LEFT JOIN request1 r ON (CONVERT(m.request_id USING utf8mb4) = CONVERT(r.request_id USING utf8mb4))
        WHERE m.timestamp < DATE_SUB(NOW(), INTERVAL ? DAY)
           OR LOWER(r.status) IN ('resolved', 'closed', 'rejected', 'completed')
        ON DUPLICATE KEY UPDATE chat_messages_archive.archived_at = NOW();
    ";
    $stmtArchive = $db->prepare($archiveQuery);
    $stmtArchive->execute([$days]);
    $archivedCount = $stmtArchive->rowCount();

    // 4. Delete archived messages from active table
    $deleteQuery = "
        DELETE m FROM chat_messages m
        INNER JOIN chat_messages_archive a ON m.id = a.id
    ";
    $stmtDelete = $db->query($deleteQuery);
    $deletedCount = $stmtDelete->rowCount();

    // 5. Count rows after archiving
    $countAfterStmt = $db->query("SELECT COUNT(*) as total FROM chat_messages");
    $totalAfter = (int)$countAfterStmt->fetch(PDO::FETCH_ASSOC)['total'];

    // 6. Optimize table to reclaim OS disk space
    try {
        $db->query("OPTIMIZE TABLE chat_messages");
    } catch (\Throwable $t) {}

    echo json_encode([
        "success" => true,
        "message" => "Chat messages archived successfully",
        "retention_days" => $days,
        "stats" => [
            "total_before" => $totalBefore,
            "archived_rows" => $deletedCount,
            "active_remaining" => $totalAfter,
            "storage_reduction_percent" => $totalBefore > 0 ? round(($deletedCount / $totalBefore) * 100, 1) . '%' : '0%'
        ]
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "success" => false,
        "message" => "Archiving failed: " . $e->getMessage()
    ]);
}
?>
