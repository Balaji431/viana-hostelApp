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

if (!$db) {
    echo json_encode(array("status" => "error", "message" => "Database connection failed", "success" => false));
    exit();
}

$date = isset($_GET['date']) ? $_GET['date'] : date('Y-m-d');
$warden_username = isset($_GET['warden_username']) ? $_GET['warden_username'] : null;

try {
    $sql = "SELECT a.*, p.full_name as name, p.room_allocation as room_no, p.institution 
            FROM attendance a
            JOIN profile p ON (CONVERT(a.student_id USING utf8mb4) = CONVERT(p.reg_no USING utf8mb4) OR a.student_id = p.id)
            JOIN hostel_rooms hr ON (CONVERT(p.room_allocation USING utf8mb4) = CONVERT(hr.room_code USING utf8mb4))";

    if ($warden_username) {
        $sql .= " JOIN mapping_staff ms ON (CONVERT(ms.username USING utf8mb4) = ?)
                  WHERE (TRIM(CONVERT(ms.hostel_name USING utf8mb4)) = TRIM(CONVERT(hr.hostel_name USING utf8mb4)) 
                         OR TRIM(CONVERT(ms.hostel_name USING utf8mb4)) = TRIM(CONVERT(hr.building_code USING utf8mb4)))
                    AND (
                        (TRIM(CONVERT(ms.floor_name USING utf8mb4)) = TRIM(CONVERT(hr.floor USING utf8mb4)))
                        OR (ms.floor_name = 'Ground' AND hr.floor = 'F00')
                        OR (ms.floor_name = '1st Floor' AND hr.floor = 'F01')
                        OR (ms.floor_name = '2nd Floor' AND hr.floor = 'F02')
                        OR (ms.floor_name IS NULL OR ms.floor_name = '')
                    )
                    AND (TRIM(CONVERT(ms.wing_name USING utf8mb4)) = TRIM(CONVERT(hr.wing_code USING utf8mb4)) 
                         OR ms.wing_name IS NULL OR ms.wing_name = '')
                    AND ms.role = 'Warden'
                    AND DATE(a.log_time) = ?
                    ORDER BY a.log_time DESC";
        $stmt = $db->prepare($sql);
        $stmt->execute([$warden_username, $date]);
    } else {
        $sql .= " WHERE DATE(a.log_time) = ? ORDER BY a.log_time DESC";
        $stmt = $db->prepare($sql);
        $stmt->execute([$date]);
    }
    $logs = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Sanitize logs for JSON encoding
    $sanitizedLogs = array_map(function($row) {
        return array_map(function($val) {
            return is_string($val) ? mb_convert_encoding($val, 'UTF-8', 'UTF-8') : $val;
        }, $row);
    }, $logs);

    $json = json_encode(array("status" => "success", "data" => $sanitizedLogs, "success" => true), JSON_INVALID_UTF8_SUBSTITUTE);
    if ($json === false) {
        echo json_encode(array("status" => "error", "message" => "JSON encoding error: " . json_last_error_msg(), "success" => false));
    } else {
        echo $json;
    }
} catch (Exception $e) {
    echo json_encode(array("status" => "error", "message" => $e->getMessage(), "success" => false));
}
?>
