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
    $database = new DatabaseMysqli();
    $conn = $database->getConnection();

    if (!$conn) {
        throw new Exception("Database connection failed");
    }

    $warden_username = isset($_GET['warden_username']) ? $_GET['warden_username'] : null;
    
    $warden_filter = "";
    $params = [];
    $param_types = "";

    if ($warden_username && $warden_username !== 'admin' && $warden_username !== 'warden1') {
        $warden_filter = " AND rr.student_reg_no IN (
            SELECT DISTINCT p.reg_no 
            FROM profile p
            JOIN mapping_staff ms ON (TRIM(ms.username) = ?)
            WHERE (TRIM(p.hostel_name) LIKE CONCAT('%', TRIM(ms.hostel_name), '%'))
              AND (ms.role = 'Warden' OR ms.role = 'Security' OR ms.role = 'Maintenance' OR ms.role = (SELECT role FROM users WHERE username = ? LIMIT 1))
        )";
        $params[] = $warden_username;
        $params[] = $warden_username;
        $param_types = "ss";
    }

    $sql = "SELECT 
                rr.id,
                rr.student_id,
                rr.student_name,
                rr.student_reg_no,
                rr.room_number,
                rr.reason,
                rr.status,
                rr.requested_at,
                hr.group_name as floor_name
            FROM renewal_requests rr
            LEFT JOIN rooms_groups_details hr ON (TRIM(rr.room_number) = TRIM(hr.room_number))
            WHERE 1=1 $warden_filter
            ORDER BY rr.requested_at DESC";

    $stmt = $conn->prepare($sql);
    if (!empty($params)) {
        $stmt->bind_param($param_types, ...$params);
    }
    $stmt->execute();
    $result = $stmt->get_result();

    $data = [];
    while ($row = $result->fetch_assoc()) {
        $data[] = $row;
    }

    echo json_encode([
        "success" => true,
        "status" => "success",
        "data" => $data
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "status" => "error",
        "message" => $e->getMessage()
    ]);
}
?>
