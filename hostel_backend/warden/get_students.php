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

try {
    $db = (new Database())->getConnection();

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
        echo json_encode(array("status" => "success", "data" => [], "locations" => [], "success" => true));
        exit();
    }

    // Resolve full name & user details for warden
    $w_stmt = $db->prepare("
        SELECT id, username, full_name, role
        FROM users
        WHERE LOWER(TRIM(username)) = LOWER(TRIM(:w))
           OR LOWER(TRIM(full_name)) = LOWER(TRIM(:w))
        LIMIT 1
    ");
    $w_stmt->execute([':w' => $warden_username]);
    $w_user = $w_stmt->fetch(PDO::FETCH_ASSOC);

    $w_name = $w_user ? $w_user['full_name'] : $warden_username;
    $w_bio  = $w_user ? $w_user['username']  : $warden_username;
    $is_admin = ($w_user && in_array(strtolower($w_user['role']), ['admin', 'superadmin'])) || strtolower($warden_username) === 'admin';

    if ($is_admin) {
        // ADMIN QUERY
        $stmt = $db->prepare("
            SELECT DISTINCT
                p.id as profile_id,
                p.full_name,
                p.reg_no as register_number,
                COALESCE(NULLIF(p.room_allocation, ''), u.RoomId, rgd.room_number) as room_no,
                COALESCE(NULLIF(p.institution, ''), u.Institution, 'SIMATS') as institution,
                u.id as user_id,
                u.conduct,
                u.Status,
                rgd.room_number as room_code,
                COALESCE(NULLIF(rgd.hostel_name, ''), p.hostel_name, u.HostelName) as hostel_name,
                COALESCE(NULLIF(rgd.group_name, ''), 'Default Floor') as floor,
                'General' as wing_code
            FROM profile p
            LEFT JOIN users u ON (p.reg_no = u.username)
            LEFT JOIN rooms_groups_details rgd ON (
                p.room_allocation = rgd.room_number 
                OR u.RoomId = rgd.room_number
                OR REPLACE(REPLACE(TRIM(rgd.room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(COALESCE(NULLIF(p.room_allocation,''), u.RoomId)), ' ', ''), '-', '')
            )
            WHERE (p.room_allocation IS NOT NULL AND p.room_allocation != '')
               OR (u.RoomId IS NOT NULL AND u.RoomId != '')
            ORDER BY p.full_name ASC
        ");
        $stmt->execute();
        $raw_students = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $locStmt = $db->prepare("
            SELECT DISTINCT hostel_name, group_name as floor_name, 'W0' as wing_name, room_number
            FROM rooms_groups_details
            WHERE room_number IS NOT NULL AND room_number != ''
            ORDER BY room_number ASC
        ");
        $locStmt->execute();
        $locations = $locStmt->fetchAll(PDO::FETCH_ASSOC);
    } else {
        // 1. Fetch mapped rooms for this warden
        $myRoomsStmt = $db->prepare("
            SELECT DISTINCT rgd.room_number, rgd.group_name as floor_name, rgd.hostel_name
            FROM rooms_groups_details rgd
            LEFT JOIN mapping_staff ms ON (
                (LOWER(ms.username) = LOWER(:w_bio) OR LOWER(ms.staff_bio_id) = LOWER(:w_bio) OR LOWER(ms.name) = LOWER(:w_name))
                AND (
                    LOWER(ms.hostel_name) = 'all'
                    OR LOWER(rgd.hostel_name) LIKE CONCAT('%', LOWER(ms.hostel_name), '%')
                    OR LOWER(ms.hostel_name) LIKE CONCAT('%', LOWER(rgd.hostel_name), '%')
                )
                AND (
                    LOWER(ms.floor_name) = 'all'
                    OR (
                        rgd.group_name IS NOT NULL AND rgd.group_name != ''
                        AND (
                            LOWER(rgd.group_name) LIKE CONCAT('%', LOWER(ms.floor_name), '%')
                            OR LOWER(ms.floor_name) LIKE CONCAT('%', LOWER(rgd.group_name), '%')
                        )
                    )
                )
            )
            WHERE (
                (LOWER(rgd.warden_name) = LOWER(:w_name) OR LOWER(rgd.warden_bio_id) = LOWER(:w_bio) OR LOWER(rgd.warden_user_id) = LOWER(:w_bio))
                OR ms.id IS NOT NULL
            )
            AND rgd.room_number IS NOT NULL AND rgd.room_number != ''
            ORDER BY rgd.room_number ASC
        ");
        $myRoomsStmt->execute([':w_bio' => $w_bio, ':w_name' => $w_name]);
        $my_rooms = $myRoomsStmt->fetchAll(PDO::FETCH_ASSOC);

        $locations = array();
        $room_numbers = array();
        foreach ($my_rooms as $r) {
            $room_numbers[] = $r['room_number'];
            $locations[] = array(
                "hostel_name" => $r['hostel_name'],
                "floor_name"  => $r['floor_name'],
                "wing_name"   => "W0",
                "room_number" => $r['room_number']
            );
        }

        if (empty($room_numbers)) {
            echo json_encode(array("status" => "success", "data" => [], "locations" => [], "success" => true));
            exit();
        }

        // 2. Fast Index-Backed Students Query using IN (...)
        $in_clause = implode(',', array_fill(0, count($room_numbers), '?'));
        
        $sql = "
            SELECT DISTINCT
                p.id as profile_id,
                p.full_name,
                p.reg_no as register_number,
                COALESCE(NULLIF(p.room_allocation, ''), u.RoomId, rgd.room_number) as room_no,
                COALESCE(NULLIF(p.institution, ''), u.Institution, 'SIMATS') as institution,
                u.id as user_id,
                u.conduct,
                u.Status,
                rgd.room_number as room_code,
                COALESCE(NULLIF(rgd.hostel_name, ''), p.hostel_name, u.HostelName) as hostel_name,
                COALESCE(NULLIF(rgd.group_name, ''), 'Default Floor') as floor,
                'General' as wing_code
            FROM rooms_groups_details rgd
            JOIN profile p ON (p.room_allocation = rgd.room_number)
            LEFT JOIN users u ON (u.username = p.reg_no)
            WHERE rgd.room_number IN ($in_clause)
            
            UNION
            
            SELECT DISTINCT
                p.id as profile_id,
                p.full_name,
                p.reg_no as register_number,
                COALESCE(NULLIF(p.room_allocation, ''), u.RoomId, rgd.room_number) as room_no,
                COALESCE(NULLIF(p.institution, ''), u.Institution, 'SIMATS') as institution,
                u.id as user_id,
                u.conduct,
                u.Status,
                rgd.room_number as room_code,
                COALESCE(NULLIF(rgd.hostel_name, ''), p.hostel_name, u.HostelName) as hostel_name,
                COALESCE(NULLIF(rgd.group_name, ''), 'Default Floor') as floor,
                'General' as wing_code
            FROM rooms_groups_details rgd
            JOIN users u ON (u.RoomId = rgd.room_number)
            LEFT JOIN profile p ON (p.reg_no = u.username)
            WHERE rgd.room_number IN ($in_clause)

            ORDER BY full_name ASC
        ";

        $stmt = $db->prepare($sql);
        // Bind parameters for both IN clauses
        $params = array_merge($room_numbers, $room_numbers);
        $stmt->execute($params);
        $raw_students = $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    $students = array();
    foreach ($raw_students as $row) {
        $row['id'] = $row['user_id'] ?: $row['profile_id'];
        $students[] = array_map(function($val) {
            return is_string($val) ? mb_convert_encoding($val, 'UTF-8', 'UTF-8') : $val;
        }, $row);
    }

    echo json_encode(array(
        "status" => "success",
        "data" => $students,
        "locations" => $locations,
        "success" => true
    ));

} catch (Exception $e) {
    echo json_encode(array("status" => "error", "message" => $e->getMessage(), "success" => false));
}
