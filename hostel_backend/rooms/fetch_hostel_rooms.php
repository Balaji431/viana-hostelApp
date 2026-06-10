<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once '../config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();

    $hostelFilter = isset($_GET['hostel_name']) ? $_GET['hostel_name'] : '';
    $roomTypeFilter = isset($_GET['room_type']) ? $_GET['room_type'] : '';
    $floorFilter = isset($_GET['floor']) ? $_GET['floor'] : '';

    $sql = "SELECT * FROM hostel_rooms WHERE 1=1";
    $params = [];

    if (!empty($hostelFilter)) {
        $sql .= " AND hostel_name = ?";
        $params[] = $hostelFilter;
    }

    if (!empty($roomTypeFilter)) {
        $sql .= " AND room_type = ?";
        $params[] = $roomTypeFilter;
    }

    if (!empty($floorFilter)) {
        $sql .= " AND floor = ?";
        $params[] = $floorFilter;
    }

    $sql .= " ORDER BY floor, room_no";

    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $rooms = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "status" => "success",
        "success" => true,
        "data" => $rooms,
        "count" => count($rooms)
    ]);
} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
