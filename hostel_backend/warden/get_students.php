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

$database = new DatabaseMysqli();
$conn = $database->getConnection();

if (!$conn) {
    echo json_encode(array("status" => "error", "message" => "Database connection failed", "success" => false));
    exit();
}

// Fetch warden_username for filtering
$warden_username = isset($_GET['warden_username']) ? $_GET['warden_username'] : null;

// Base SQL starting from profile table to include all students with room allocations
// Robust SQL query with flexible matching for hostel, floor and wing
$sql = "SELECT DISTINCT
            p.id as profile_id,
            p.full_name,
            p.reg_no as register_number,
            p.room_allocation as room_no,
            p.institution,
            u.id as user_id,
            u.conduct,
            u.Status,
            hr.room_code,
            hr.floor,
            hr.wing_code
        FROM profile p
        LEFT JOIN users u ON (TRIM(p.reg_no) = TRIM(u.username))
        JOIN hostel_rooms hr ON (TRIM(p.room_allocation) = TRIM(hr.room_code))
        JOIN mapping_staff ms ON (TRIM(ms.username) = ?)
        WHERE (
            TRIM(ms.hostel_name) COLLATE utf8mb4_general_ci LIKE CONCAT('%', TRIM(hr.hostel_name) COLLATE utf8mb4_general_ci, '%')
            OR TRIM(hr.hostel_name) COLLATE utf8mb4_general_ci LIKE CONCAT('%', TRIM(ms.hostel_name) COLLATE utf8mb4_general_ci, '%')
        )
        AND (
            TRIM(ms.floor_name) = '' 
            OR ms.floor_name IS NULL 
            OR TRIM(hr.floor) COLLATE utf8mb4_general_ci LIKE CONCAT('%', TRIM(ms.floor_name) COLLATE utf8mb4_general_ci, '%')
            OR (LOWER(TRIM(hr.floor)) IN ('f00', 'ground', 'ground floor') AND LOWER(TRIM(ms.floor_name)) IN ('f00', 'ground', 'ground floor'))
            OR (LOWER(TRIM(hr.floor)) IN ('f01', '1st floor') AND LOWER(TRIM(ms.floor_name)) IN ('f01', '1st floor'))
            OR (LOWER(TRIM(hr.floor)) IN ('f02', '2nd floor') AND LOWER(TRIM(ms.floor_name)) IN ('f02', '2nd floor'))
        )
        AND (
            TRIM(ms.wing_name) = '' 
            OR ms.wing_name IS NULL 
            OR TRIM(hr.wing_code) COLLATE utf8mb4_general_ci LIKE CONCAT('%', TRIM(ms.wing_name) COLLATE utf8mb4_general_ci, '%')
            OR TRIM(ms.wing_name) COLLATE utf8mb4_general_ci LIKE CONCAT('%', TRIM(hr.wing_code) COLLATE utf8mb4_general_ci, '%')
        )
        AND (ms.role = 'Warden' OR ms.role = 'Security' OR ms.role = 'Maintenance' OR ms.role = (SELECT role FROM users WHERE username = ? LIMIT 1))";


try {
    $stmt = $conn->prepare($sql);
    $warden_param = $warden_username ?? '';
    $stmt->bind_param("ss", $warden_param, $warden_param);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $students = array();
    if ($result && $result->num_rows > 0) {
        while($row = $result->fetch_assoc()) {
            // Use user_id as main id if available, otherwise profile_id
            $row['id'] = $row['user_id'] ?? $row['profile_id'];
            
            // Ensure all fields are UTF-8 encoded
            $students[] = array_map(function($val) {
                return is_string($val) ? mb_convert_encoding($val, 'UTF-8', 'UTF-8') : $val;
            }, $row);
        }
    }
    
    $json = json_encode(array("status" => "success", "data" => $students, "success" => true), JSON_INVALID_UTF8_SUBSTITUTE);
    if ($json === false) {
        echo json_encode(array("status" => "error", "message" => "JSON encoding error: " . json_last_error_msg(), "success" => false));
    } else {
        echo $json;
    }
} catch (Exception $e) {
    echo json_encode(array("status" => "error", "message" => $e->getMessage(), "success" => false));
} finally {
    if (isset($conn) && $conn) {
        $conn->close();
    }
}
?>
