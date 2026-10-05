<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/auth_helper.php';
require_once __DIR__ . '/db_helper.php';

$authUser = requireAuth(['it', 'admin', 'super_admin', 'warden']);

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

ensureBiometricAuditTables($db);

$q = trim($_GET['query'] ?? $_GET['q'] ?? $_POST['query'] ?? '');
$statusFilter = strtolower(trim($_GET['status'] ?? $_POST['status'] ?? 'all')); // all, synced, not_synced
$hostelFilter = trim($_GET['hostel'] ?? $_POST['hostel'] ?? '');
$page = max(1, (int)($_GET['page'] ?? $_POST['page'] ?? 1));
$limit = max(1, min(100, (int)($_GET['limit'] ?? $_POST['limit'] ?? 20)));
$offset = ($page - 1) * $limit;

try {
    $where = ["u.role = 'student'"];
    $params = [];

    if (!empty($q)) {
        $where[] = "(u.username LIKE ? OR u.full_name LIKE ? OR u.email LIKE ? OR u.RoomId LIKE ? OR bss.room_allocation LIKE ? OR bnss.room_allocation LIKE ? OR p.room_allocation LIKE ?)";
        $wildcard = "%$q%";
        $params[] = $wildcard;
        $params[] = $wildcard;
        $params[] = $wildcard;
        $params[] = $wildcard;
        $params[] = $wildcard;
        $params[] = $wildcard;
        $params[] = $wildcard;
    }

    if (!empty($hostelFilter) && strtolower($hostelFilter) !== 'all') {
        $where[] = "(COALESCE(bss.hostel_name, bnss.hostel_name, p.hostel_name, u.HostelName) = ?)";
        $params[] = $hostelFilter;
    }

    if ($statusFilter === 'synced') {
        $where[] = "bss.id IS NOT NULL";
    } elseif ($statusFilter === 'not_synced') {
        $where[] = "bss.id IS NULL";
    }

    $whereSql = implode(" AND ", $where);

    // Count query
    $countSql = "
        SELECT COUNT(DISTINCT u.id)
        FROM users u
        LEFT JOIN biometric_synced_students bss ON u.username COLLATE utf8mb4_general_ci = bss.register_no COLLATE utf8mb4_general_ci
        LEFT JOIN biometric_not_synced_students bnss ON u.username COLLATE utf8mb4_general_ci = bnss.register_no COLLATE utf8mb4_general_ci
        LEFT JOIN profile p ON u.username COLLATE utf8mb4_general_ci = p.reg_no COLLATE utf8mb4_general_ci
        WHERE $whereSql
    ";
    $countStmt = $db->prepare($countSql);
    $countStmt->execute($params);
    $totalRecords = (int)$countStmt->fetchColumn();

    // Data query
    $dataSql = "
        SELECT 
            u.id as user_id,
            u.username as register_no,
            u.full_name,
            u.email,
            COALESCE(bss.hostel_name, bnss.hostel_name, p.hostel_name, u.HostelName, 'N/A') as hostel_name,
            COALESCE(bss.room_allocation, bnss.room_allocation, p.room_allocation, u.RoomId, 'N/A') as room_allocation,
            p.personal_phone as phone,
            p.profile_pic,
            CASE WHEN bss.id IS NOT NULL THEN 1 ELSE 0 END as is_synced,
            COALESCE(bss.records_found, 0) as records_found,
            bss.last_attendance_date,
            COALESCE(bss.last_checked_at, bnss.last_checked_at) as last_checked_at,
            COALESCE(bss.biometric_id, bnss.biometric_id, u.biometric_id) as biometric_id,
            COALESCE(bss.notes, bnss.notes) as notes
        FROM users u
        LEFT JOIN biometric_synced_students bss ON u.username COLLATE utf8mb4_general_ci = bss.register_no COLLATE utf8mb4_general_ci
        LEFT JOIN biometric_not_synced_students bnss ON u.username COLLATE utf8mb4_general_ci = bnss.register_no COLLATE utf8mb4_general_ci
        LEFT JOIN profile p ON u.username COLLATE utf8mb4_general_ci = p.reg_no COLLATE utf8mb4_general_ci
        WHERE $whereSql
        ORDER BY 
            CASE WHEN bss.id IS NOT NULL THEN 0 WHEN bnss.id IS NOT NULL THEN 1 ELSE 2 END,
            u.full_name ASC
        LIMIT $limit OFFSET $offset
    ";

    $dataStmt = $db->prepare($dataSql);
    $dataStmt->execute($params);
    $students = $dataStmt->fetchAll(PDO::FETCH_ASSOC);

    // Format output boolean
    foreach ($students as &$s) {
        $s['is_synced'] = ($s['is_synced'] == 1);
    }

    // List of hostels for filter dropdown
    $hostelList = $db->query("
        SELECT DISTINCT COALESCE(NULLIF(TRIM(HostelName), ''), 'Unallocated') as hostel 
        FROM users 
        WHERE role = 'student' AND HostelName IS NOT NULL AND HostelName != ''
        ORDER BY hostel ASC
    ")->fetchAll(PDO::FETCH_COLUMN);

    echo json_encode([
        "success" => true,
        "data" => $students,
        "pagination" => [
            "total" => $totalRecords,
            "page" => $page,
            "limit" => $limit,
            "total_pages" => ceil($totalRecords / $limit)
        ],
        "hostels" => $hostelList
    ]);

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
