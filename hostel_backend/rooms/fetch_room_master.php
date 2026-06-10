<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json");
// Enable gzip output compression on the PHP level for large payloads
if (extension_loaded('zlib') && !ob_get_level()) {
    ob_start('ob_gzhandler');
}

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once '../config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();

    $locationFilter = isset($_GET['location_name']) ? $_GET['location_name'] : '';
    $buildingFilter = isset($_GET['building_code']) ? $_GET['building_code'] : '';
    $floorFilter    = isset($_GET['floor_no'])      ? $_GET['floor_no']      : '';
    $roomTypeFilter = isset($_GET['room_type'])     ? $_GET['room_type']     : '';
    $searchFilter   = isset($_GET['search'])        ? $_GET['search']        : '';

    // Pagination support — default: return all (page=0 disables pagination)
    $page     = isset($_GET['page'])  ? max(0, (int)$_GET['page'])  : 0;
    $per_page = isset($_GET['limit']) ? max(1, (int)$_GET['limit']) : 500;

    $sql    = "SELECT * FROM room_master WHERE 1=1";
    $params = [];

    if (!empty($locationFilter)) {
        $sql    .= " AND location_name = ?";
        $params[] = $locationFilter;
    }

    if (!empty($buildingFilter)) {
        $sql    .= " AND building_code = ?";
        $params[] = $buildingFilter;
    }

    if (!empty($floorFilter)) {
        $sql    .= " AND floor_no = ?";
        $params[] = $floorFilter;
    }

    if (!empty($roomTypeFilter)) {
        $sql    .= " AND room_type = ?";
        $params[] = $roomTypeFilter;
    }

    if (!empty($searchFilter)) {
        $sql           .= " AND (room_no LIKE ? OR location_name LIKE ? OR building_code LIKE ?)";
        $searchParam    = "%$searchFilter%";
        $params[]       = $searchParam;
        $params[]       = $searchParam;
        $params[]       = $searchParam;
    }

    $sql .= " ORDER BY building_code, floor_no, block_no, room_no";

    // Count total rows
    $countSql  = "SELECT COUNT(*) as total FROM room_master WHERE 1=1";
    // (Re-build count with same filters but skip ORDER BY / LIMIT)
    $countBase = substr($sql, strpos($sql, 'WHERE'));
    $countStmt = $db->prepare("SELECT COUNT(*) as total FROM room_master " . $countBase);
    // Remove ORDER BY from count query
    $countSqlClean = preg_replace('/ORDER BY.*$/i', '', "SELECT COUNT(*) as total FROM room_master " . $countBase);
    $countStmt2 = $db->prepare($countSqlClean);
    $countStmt2->execute($params);
    $totalRows = (int)($countStmt2->fetch(PDO::FETCH_ASSOC)['total'] ?? 0);

    // Apply pagination only when page > 0
    if ($page > 0) {
        $offset  = ($page - 1) * $per_page;
        $sql    .= " LIMIT $per_page OFFSET $offset";
    }

    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $rooms = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "status"      => "success",
        "success"     => true,
        "data"        => $rooms,
        "count"       => count($rooms),
        "total"       => $totalRows,
        "page"        => $page,
        "per_page"    => $per_page,
        "total_pages" => $page > 0 ? ceil($totalRows / $per_page) : 1,
    ]);
} catch (Exception $e) {
    echo json_encode([
        "status"  => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
