<?php
header('Access-Control-Allow-Origin: *');
header("Content-Type: application/json");

require_once("../../config/database.php");

$data = json_decode(file_get_contents("php://input"), true);

$db = new Database();
$conn = $db->getConnection();

$stmt = $conn->prepare("INSERT INTO hostels (name) VALUES (?)");
$stmt->execute([$data['name']]);

echo json_encode(["success"=>true]);
?>
