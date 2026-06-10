<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../../config/database.php';

$mappingId = $_GET['id'] ?? null;

if (!$mappingId) {
    echo json_encode(["success" => false, "message" => "Mapping ID required"]);
    exit();
}

try {
    // ON DELETE CASCADE will handle mapping_staff
    $stmt = $pdo->prepare("DELETE FROM location_mappings WHERE id = ?");
    $stmt->execute([$mappingId]);

    echo json_encode(["success" => true]);

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
}
?>
