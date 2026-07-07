<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

try {
    $db = new Database();
    $conn = $db->getConnection();
    if (!$conn) {
        throw new Exception("Database connection failed");
    }

    // Fetch unallocated students who have paid their hostel fee
    $query = "
        SELECT 
            u.id, 
            u.full_name, 
            u.username as register_no, 
            u.Campus as campus, 
            u.HostelType as gender, 
            p.email, 
            COALESCE(vp.hostel_preference, 'Standard Room') as room_preference, 
            COALESCE(vp.hostel_name, 'Krishna Hostel') as hostel_preference, 
            COALESCE(vp.paid_amount, 0.00) as paid_amount
        FROM users u
        LEFT JOIN profile p ON u.username = p.reg_no
        LEFT JOIN vstudy_payments vp ON u.username = vp.roll_number
        WHERE u.role = 'student'
          AND (p.current_room_id IS NULL OR p.current_room_id = 0 OR p.room_allocation IS NULL OR p.room_allocation = '' OR p.room_allocation = 'N/A' OR p.room_allocation = 'N/A, N/A, N/A')
        ORDER BY u.id DESC
    ";

    $stmt = $conn->prepare($query);
    $stmt->execute();
    $students = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "success" => true,
        "status" => "success",
        "data" => $students
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "status" => "error",
        "message" => $e->getMessage()
    ]);
}
?>
