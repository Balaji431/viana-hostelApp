<?php
header('Access-Control-Allow-Origin: *');
header("Content-Type: application/json");

require_once("../../config/database.php");

$data = json_decode(file_get_contents("php://input"), true);

$db = new Database();
$conn = $db->getConnection();

$stmt = $conn->prepare("INSERT INTO sub_zones (zone_id, name) VALUES (?, ?)");
$stmt->execute([$data['zone_id'], $data['name']]);

echo json_encode(["success"=>true]);
?>
