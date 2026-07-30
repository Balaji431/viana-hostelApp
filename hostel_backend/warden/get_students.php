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
require_once '../utils/auth_helper.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

if (!$conn) {
    echo json_encode(array("status" => "error", "message" => "Database connection failed", "success" => false));
    exit();
}

try {
    $warden_username = isset($_GET['warden_username']) ? trim($_GET['warden_username']) : '';

    if (empty($warden_username)) {
        // Fallback to JWT payload if present
        $auth_header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
        if (empty($auth_header) && function_exists('apache_request_headers')) {
            $headers = apache_request_headers();
            $auth_header = $headers['Authorization'] ?? $headers['authorization'] ?? '';
        }
        if (preg_match('/Bearer\s+(.*)$/i', $auth_header, $matches)) {
            $payload = validateJWT($matches[1]);
            if ($payload) $warden_username = $payload['username'];
        }
    }

    if (empty($warden_username)) {
        echo json_encode(array("status" => "success", "data" => [], "success" => true));
        exit();
    }

    $is_admin = (strtolower($warden_username) === 'admin');

    if ($is_admin) {
        $sql = "SELECT DISTINCT
                    p.id as profile_id,
                    p.full_name,
                    p.reg_no as register_number,
                    p.room_allocation as room_no,
                    p.institution,
                    u.id as user_id,
                    u.conduct,
                    u.Status,
                    rgd.room_number as room_code,
                    rgd.hostel_name,
                    rgd.group_name as floor,
                    'General' as wing_code
                FROM profile p
                LEFT JOIN users u ON (TRIM(p.reg_no) = TRIM(u.username))
                LEFT JOIN rooms_groups_details rgd ON (TRIM(p.room_allocation) = TRIM(rgd.room_number))";
        $stmt = $conn->prepare($sql);
    } else {
        // Fetch all assigned locations for this warden from mapping_staff
        $sql = "SELECT DISTINCT
                    p.id as profile_id,
                    p.full_name,
                    p.reg_no as register_number,
                    p.room_allocation as room_no,
                    p.institution,
                    u.id as user_id,
                    u.conduct,
                    u.Status,
                    rgd.room_number as room_code,
                    rgd.hostel_name,
                    rgd.group_name as floor,
                    'General' as wing_code
                FROM profile p
                LEFT JOIN users u ON (TRIM(p.reg_no) = TRIM(u.username))
                JOIN rooms_groups_details rgd ON (TRIM(p.room_allocation) = TRIM(rgd.room_number))
                JOIN mapping_staff ms ON (
                    TRIM(rgd.hostel_name) LIKE CONCAT('%', TRIM(ms.hostel_name), '%') 
                    AND LOWER(rgd.group_name) LIKE CONCAT('%', LOWER(ms.floor_name), '%')
                )
                WHERE (ms.username = ? OR ms.staff_bio_id = ?)";
        $stmt = $conn->prepare($sql);
        $stmt->bind_param("ss", $warden_username, $warden_username);
    }

    $stmt->execute();
    $result = $stmt->get_result();
    
    $students = array();
    if ($result && $result->num_rows > 0) {
        while($row = $result->fetch_assoc()) {
            $row['id'] = $row['user_id'] ?? $row['profile_id'];
            $students[] = array_map(function($val) {
                return is_string($val) ? mb_convert_encoding($val, 'UTF-8', 'UTF-8') : $val;
            }, $row);
        }
    }
    
    // Fetch all locations (floors, wings, rooms) mapped to this warden
    $locations = array();
    if ($is_admin) {
        $locSql = "SELECT DISTINCT 
                       rgd.hostel_name, 
                       rgd.group_name as floor_name, 
                       'W0' as wing_name, 
                       rgd.room_number 
                   FROM rooms_groups_details rgd
                   WHERE rgd.room_number IS NOT NULL AND rgd.room_number != ''";
        $locStmt = $conn->prepare($locSql);
    } else {
        $locSql = "SELECT DISTINCT 
                       ms.hostel_name, 
                       ms.floor_name, 
                       ms.wing_name, 
                       rgd.room_number 
                   FROM mapping_staff ms
                   LEFT JOIN rooms_groups_details rgd ON (
                       TRIM(rgd.hostel_name) LIKE CONCAT('%', TRIM(ms.hostel_name), '%')
                       AND LOWER(rgd.group_name) LIKE CONCAT('%', LOWER(ms.floor_name), '%')
                       AND (rgd.room_number LIKE CONCAT('%-', TRIM(ms.wing_name), '-%') OR ms.wing_name = 'W0' OR ms.wing_name = 'N/A')
                   )
                   WHERE (ms.username = ? OR ms.staff_bio_id = ?)";
        $locStmt = $conn->prepare($locSql);
        $locStmt->bind_param("ss", $warden_username, $warden_username);
    }
    $locStmt->execute();
    $locRes = $locStmt->get_result();
    if ($locRes && $locRes->num_rows > 0) {
        while ($lRow = $locRes->fetch_assoc()) {
            $locations[] = array_map(function($val) {
                return is_string($val) ? mb_convert_encoding($val, 'UTF-8', 'UTF-8') : $val;
            }, $lRow);
        }
    }

    echo json_encode(array("status" => "success", "data" => $students, "locations" => $locations, "success" => true));

} catch (Exception $e) {
    echo json_encode(array("status" => "error", "message" => $e->getMessage(), "success" => false));
} finally {
    if (isset($conn) && $conn) {
        $conn->close();
    }
}
?>
