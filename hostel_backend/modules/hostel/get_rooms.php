<?php
error_reporting(0);
ini_set('display_errors', 0);

header('Access-Control-Allow-Origin: *');
header("Content-Type: application/json");

require_once("../../config/database.php");

try {
    $sub_zone_id = isset($_GET['sub_zone_id']) ? $_GET['sub_zone_id'] : 0;

    $db = new Database();
    $conn = $db->getConnection();

    $stmt = $conn->prepare("SELECT id, room_number, capacity, floor_label FROM rooms WHERE sub_zone_id=?");
    $stmt->execute([$sub_zone_id]);

    $data = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode($data);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "error" => $e->getMessage()
    ]);
}
?>
