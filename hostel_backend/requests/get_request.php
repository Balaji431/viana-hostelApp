<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';



include_once '../config/database.php';

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

if(!empty($data->request_id)){
    // Join with users and profile to provide full context (room allocation)
    $query = "SELECT r.*, u.full_name as student_name, p.room_allocation 
              FROM request1 r 
              LEFT JOIN users u ON r.student_id = u.id 
              LEFT JOIN profile p ON u.username = p.reg_no
              WHERE r.request_id = :request_id";

    $stmt = $db->prepare($query);
    $stmt->bindParam(":request_id", $data->request_id);
    $stmt->execute();

    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if($row){
        echo json_encode([
            "success" => true,
            "data" => $row
        ]);
    } else {
        echo json_encode(["success" => false, "message" => "Request not found"]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Missing request_id"]);
}
?>
