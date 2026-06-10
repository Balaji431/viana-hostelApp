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
        // Filter payments to only show students assigned to this staff member
        // Added JOIN with hostel_rooms to get correct hostel/floor/wing info
        $warden_filter = " WHERE p.registerNumber COLLATE utf8mb4_unicode_ci IN (
            SELECT DISTINCT pr.reg_no COLLATE utf8mb4_unicode_ci
            FROM profile pr
            JOIN hostel_rooms hr ON (TRIM(pr.room_allocation) COLLATE utf8mb4_unicode_ci = TRIM(hr.room_code) COLLATE utf8mb4_unicode_ci)
            JOIN mapping_staff ms ON (TRIM(ms.username) COLLATE utf8mb4_unicode_ci = :warden_username COLLATE utf8mb4_unicode_ci)
            WHERE (
                LOWER(TRIM(ms.hostel_name)) COLLATE utf8mb4_unicode_ci = LOWER(TRIM(hr.hostel_name)) COLLATE utf8mb4_unicode_ci
                OR LOWER(TRIM(ms.hostel_name)) COLLATE utf8mb4_unicode_ci LIKE CONCAT('%', LOWER(TRIM(hr.hostel_name)), '%') COLLATE utf8mb4_unicode_ci
                OR LOWER(TRIM(hr.hostel_name)) COLLATE utf8mb4_unicode_ci LIKE CONCAT('%', LOWER(TRIM(ms.hostel_name)), '%') COLLATE utf8mb4_unicode_ci
            )
            AND (
                LOWER(TRIM(ms.floor_name)) COLLATE utf8mb4_unicode_ci = LOWER(TRIM(hr.floor)) COLLATE utf8mb4_unicode_ci
                OR (LOWER(TRIM(hr.floor)) IN ('f00', 'ground') AND LOWER(TRIM(ms.floor_name)) IN ('f00', 'ground'))
                OR (LOWER(TRIM(hr.floor)) IN ('f01', '1st floor') AND LOWER(TRIM(ms.floor_name)) IN ('f01', '1st floor'))
                OR (LOWER(TRIM(hr.floor)) IN ('f02', '2nd floor') AND LOWER(TRIM(ms.floor_name)) IN ('f02', '2nd floor'))
                OR ms.floor_name IS NULL OR ms.floor_name = ''
            )
            AND (LOWER(TRIM(ms.wing_name)) COLLATE utf8mb4_unicode_ci = LOWER(TRIM(hr.wing_code)) COLLATE utf8mb4_unicode_ci OR ms.wing_name IS NULL OR ms.wing_name = '')
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
