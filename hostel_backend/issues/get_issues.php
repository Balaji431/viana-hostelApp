<?php
ini_set('display_errors', 0);
error_reporting(E_ALL);

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
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
} catch (Exception $e) {}

$roleFilter = isset($_GET['role']) ? trim(strtolower($_GET['role'])) : '';
$statusFilter = isset($_GET['status']) ? trim($_GET['status']) : '';
$search = isset($_GET['search']) ? trim($_GET['search']) : '';
$limit = isset($_GET['limit']) ? intval($_GET['limit']) : 100;
$offset = isset($_GET['offset']) ? intval($_GET['offset']) : 0;

try {
    // 1. Calculate role and status counts for Super Admin Dashboard KPI
    $countQuery = "SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN LOWER(user_role) = 'student' THEN 1 ELSE 0 END) as student_count,
        SUM(CASE WHEN LOWER(user_role) = 'warden' THEN 1 ELSE 0 END) as warden_count,
        SUM(CASE WHEN LOWER(user_role) = 'it' OR LOWER(user_role) = 'it_department' THEN 1 ELSE 0 END) as it_count,
        SUM(CASE WHEN LOWER(user_role) = 'security' THEN 1 ELSE 0 END) as security_count,
        SUM(CASE WHEN LOWER(user_role) = 'admin' THEN 1 ELSE 0 END) as admin_count,
        SUM(CASE WHEN LOWER(user_role) = 'maintenance' THEN 1 ELSE 0 END) as maintenance_count,
        SUM(CASE WHEN LOWER(status) = 'pending' THEN 1 ELSE 0 END) as pending_count,
        SUM(CASE WHEN LOWER(status) = 'in progress' THEN 1 ELSE 0 END) as in_progress_count,
        SUM(CASE WHEN LOWER(status) = 'resolved' THEN 1 ELSE 0 END) as resolved_count
        FROM `issues`";
    $countStmt = $db->query($countQuery);
    $countsRow = $countStmt->fetch(PDO::FETCH_ASSOC);

    $counts = [
        'total' => intval($countsRow['total'] ?? 0),
        'student' => intval($countsRow['student_count'] ?? 0),
        'warden' => intval($countsRow['warden_count'] ?? 0),
        'it' => intval($countsRow['it_count'] ?? 0),
        'security' => intval($countsRow['security_count'] ?? 0),
        'admin' => intval($countsRow['admin_count'] ?? 0),
        'maintenance' => intval($countsRow['maintenance_count'] ?? 0),
        'pending' => intval($countsRow['pending_count'] ?? 0),
        'in_progress' => intval($countsRow['in_progress_count'] ?? 0),
        'resolved' => intval($countsRow['resolved_count'] ?? 0),
    ];

    // 2. Fetch filtered issues
    $where = [];
    $params = [];

    if (!empty($roleFilter) && $roleFilter !== 'all') {
        if ($roleFilter === 'it') {
            $where[] = "(LOWER(user_role) = 'it' OR LOWER(user_role) = 'it_department')";
        } else {
            $where[] = "LOWER(user_role) = :role";
            $params[':role'] = $roleFilter;
        }
    }

    if (!empty($statusFilter) && strtolower($statusFilter) !== 'all') {
        $where[] = "LOWER(status) = :status";
        $params[':status'] = strtolower($statusFilter);
    }

    if (!empty($search)) {
        $where[] = "(username LIKE :search OR user_name LIKE :search OR issue_description LIKE :search OR email LIKE :search)";
        $params[':search'] = '%' . $search . '%';
    }

    $whereClause = !empty($where) ? 'WHERE ' . implode(' AND ', $where) : '';
    $dataQuery = "SELECT id, user_id, username, user_name, user_role, email, phone, hostel_name, room_no, issue_description, attachment_url, attachment_type, attachment_name, status, admin_notes, created_at, updated_at 
                  FROM `issues` 
                  $whereClause 
                  ORDER BY created_at DESC 
                  LIMIT :limit OFFSET :offset";

    $stmt = $db->prepare($dataQuery);
    foreach ($params as $key => $val) {
        $stmt->bindValue($key, $val);
    }
    $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
    $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
    $stmt->execute();

    $issues = $stmt->fetchAll(PDO::FETCH_ASSOC);

    sendResponse(true, "Issues fetched successfully", [
        'issues' => $issues,
        'counts' => $counts
    ]);

} catch (Exception $e) {
    sendResponse(false, "Database error: " . $e->getMessage(), null, 500);
}
