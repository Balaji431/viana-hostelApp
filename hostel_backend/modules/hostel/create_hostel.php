<?php
header('Access-Control-Allow-Origin: *');
header("Content-Type: application/json");

require_once("../../config/database.php");

$data = json_decode(file_get_contents("php://input"), true);

$db = new Database();
$conn = $db->getConnection();

// Check for duplicate hostel name
$check_stmt = $conn->prepare("SELECT id FROM hostels WHERE name = ?");
$check_stmt->execute([$data['name']]);
$row = $check_stmt->fetch(PDO::FETCH_ASSOC);

if ($row) {
    echo json_encode(["success" => false, "message" => "Hostel with this name already exists"]);
    exit();
}

$stmt = $conn->prepare("INSERT INTO hostels (name) VALUES (?)");
$stmt->execute([$data['name']]);

echo json_encode(["success" => true]);
?>
