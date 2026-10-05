<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/auth_helper.php';

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $raw_input = file_get_contents('php://input');
    $post_data = json_decode($raw_input, true) ?? [];

    $reg_no = trim($_GET['reg_no'] ?? $post_data['reg_no'] ?? $_GET['student_id'] ?? $post_data['student_id'] ?? '');
    $warden_username = trim($_GET['warden_username'] ?? $post_data['warden_username'] ?? '');

    if (empty($warden_username)) {
        $auth_header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
        if (empty($auth_header) && function_exists('apache_request_headers')) {
            $headers = apache_request_headers();
            $auth_header = $headers['Authorization'] ?? $headers['authorization'] ?? '';
        }
        if (preg_match('/Bearer\s+(.*)$/i', $auth_header, $matches)) {
            $payload = validateJWT($matches[1]);
            if ($payload) $warden_username = $payload['username'] ?? '';
        }
    }

    if (empty($reg_no)) {
        echo json_encode([
            "success" => false,
            "status" => "error",
            "error_code" => "EMPTY_REG_NO",
            "message" => "Please provide student register number."
        ]);
        exit();
    }

    // 1. Resolve Warden Role and Assigned Rooms/Floors
    $is_admin = false;
    $w_name = $warden_username;
    $w_bio = $warden_username;

    if (!empty($warden_username)) {
        $w_stmt = $db->prepare("
            SELECT id, username, full_name, role
            FROM users
            WHERE LOWER(TRIM(username)) = LOWER(TRIM(:w))
               OR LOWER(TRIM(full_name)) = LOWER(TRIM(:w))
            LIMIT 1
        ");
        $w_stmt->execute([':w' => $warden_username]);
        $w_user = $w_stmt->fetch(PDO::FETCH_ASSOC);

        if ($w_user) {
            $w_name = $w_user['full_name'];
            $w_bio = $w_user['username'];
            if (in_array(strtolower($w_user['role']), ['admin', 'superadmin', 'super_admin'])) {
                $is_admin = true;
            }
        }
        if (strtolower($warden_username) === 'admin') {
            $is_admin = true;
        }
    }

    // 2. Lookup Student in profile and users table
    $s_stmt = $db->prepare("
        SELECT 
            p.id as profile_id,
            p.full_name,
            p.reg_no,
            COALESCE(NULLIF(p.room_allocation, ''), u.RoomId, '') as room_allocation,
            COALESCE(NULLIF(p.hostel_name, ''), u.HostelName, '') as hostel_name,
            COALESCE(NULLIF(p.institution, ''), u.Institution, 'SIMATS') as institution,
            u.id as user_id,
            u.phone_number,
            u.ParentContact as parent_phone
        FROM profile p
        LEFT JOIN users u ON (LOWER(TRIM(p.reg_no)) = LOWER(TRIM(u.username)))
        WHERE LOWER(TRIM(p.reg_no)) = LOWER(TRIM(:reg))
           OR LOWER(TRIM(u.username)) = LOWER(TRIM(:reg))
        LIMIT 1
    ");
    $s_stmt->execute([':reg' => $reg_no]);
    $student = $s_stmt->fetch(PDO::FETCH_ASSOC);

    // Fallback: If not in profile, check users table directly
    if (!$student) {
        $u_stmt = $db->prepare("
            SELECT 
                id as user_id,
                full_name,
                username as reg_no,
                RoomId as room_allocation,
                HostelName as hostel_name,
                Institution as institution,
                phone_number,
                ParentContact as parent_phone
            FROM users
            WHERE LOWER(TRIM(username)) = LOWER(TRIM(:reg))
            LIMIT 1
        ");
        $u_stmt->execute([':reg' => $reg_no]);
        $student = $u_stmt->fetch(PDO::FETCH_ASSOC);
    }

    if (!$student) {
        echo json_encode([
            "success" => false,
            "status" => "error",
            "error_code" => "STUDENT_NOT_FOUND",
            "message" => "Student with Register Number '$reg_no' was not found in the records."
        ]);
        exit();
    }

    $room_allocation = trim($student['room_allocation'] ?? '');
    $hostel_name = trim($student['hostel_name'] ?? '');
    $student_name = trim($student['full_name'] ?? 'Student');
    $student_reg = trim($student['reg_no'] ?? $reg_no);

    // 3. Check if Student is Allocated to a Room
    $is_unallocated = empty($room_allocation) || 
                      in_array(strtolower($room_allocation), ['null', 'unallocated', 'n/a', 'none', 'pending', '0']);

    if ($is_unallocated) {
        echo json_encode([
            "success" => false,
            "status" => "error",
            "error_code" => "NOT_ALLOCATED",
            "message" => "Student $student_name ($student_reg) has not been allocated to any room yet. Please allocate a room before enrolling face biometric.",
            "student" => [
                "reg_no" => $student_reg,
                "full_name" => $student_name,
                "is_allocated" => false,
                "room_no" => null,
                "floor_name" => null,
                "hostel_name" => $hostel_name
            ]
        ]);
        exit();
    }

    // 4. Resolve the Allocated Room's Details (Floor, Hostel, Assigned Warden)
    $rgd_stmt = $db->prepare("
        SELECT 
            room_number,
            group_name as floor_name,
            hostel_name,
            warden_name,
            warden_bio_id,
            warden_user_id
        FROM rooms_groups_details
        WHERE room_number = :room
           OR REPLACE(REPLACE(TRIM(room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(:room), ' ', ''), '-', '')
        LIMIT 1
    ");
    $rgd_stmt->execute([':room' => $room_allocation]);
    $room_details = $rgd_stmt->fetch(PDO::FETCH_ASSOC);

    $floor_name = $room_details['floor_name'] ?? 'Floor';
    $assigned_hostel = !empty($room_details['hostel_name']) ? $room_details['hostel_name'] : $hostel_name;
    $assigned_warden_name = trim($room_details['warden_name'] ?? '');
    $assigned_warden_bio = trim($room_details['warden_bio_id'] ?? '');

    // Check mapping_staff for this floor if warden_name is empty in rooms_groups_details
    if (empty($assigned_warden_name)) {
        $ms_stmt = $db->prepare("
            SELECT name, staff_bio_id, username
            FROM mapping_staff
            WHERE (
                LOWER(floor_name) = 'all' 
                OR LOWER(floor_name) LIKE CONCAT('%', LOWER(:floor), '%')
                OR LOWER(:floor) LIKE CONCAT('%', LOWER(floor_name), '%')
            )
            LIMIT 1
        ");
        $ms_stmt->execute([':floor' => $floor_name]);
        $ms_row = $ms_stmt->fetch(PDO::FETCH_ASSOC);
        if ($ms_row) {
            $assigned_warden_name = $ms_row['name'] ?? $ms_row['username'] ?? '';
            $assigned_warden_bio = $ms_row['staff_bio_id'] ?? $ms_row['username'] ?? '';
        }
    }

    if (empty($assigned_warden_name)) {
        $assigned_warden_name = "Warden of $floor_name";
    }

    // 5. Check if the Current Logged-in Warden is Authorized for this Student's Floor / Room
    $is_authorized = false;

    if ($is_admin) {
        $is_authorized = true;
    } else if (!empty($warden_username)) {
        // Direct match on room's warden
        if (!empty($assigned_warden_bio) && (strtolower($assigned_warden_bio) === strtolower($w_bio) || strtolower($assigned_warden_bio) === strtolower($warden_username))) {
            $is_authorized = true;
        } else if (!empty($assigned_warden_name) && (strtolower($assigned_warden_name) === strtolower($w_name) || strtolower($assigned_warden_name) === strtolower($warden_username))) {
            $is_authorized = true;
        } else {
            // Check mapping_staff for logged in warden
            $check_ms = $db->prepare("
                SELECT id
                FROM mapping_staff
                WHERE (
                    LOWER(username) = LOWER(:w_bio) 
                    OR LOWER(staff_bio_id) = LOWER(:w_bio) 
                    OR LOWER(name) = LOWER(:w_name)
                )
                AND (
                    LOWER(hostel_name) = 'all' 
                    OR LOWER(hostel_name) LIKE CONCAT('%', LOWER(:hostel), '%') 
                    OR LOWER(:hostel) LIKE CONCAT('%', LOWER(hostel_name), '%')
                )
                AND (
                    LOWER(floor_name) = 'all'
                    OR LOWER(floor_name) LIKE CONCAT('%', LOWER(:floor), '%')
                    OR LOWER(:floor) LIKE CONCAT('%', LOWER(floor_name), '%')
                )
                LIMIT 1
            ");
            $check_ms->execute([
                ':w_bio' => $w_bio,
                ':w_name' => $w_name,
                ':hostel' => $assigned_hostel,
                ':floor' => $floor_name
            ]);
            if ($check_ms->fetch()) {
                $is_authorized = true;
            }
        }
    }

    // 6. Return Response
    if (!$is_authorized) {
        echo json_encode([
            "success" => false,
            "status" => "error",
            "error_code" => "ALLOCATED_TO_OTHER_WARDEN",
            "message" => "Unauthorized Floor: Student $student_name ($student_reg) is allocated to Room $room_allocation ($floor_name, $assigned_hostel) under Warden '$assigned_warden_name'. Only their assigned floor warden can enroll their biometric face.",
            "student" => [
                "reg_no" => $student_reg,
                "full_name" => $student_name,
                "is_allocated" => true,
                "is_assigned_to_you" => false,
                "room_no" => $room_allocation,
                "floor_name" => $floor_name,
                "hostel_name" => $assigned_hostel,
                "assigned_warden" => $assigned_warden_name
            ]
        ]);
        exit();
    }

    echo json_encode([
        "success" => true,
        "status" => "success",
        "message" => "Student verified successfully for enrollment on your floor.",
        "student" => [
            "reg_no" => $student_reg,
            "full_name" => $student_name,
            "is_allocated" => true,
            "is_assigned_to_you" => true,
            "room_no" => $room_allocation,
            "floor_name" => $floor_name,
            "hostel_name" => $assigned_hostel,
            "assigned_warden" => $assigned_warden_name
        ]
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "success" => false,
        "status" => "error",
        "error_code" => "SERVER_ERROR",
        "message" => "Error verifying student: " . $e->getMessage()
    ]);
}
