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

try {
    $database = new Database();
    $db = $database->getConnection();

    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $warden_username = isset($_GET['warden_username']) ? $_GET['warden_username'] : null;
    $warden_filter = "";
    $params = [];

    if ($warden_username && $warden_username !== 'admin') {
        $warden_filter = " WHERE p.registerNumber IN (
            SELECT DISTINCT pr.reg_no
            FROM profile pr
            JOIN rooms_groups_details rgd ON (TRIM(pr.room_allocation) = TRIM(rgd.room_number))
            JOIN mapping_staff ms ON (TRIM(ms.username) = :warden_username)
            WHERE (
                LOWER(TRIM(ms.hostel_name)) = LOWER(TRIM(rgd.hostel_name))
                OR LOWER(TRIM(ms.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(rgd.hostel_name)), '%')
                OR LOWER(TRIM(rgd.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(ms.hostel_name)), '%')
            )
            AND (
                LOWER(TRIM(rgd.group_name)) LIKE CONCAT('%', LOWER(TRIM(ms.floor_name)), '%')
                OR ms.floor_name IS NULL OR ms.floor_name = ''
            )
        )";
        $params[':warden_username'] = $warden_username;
    }

    // Try booking_date first, fallback to payment_id if it doesn't exist
    $query = "SELECT p.* FROM payment p $warden_filter ORDER BY payment_id DESC LIMIT 500";
    
    // Check if booking_date exists by trying to select it
    try {
        $check_query = "SELECT booking_date FROM payment LIMIT 1";
        $db->query($check_query);
        $query = "SELECT p.* FROM payment p $warden_filter ORDER BY booking_date DESC LIMIT 500";
    } catch (Exception $e) {
        // booking_date doesn't exist, keep the payment_id order
    }

    $stmt = $db->prepare($query);
    foreach ($params as $key => $val) {
        $stmt->bindValue($key, $val);
    }
    $stmt->execute();
    $payments = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "success" => true,
        "status" => "success",
        "data" => $payments,
        "count" => count($payments)
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "success" => false,
        "status" => "error",
        "message" => $e->getMessage(),
        "trace" => $e->getTraceAsString()
    ]);
}
?>
