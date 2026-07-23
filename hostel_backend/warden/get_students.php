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
    // 1. Authenticate via validated JWT if present
    $auth_header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (empty($auth_header)) {
        if (function_exists('apache_request_headers')) {
            $headers = apache_request_headers();
            $auth_header = $headers['Authorization'] ?? $headers['authorization'] ?? '';
        }
    }
    
    $token = null;
    if (preg_match('/Bearer\s+(.*)$/i', $auth_header, $matches)) {
        $token = $matches[1];
    }
    
    $payload = validateJWT($token);
    if ($payload) {
        $warden_username = $payload['username'];
    } else {
        // Fallback for simple tests
        $warden_username = isset($_GET['warden_username']) ? $_GET['warden_username'] : null;
    }

    if (empty($warden_username)) {
        echo json_encode(array("status" => "success", "data" => [], "success" => true));
        exit();
    }

    // 2. Resolve Warden role
    $warden_role = 'staff';
    $u_stmt = $conn->prepare("SELECT role FROM users WHERE username = ? LIMIT 1");
    $u_stmt->bind_param("s", $warden_username);
    $u_stmt->execute();
    $u_res = $u_stmt->get_result()->fetch_assoc();
    
    if ($u_res) {
        $warden_role = $u_res['role'];
    } else {
        $s_stmt = $conn->prepare("SELECT role FROM staff_users WHERE bio_id = ? LIMIT 1");
        $s_stmt->bind_param("s", $warden_username);
        $s_stmt->execute();
        $s_res = $s_stmt->get_result()->fetch_assoc();
        if ($s_res) {
            $warden_role = $s_res['role'];
        } else {
            echo json_encode(array("status" => "success", "data" => [], "success" => true));
            exit();
        }
    }
    
    $is_main_warden = ($warden_role === 'admin');

    $mapped_hostel = null;
    $mapped_floor = null;
    $mapped_wing = null;

    if (!$is_main_warden) {
        // 3. Fetch warden's mapping details (support both username and staff_bio_id)
        $m_stmt = $conn->prepare("SELECT hostel_name, floor_name, wing_name FROM mapping_staff WHERE (username = ? OR staff_bio_id = ?) AND role = 'warden' LIMIT 1");
        $m_stmt->bind_param("ss", $warden_username, $warden_username);
        $m_stmt->execute();
        $mapping = $m_stmt->get_result()->fetch_assoc();
        
        if ($mapping) {
            $warden_role = 'warden'; // Allow them if they are mapped as warden
            $mapped_hostel = $mapping['hostel_name'];
            $mapped_floor = $mapping['floor_name'];
            $mapped_wing = $mapping['wing_name'];
        } else if ($warden_role !== 'warden') {
            http_response_code(403);
            echo json_encode(["status" => "error", "message" => "Access Denied. You do not have the warden role.", "success" => false]);
            exit();
        }
    }

    // 4. Query students from profile
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
            LEFT JOIN hostel_rooms hr ON (p.current_room_id = hr.id OR TRIM(p.room_allocation) = TRIM(hr.room_code))";

    $where_clauses = [];
    $params = [];
    $types = "";

    if (!$is_main_warden) {
        // Hostel filter
        $where_clauses[] = "(hr.hostel_name = ? OR hr.hostel_name LIKE CONCAT('%', ?, '%') OR ? LIKE CONCAT('%', hr.hostel_name, '%'))";
        $params[] = $mapped_hostel;
        $params[] = $mapped_hostel;
        $params[] = $mapped_hostel;
        $types .= "sss";

        // Floor filter (supports floor mapping Ground -> F00, Fourth -> F04, etc.)
        if (!empty($mapped_floor) && strtolower($mapped_floor) !== 'all') {
            $where_clauses[] = "(
                TRIM(hr.floor) COLLATE utf8mb4_general_ci LIKE CONCAT('%', ? COLLATE utf8mb4_general_ci, '%')
                OR (LOWER(TRIM(hr.floor)) IN ('f00', 'ground', 'ground floor') AND LOWER(?) IN ('f00', 'ground', 'ground floor'))
                OR (LOWER(TRIM(hr.floor)) IN ('f01', '1st floor') AND LOWER(?) IN ('f01', '1st floor'))
                OR (LOWER(TRIM(hr.floor)) IN ('f02', '2nd floor') AND LOWER(?) IN ('f02', '2nd floor'))
                OR (LOWER(TRIM(hr.floor)) IN ('f03', '3rd floor') AND LOWER(?) IN ('f03', '3rd floor'))
                OR (LOWER(TRIM(hr.floor)) IN ('f04', '4th floor') AND LOWER(?) IN ('f04', '4th floor'))
            )";
            $params[] = $mapped_floor;
            $params[] = $mapped_floor;
            $params[] = $mapped_floor;
            $params[] = $mapped_floor;
            $params[] = $mapped_floor;
            $params[] = $mapped_floor;
            $types .= "ssssss";
        }

        // Wing filter
        if (!empty($mapped_wing) && strtolower($mapped_wing) !== 'all') {
            $where_clauses[] = "(hr.wing_code = ? OR hr.wing_code LIKE CONCAT('%', ?, '%') OR ? LIKE CONCAT('%', hr.wing_code, '%'))";
            $params[] = $mapped_wing;
            $params[] = $mapped_wing;
            $params[] = $mapped_wing;
            $types .= "sss";
        }
    }

    if (!empty($where_clauses)) {
        $sql .= " WHERE " . implode(" AND ", $where_clauses);
    }

    $stmt = $conn->prepare($sql);
    if (!empty($params)) {
        $stmt->bind_param($types, ...$params);
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
    
    echo json_encode(array("status" => "success", "data" => $students, "success" => true));

} catch (Exception $e) {
    echo json_encode(array("status" => "error", "message" => $e->getMessage(), "success" => false));
} finally {
    if (isset($conn) && $conn) {
        $conn->close();
    }
}
?>
