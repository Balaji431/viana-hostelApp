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

$database = new Database();
$db = $database->getConnection();

try {
    $warden_username = isset($_GET['warden_username']) ? $_GET['warden_username'] : null;
    
    $warden_filter = "";
    $params = [];

    if ($warden_username && $warden_username !== 'admin' && $warden_username !== 'warden1') {
        // Filter reports to only show students assigned to this staff member
        $warden_filter = " AND stu.username IN (
            SELECT DISTINCT p.reg_no 
            FROM profile p
            JOIN hostel_rooms hr ON (TRIM(p.room_allocation) = TRIM(hr.room_code))
            JOIN mapping_staff ms ON (TRIM(ms.username) = :warden_username)
            WHERE (
                LOWER(TRIM(ms.hostel_name)) = LOWER(TRIM(hr.hostel_name))
                OR LOWER(TRIM(ms.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(hr.hostel_name)), '%')
                OR LOWER(TRIM(hr.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(ms.hostel_name)), '%')
            )
            AND (
                LOWER(TRIM(ms.floor_name)) = LOWER(TRIM(hr.floor))
                OR (LOWER(TRIM(hr.floor)) IN ('f00', 'ground') AND LOWER(TRIM(ms.floor_name)) IN ('f00', 'ground'))
                OR (LOWER(TRIM(hr.floor)) IN ('f01', '1st floor') AND LOWER(TRIM(ms.floor_name)) IN ('f01', '1st floor'))
                OR (LOWER(TRIM(hr.floor)) IN ('f02', '2nd floor') AND LOWER(TRIM(ms.floor_name)) IN ('f02', '2nd floor'))
                OR (LOWER(TRIM(hr.floor)) IN ('f04', '4th floor', 'fourth') AND LOWER(TRIM(ms.floor_name)) IN ('f04', '4th floor', 'fourth'))
                OR ms.floor_name IS NULL OR ms.floor_name = ''
            )
            AND (LOWER(TRIM(ms.wing_name)) = LOWER(TRIM(hr.wing_code)) OR ms.wing_name IS NULL OR ms.wing_name = '')
            AND (ms.role = 'Warden' OR ms.role = 'Security' OR ms.role = 'Maintenance' OR ms.role = (SELECT role FROM users WHERE username = :warden_username LIMIT 1))
        )";
        $params[':warden_username'] = $warden_username;
    }

    $query = "SELECT r.*, stu.full_name as student_name
              FROM request1 r
              LEFT JOIN users stu ON r.student_id = stu.id
              WHERE r.request_type != 'room_change' AND r.request_type != 'General Inquiry' $warden_filter
              ORDER BY r.created_at DESC";

    $stmt = $db->prepare($query);
    foreach ($params as $key => $val) {
        $stmt->bindValue($key, $val);
    }
    $stmt->execute();

    $requests = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "success" => true,
        "data" => $requests,
        "status" => "success"
    ]);
} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => $e->getMessage(),
        "status" => "error"
    ]);
}
?>
