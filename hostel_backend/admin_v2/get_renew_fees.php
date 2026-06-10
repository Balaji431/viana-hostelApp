<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();

    $hostel_id = isset($_GET['hostel_id']) ? intval($_GET['hostel_id']) : null;

    if ($hostel_id) {
        $query = "SELECT * FROM renew_fee WHERE hostel_id = :hostel_id ORDER BY id ASC";
        $stmt = $db->prepare($query);
        $stmt->bindParam(':hostel_id', $hostel_id);
    } else {
        $query = "SELECT * FROM renew_fee ORDER BY id ASC";
        $stmt = $db->prepare($query);
    }
    
    $stmt->execute();
    $fees = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "status" => "success",
        "success" => true,
        "data" => $fees
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
