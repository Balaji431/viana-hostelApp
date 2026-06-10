<?php
require_once 'config/database.php';

$id = 2; // Warden ID
$newName = "Venkatesh";
$newRoleLabel = "Senior Warden"; // Example detail

$sql = "UPDATE users SET name = ?, institution = ? WHERE id = ?";
$stmt = $conn->prepare($sql);
$stmt->bind_param("ssi", $newName, $newRoleLabel, $id);

if ($stmt->execute()) {
    echo json_encode(["success" => true, "message" => "Warden profile updated in database"]);
} else {
    echo json_encode(["success" => false, "message" => $conn->error]);
}
?>
