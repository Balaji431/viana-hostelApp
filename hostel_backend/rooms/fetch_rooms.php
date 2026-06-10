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

    $hostelFilter = isset($_GET['hostel']) ? $_GET['hostel'] : '';
    $statusFilter = isset($_GET['status']) ? $_GET['status'] : '';

    $sql = "SELECT * FROM rooms WHERE 1=1";
    $params = [];

    if (!empty($hostelFilter)) {
        $sql .= " AND hostel_name = ?";
        $params[] = $hostelFilter;
    }

    if (!empty($statusFilter)) {
        $sql .= " AND status = ?";
        $params[] = $statusFilter;
    }

    $sql .= " ORDER BY hostel_name, room_number";

    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $rooms = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "status" => "success",
        "success" => true,
        "data" => $rooms
    ]);
} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
