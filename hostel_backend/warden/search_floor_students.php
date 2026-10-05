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

$authUser = requireAuth(['warden', 'admin', 'super_admin', 'security', 'it']);

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $raw_input = file_get_contents('php://input');
    $post_data = json_decode($raw_input, true) ?? [];

    $is_admin = in_array(strtolower($authUser['role'] ?? ''), ['admin', 'super_admin', 'superadmin']);
    $warden_username = $authUser['username'] ?? '';

    // Only authorized admins can filter by another warden's username
    if ($is_admin && !empty($_GET['warden_username']) && strtolower(trim($_GET['warden_username'])) !== 'admin') {
        $warden_username = trim($_GET['warden_username']);
    }

    $query = trim($_GET['query'] ?? $_GET['q'] ?? $_GET['reg_no'] ?? $post_data['query'] ?? $post_data['reg_no'] ?? '');

    // 1. Resolve Warden Role and Assigned Rooms/Floors
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
        }
    }

    $rows = [];

    if ($is_admin) {
        // Admin can search any allocated student
        $sql = "
            SELECT DISTINCT
                p.id as profile_id,
                p.full_name,
                p.reg_no as register_number,
                COALESCE(NULLIF(p.room_allocation, ''), u.RoomId, rgd.room_number) as room_no,
                COALESCE(NULLIF(rgd.group_name, ''), 'General Floor') as floor_name,
                COALESCE(NULLIF(rgd.hostel_name, ''), p.hostel_name, u.HostelName) as hostel_name
            FROM profile p
            LEFT JOIN users u ON (p.reg_no = u.username)
            LEFT JOIN rooms_groups_details rgd ON (
                p.room_allocation = rgd.room_number
                OR u.RoomId = rgd.room_number
                OR REPLACE(REPLACE(TRIM(rgd.room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(COALESCE(NULLIF(p.room_allocation,''), u.RoomId)), ' ', ''), '-', '')
            )
            WHERE (
                (p.room_allocation IS NOT NULL AND p.room_allocation != '' AND LOWER(p.room_allocation) NOT IN ('null', 'unallocated', 'none', 'n/a', 'pending', '0'))
                OR (u.RoomId IS NOT NULL AND u.RoomId != '' AND LOWER(u.RoomId) NOT IN ('null', 'unallocated', 'none', 'n/a', 'pending', '0'))
            )
        ";

        $params = [];
        if (!empty($query)) {
            $sql .= " AND (p.reg_no LIKE :q1 OR p.full_name LIKE :q2 OR u.username LIKE :q3 OR u.full_name LIKE :q4) ";
            $params[':q1'] = "%$query%";
            $params[':q2'] = "%$query%";
            $params[':q3'] = "%$query%";
            $params[':q4'] = "%$query%";
        }

        $sql .= " ORDER BY (p.reg_no LIKE :exact_prefix) DESC, p.full_name ASC";
        $params[':exact_prefix'] = "$query%";

        $stmt = $db->prepare($sql);
        $stmt->execute($params);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    } else {
        // Floor Warden: Fetch all rooms assigned to this warden
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
        ");
        $myRoomsStmt->execute([':w_bio' => $w_bio, ':w_name' => $w_name]);
        $my_rooms = $myRoomsStmt->fetchAll(PDO::FETCH_ASSOC);

        $room_numbers = [];
        foreach ($my_rooms as $r) {
            $room_numbers[] = $r['room_number'];
        }

        // Also check if profile table has students mapped to warden directly
        $profWardenStmt = $db->prepare("
            SELECT DISTINCT room_allocation
            FROM profile
            WHERE (LOWER(warden) = LOWER(:w_name) OR LOWER(warden) = LOWER(:w_bio))
              AND room_allocation IS NOT NULL AND room_allocation != ''
        ");
        $profWardenStmt->execute([':w_name' => $w_name, ':w_bio' => $w_bio]);
        while ($pwRow = $profWardenStmt->fetch(PDO::FETCH_ASSOC)) {
            $room_numbers[] = $pwRow['room_allocation'];
        }

        $room_numbers = array_values(array_unique(array_filter($room_numbers)));

        if (empty($room_numbers)) {
            echo json_encode([
                "success" => true,
                "status" => "success",
                "warden_username" => $warden_username,
                "count" => 0,
                "students" => []
            ]);
            exit();
        }

        $in_clause = implode(',', array_fill(0, count($room_numbers), '?'));

        $sql = "
            SELECT DISTINCT
                p.id as profile_id,
                p.full_name,
                p.reg_no as register_number,
                COALESCE(NULLIF(p.room_allocation, ''), u.RoomId, rgd.room_number) as room_no,
                COALESCE(NULLIF(rgd.group_name, ''), 'Floor') as floor_name,
                COALESCE(NULLIF(rgd.hostel_name, ''), p.hostel_name, u.HostelName) as hostel_name
            FROM rooms_groups_details rgd
            JOIN profile p ON (
                p.room_allocation = rgd.room_number
                OR REPLACE(REPLACE(TRIM(rgd.room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(p.room_allocation), ' ', ''), '-', '')
            )
            LEFT JOIN users u ON (u.username = p.reg_no)
            WHERE rgd.room_number IN ($in_clause)
        ";

        $params = $room_numbers;

        if (!empty($query)) {
            $sql .= " AND (
                p.reg_no LIKE ? 
                OR p.full_name LIKE ? 
                OR u.username LIKE ? 
                OR u.full_name LIKE ?
            )";
            $params[] = "%$query%";
            $params[] = "%$query%";
            $params[] = "%$query%";
            $params[] = "%$query%";
        }

        $sql .= "
            UNION
            
            SELECT DISTINCT
                p.id as profile_id,
                p.full_name,
                p.reg_no as register_number,
                COALESCE(NULLIF(p.room_allocation, ''), u.RoomId, rgd.room_number) as room_no,
                COALESCE(NULLIF(rgd.group_name, ''), 'Floor') as floor_name,
                COALESCE(NULLIF(rgd.hostel_name, ''), p.hostel_name, u.HostelName) as hostel_name
            FROM rooms_groups_details rgd
            JOIN users u ON (
                u.RoomId = rgd.room_number
                OR REPLACE(REPLACE(TRIM(rgd.room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(u.RoomId), ' ', ''), '-', '')
            )
            LEFT JOIN profile p ON (p.reg_no = u.username)
            WHERE rgd.room_number IN ($in_clause)
        ";

        $params = array_merge($params, $room_numbers);

        if (!empty($query)) {
            $sql .= " AND (
                u.username LIKE ? 
                OR u.full_name LIKE ? 
                OR p.reg_no LIKE ? 
                OR p.full_name LIKE ?
            )";
            $params[] = "%$query%";
            $params[] = "%$query%";
            $params[] = "%$query%";
            $params[] = "%$query%";
        }

        $sql .= " ORDER BY full_name ASC";

        $stmt = $db->prepare($sql);
        $stmt->execute($params);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    $students = [];
    $seen_regs = [];
    foreach ($rows as $row) {
        $reg = trim($row['register_number'] ?? '');
        if (empty($reg) || isset($seen_regs[strtolower($reg)])) continue;
        $seen_regs[strtolower($reg)] = true;

        $students[] = [
            'reg_no' => $reg,
            'register_number' => $reg,
            'full_name' => trim($row['full_name'] ?? 'Student'),
            'room_no' => trim($row['room_no'] ?? ''),
            'floor_name' => trim($row['floor_name'] ?? ''),
            'hostel_name' => trim($row['hostel_name'] ?? ''),
            'is_face_enrolled' => false,
            'is_allocated' => true,
            'is_assigned_to_you' => true,
        ];
    }

    echo json_encode([
        "success" => true,
        "status" => "success",
        "warden_username" => $warden_username,
        "query" => $query,
        "count" => count($students),
        "students" => $students
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "success" => false,
        "status" => "error",
        "message" => "Error searching floor students: " . $e->getMessage()
    ]);
}
