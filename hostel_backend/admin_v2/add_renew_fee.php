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

    if (isset($data['hostel_id']) && isset($data['room_type'])) {
        $hostel_id = intval($data['hostel_id']);
        $room_type = $data['room_type'];
        $six_month = $data['six_month_amount'] ?? 0;
        $monthly = $data['monthly_amount'] ?? 0;
        $facility = $data['facility_description'] ?? '';
        
        // Get hostel name for redundancy if needed
        $hStmt = $db->prepare("SELECT name FROM hostels WHERE id = :hid");
        $hStmt->bindParam(':hid', $hostel_id);
        $hStmt->execute();
        $hRow = $hStmt->fetch(PDO::FETCH_ASSOC);
        $hostel_name = $hRow ? $hRow['name'] : 'Unknown';

        $query = "INSERT INTO renew_fee (room_type, six_month_amount, monthly_amount, facility_description, hostel_id, hostel_name) 
                  VALUES (:room_type, :six_month, :monthly, :facility, :hostel_id, :hostel_name)";
        
        $stmt = $db->prepare($query);
        $stmt->bindParam(':room_type', $room_type);
        $stmt->bindParam(':six_month', $six_month);
        $stmt->bindParam(':monthly', $monthly);
        $stmt->bindParam(':facility', $facility);
        $stmt->bindParam(':hostel_id', $hostel_id);
        $stmt->bindParam(':hostel_name', $hostel_name);

        if ($stmt->execute()) {
            echo json_encode([
                "status" => "success",
                "success" => true,
                "message" => "Fee added successfully",
                "id" => $db->lastInsertId()
            ]);
        } else {
            throw new Exception("Insert failed");
        }
    } else {
        throw new Exception("Invalid data: hostel_id and room_type are required");
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
