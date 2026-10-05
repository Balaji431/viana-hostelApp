<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/db_helper.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

ensureBiometricAuditTables($db);

try {
    // Total students in users table
    $totalStudents = (int)$db->query("SELECT COUNT(*) FROM users WHERE LOWER(role) = 'student'")->fetchColumn();

    // Table 1: Synced students count
    $syncedCount = (int)$db->query("SELECT COUNT(*) FROM biometric_synced_students")->fetchColumn();

    // Table 2: Not synced students count
    $notSyncedAudited = (int)$db->query("SELECT COUNT(*) FROM biometric_not_synced_students")->fetchColumn();

    // Total audited across both tables
    $totalAudited = $syncedCount + $notSyncedAudited;
    $notSyncedCount = $notSyncedAudited;

    // If some students haven't been audited yet, they count toward not_synced
    if ($totalStudents > $totalAudited) {
        $notSyncedCount += ($totalStudents - $totalAudited);
    }

    $effectiveTotal = max($totalStudents, $totalAudited);
    $syncPercentage = $effectiveTotal > 0 ? round(($syncedCount / $effectiveTotal) * 100, 1) : 0;

    // Hostel-wise breakdown combining both tables
    $hostelStmt = $db->query("
        SELECT 
            hostel,
            SUM(total) as total,
            SUM(synced) as synced,
            SUM(not_synced) as not_synced
        FROM (
            SELECT 
                COALESCE(NULLIF(TRIM(hostel_name), ''), 'Unallocated') as hostel,
                COUNT(*) as total,
                COUNT(*) as synced,
                0 as not_synced
            FROM biometric_synced_students
            GROUP BY COALESCE(NULLIF(TRIM(hostel_name), ''), 'Unallocated')
            
            UNION ALL
            
            SELECT 
                COALESCE(NULLIF(TRIM(hostel_name), ''), 'Unallocated') as hostel,
                COUNT(*) as total,
                0 as synced,
                COUNT(*) as not_synced
            FROM biometric_not_synced_students
            GROUP BY COALESCE(NULLIF(TRIM(hostel_name), ''), 'Unallocated')
        ) combined
        GROUP BY hostel
        ORDER BY total DESC
    ");
    $hostelBreakdown = $hostelStmt->fetchAll(PDO::FETCH_ASSOC);
    foreach ($hostelBreakdown as &$hb) {
        $hb['total'] = (int)($hb['total'] ?? 0);
        $hb['synced'] = (int)($hb['synced'] ?? 0);
        $hb['not_synced'] = (int)($hb['not_synced'] ?? 0);
    }

    // Last sync timestamp
    $lastSyncTime = $db->query("
        SELECT MAX(last_time) FROM (
            SELECT MAX(last_checked_at) as last_time FROM biometric_synced_students
            UNION ALL
            SELECT MAX(last_checked_at) as last_time FROM biometric_not_synced_students
        ) t
    ")->fetchColumn() ?: null;

    // Recent activity (latest 10 checked students from both tables)
    $recentStmt = $db->query("
        (
            SELECT register_no, full_name, hostel_name, room_allocation, 1 as is_synced, records_found, last_checked_at
            FROM biometric_synced_students
        )
        UNION ALL
        (
            SELECT register_no, full_name, hostel_name, room_allocation, 0 as is_synced, 0 as records_found, last_checked_at
            FROM biometric_not_synced_students
        )
        ORDER BY last_checked_at DESC
        LIMIT 10
    ");
    $recentActivity = $recentStmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "success" => true,
        "data" => [
            "total_students" => $effectiveTotal,
            "synced_count" => $syncedCount,
            "not_synced_count" => $notSyncedCount,
            "sync_percentage" => $syncPercentage,
            "total_audited" => $totalAudited,
            "last_synced_at" => $lastSyncTime,
            "hostel_breakdown" => $hostelBreakdown,
            "recent_activity" => $recentActivity
        ]
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
