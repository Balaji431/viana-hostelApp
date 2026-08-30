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
            SELECT DISTINCT pr.reg_no COLLATE utf8mb4_unicode_ci 
            FROM profile pr 
            JOIN mapping_staff ms ON (ms.username = :warden_username AND LOWER(TRIM(ms.hostel_name)) = LOWER(TRIM(pr.hostel_name)))
        )";
        $params[':warden_username'] = $warden_username;
    }

    $query = "SELECT p.* FROM payment p $warden_filter ORDER BY COALESCE(p.paid_at, p.created_at, p.booking_date, p.id) DESC LIMIT 500";

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
