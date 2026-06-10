<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

$database = new Database();
$conn = $database->getConnection();

try {
    // Get room types and amounts from the new renew_fee table
    $sql = "SELECT room_type as name, six_month_amount, monthly_amount, facility_description as description
            FROM renew_fee 
            ORDER BY six_month_amount ASC";
            
    $stmt = $conn->prepare($sql);
    $stmt->execute();
    $roomTypes = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Format for the frontend
    $formatted = [];
    foreach ($roomTypes as $room) {
        $formatted[] = [
            'id' => $room['name'],
            'name' => $room['name'],
            'six_month_amount' => (float)$room['six_month_amount'],
            'monthly_amount' => (float)$room['monthly_amount'],
            'description' => $room['description']
        ];
    }

    echo json_encode([
        'status' => 'success',
        'data' => $formatted
    ]);

} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
