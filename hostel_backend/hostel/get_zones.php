<?php
error_reporting(0);
ini_set('display_errors', 0);

header('Access-Control-Allow-Origin: *');
header("Content-Type: application/json");

require_once("../../config/database.php");

try {
    $hostel_id = isset($_GET['hostel_id']) ? $_GET['hostel_id'] : 0;

    $db = new Database();
    $conn = $db->getConnection();

    $stmt = $conn->prepare("SELECT id, name FROM zones WHERE hostel_id=?");
    $stmt->execute([$hostel_id]);

    $data = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode($data);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "error" => $e->getMessage()
    ]);
}
?>
