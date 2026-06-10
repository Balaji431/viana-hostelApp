<?php
header('Access-Control-Allow-Origin: *');
header("Content-Type: application/json");

require_once("../../config/database.php");

$data = json_decode(file_get_contents("php://input"), true);

$db = new Database();
$conn = $db->getConnection();

$stmt = $conn->prepare(
"INSERT INTO rooms (sub_zone_id, room_number, capacity, floor_label)
 VALUES (?, ?, ?, ?)"
);

$stmt->execute([
  $data['sub_zone_id'],
  $data['room_number'],
  $data['capacity'],
  $data['floor']
]);

echo json_encode(["success"=>true]);
?>
