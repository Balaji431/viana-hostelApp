<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json; charset=UTF-8");

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/auth_helper.php';

$authUser = requireAuth(['admin', 'super_admin', 'warden', 'maintenance', 'it']);

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $status = isset($_GET['status']) ? trim($_GET['status']) : 'all';
    $hostelName = isset($_GET['hostel_name']) ? trim($_GET['hostel_name']) : '';
    $roomNo = isset($_GET['room_no']) ? trim($_GET['room_no']) : '';
    $recordedBy = isset($_GET['recorded_by']) ? trim($_GET['recorded_by']) : '';
    $page = isset($_GET['page']) ? max(1, (int)$_GET['page']) : 1;
    $limit = isset($_GET['limit']) ? max(1, (int)$_GET['limit']) : 50;
    $offset = ($page - 1) * $limit;

    $where = ["1=1"];
    $params = [];

    if (!empty($status) && $status !== 'all') {
        $where[] = "r.status = ?";
        $params[] = $status;
    }

    if (!empty($hostelName)) {
        $where[] = "(r.hostel_name = ? OR r.building_code = ?)";
        $params[] = $hostelName;
        $params[] = $hostelName;
    }

    if (!empty($roomNo)) {
        $where[] = "r.room_no LIKE ?";
        $params[] = "%$roomNo%";
    }

    if (!empty($recordedBy)) {
        $where[] = "r.recorded_by = ?";
        $params[] = $recordedBy;
    }

    $whereSQL = implode(" AND ", $where);

    // 1. Fetch paginated rows
    $sql = "
        SELECT 
            r.*,
            b.id as bill_id,
            b.total_amount as billed_amount,
            b.rate_per_unit,
            b.penalty_amount,
            b.created_at as billed_at
        FROM eb_meter_readings r
        LEFT JOIN eb_bills b ON b.reading_id = r.id
        WHERE $whereSQL
        ORDER BY r.id DESC
        LIMIT $limit OFFSET $offset
    ";

    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $readings = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // 2. Count total matching
    $countStmt = $db->prepare("SELECT COUNT(*) as total FROM eb_meter_readings r WHERE $whereSQL");
    $countStmt->execute($params);
    $totalCount = (int)($countStmt->fetch(PDO::FETCH_ASSOC)['total'] ?? 0);

    // 3. Overview metrics (for admin dashboard stats)
    $metricsStmt = $db->query("
        SELECT 
            COUNT(*) as total_inspections,
            SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending_count,
            SUM(CASE WHEN status = 'billed' THEN 1 ELSE 0 END) as billed_count,
            SUM(CASE WHEN watts >= 1500 THEN 1 ELSE 0 END) as high_load_count,
            COALESCE(SUM(units_consumed), 0) as total_units
        FROM eb_meter_readings
    ");
    $metrics = $metricsStmt->fetch(PDO::FETCH_ASSOC);

    echo json_encode([
        "status" => "success",
        "data" => $readings,
        "total" => $totalCount,
        "page" => $page,
        "limit" => $limit,
        "metrics" => [
            "total_inspections" => (int)($metrics['total_inspections'] ?? 0),
            "pending_count" => (int)($metrics['pending_count'] ?? 0),
            "billed_count" => (int)($metrics['billed_count'] ?? 0),
            "high_load_count" => (int)($metrics['high_load_count'] ?? 0),
            "total_units" => (float)($metrics['total_units'] ?? 0.0)
        ]
    ]);
} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "message" => $e->getMessage()
    ]);
}
