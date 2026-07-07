<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
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

    $data = json_decode(file_get_contents("php://input"), true);

    if (isset($data['room_type'])) {
        $room_type = $data['room_type'];
        $hostel_fee = $data['hostel_fee'] ?? $data['six_month_amount'] ?? 0;
        $food_fee   = $data['food_fee'] ?? 50000;
        $monthly    = $data['monthly_amount'] ?? 2000;
        $facility   = $data['facility_description'] ?? '';

        $query = "INSERT INTO hostel_renew_fee (room_type, hostel_fee, food_fee, monthly_amount, facility_description)
                  VALUES (:room_type, :hostel_fee, :food_fee, :monthly, :facility)
                  ON DUPLICATE KEY UPDATE hostel_fee = VALUES(hostel_fee), food_fee = VALUES(food_fee), 
                  monthly_amount = VALUES(monthly_amount), facility_description = VALUES(facility_description)";
        
        $stmt = $db->prepare($query);
        $stmt->bindParam(':room_type',  $room_type);
        $stmt->bindParam(':hostel_fee', $hostel_fee);
        $stmt->bindParam(':food_fee',   $food_fee);
        $stmt->bindParam(':monthly',    $monthly);
        $stmt->bindParam(':facility',   $facility);

        if ($stmt->execute()) {
            echo json_encode([
                "status"  => "success",
                "success" => true,
                "message" => "Fee added successfully",
                "id"      => $db->lastInsertId()
            ]);
        } else {
            throw new Exception("Insert failed");
        }
    } else {
        throw new Exception("Invalid data: room_type is required");
    }
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
