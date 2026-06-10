<?php
header('Access-Control-Allow-Origin: *');
header("Content-Type: application/json");

require_once("../../config/database.php");

$data = json_decode(file_get_contents("php://input"), true);

$db = new Database();
$conn = $db->getConnection();

$stmt = $conn->prepare(
"UPDATE rooms SET room_number=?, capacity=?, floor_label=? WHERE id=?"
);

$stmt->execute([
  $data['room_number'],
  $data['capacity'],
  $data['floor'],
  $data['id']
]);

echo json_encode(["success"=>true]);
?>
