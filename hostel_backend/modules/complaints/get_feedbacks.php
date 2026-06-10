<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../../config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();

    $query = "SELECT f.*, 
                     u.full_name AS student_name, 
                     u.username AS student_reg_no, 
                     u.phone_number AS student_phone, 
                     u.RoomId AS student_room, 
                     COALESCE(ms.name, u2.full_name, f.staff_username) AS staff_name
              FROM feedbacks f
              LEFT JOIN users u ON f.student_id = u.id
              LEFT JOIN mapping_staff ms ON f.staff_username = ms.username
              LEFT JOIN users u2 ON f.staff_username = u2.username
              ORDER BY f.created_at DESC";

    $stmt = $db->prepare($query);
    $stmt->execute();

    $feedbacks = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "success" => true,
        "data" => $feedbacks
    ]);

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Server error: " . $e->getMessage()]);
}
?>
