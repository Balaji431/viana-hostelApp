<?php
error_reporting(0);
ini_set('display_errors', 0);

header('Access-Control-Allow-Origin: *');
header("Content-Type: application/json");

require_once("../../config/database.php");

try {
    $db = new Database();
    $conn = $db->getConnection();

    $stmt = $conn->query("SELECT id, name FROM hostels");

    $data = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode($data);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "error" => $e->getMessage()
    ]);
}
?>
