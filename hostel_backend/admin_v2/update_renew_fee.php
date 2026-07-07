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

    if (isset($data['id'])) {
        $id         = intval($data['id']);
        $hostel_fee = $data['hostel_fee'] ?? $data['six_month_amount'] ?? 0;
        $food_fee   = $data['food_fee'] ?? 50000;
        $monthly    = $data['monthly_amount'] ?? 2000;
        $room_type  = $data['room_type'] ?? '';
        $facility   = $data['facility_description'] ?? '';

        $query = "UPDATE hostel_renew_fee SET 
                  room_type = :room_type, 
                  hostel_fee = :hostel_fee, 
                  food_fee = :food_fee,
                  monthly_amount = :monthly, 
                  facility_description = :facility
                  WHERE id = :id";
        
        $stmt = $db->prepare($query);
        $stmt->bindParam(':room_type',  $room_type);
        $stmt->bindParam(':hostel_fee', $hostel_fee);
        $stmt->bindParam(':food_fee',   $food_fee);
        $stmt->bindParam(':monthly',    $monthly);
        $stmt->bindParam(':facility',   $facility);
        $stmt->bindParam(':id',         $id);

        if ($stmt->execute()) {
            echo json_encode([
                "status"  => "success",
                "success" => true,
                "message" => "Fee updated successfully"
            ]);
        } else {
            throw new Exception("Update failed");
        }
    } else {
        throw new Exception("Invalid data: ID is required");
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
