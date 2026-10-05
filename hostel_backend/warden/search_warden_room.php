<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';
require_once '../utils/auth_helper.php';

$authUser = requireAuth(['warden', 'admin', 'super_admin', 'security', 'it']);

try {
    $db = (new Database())->getConnection();

    $is_admin = in_array(strtolower($authUser['role'] ?? ''), ['admin', 'super_admin', 'superadmin']);
    $warden_param = $authUser['username'] ?? '';

    if ($is_admin && !empty($_GET['warden_username']) && strtolower(trim($_GET['warden_username'])) !== 'admin') {
        $warden_param = trim($_GET['warden_username']);
    }
    $room_param = trim($_GET['room_number'] ?? $_POST['room_number'] ?? '');

    if (empty($warden_param)) {
        echo json_encode(["success" => false, "message" => "Warden username or ID is required."]);
        exit();
    }

    // 1. Fetch Warden Details
    $w_stmt = $db->prepare("
        SELECT id, username, full_name, role
        FROM users
        WHERE LOWER(TRIM(username)) = LOWER(TRIM(?))
           OR LOWER(TRIM(full_name)) = LOWER(TRIM(?))
        LIMIT 1
    ");
    $w_stmt->execute([$warden_param, $warden_param]);
    $warden_user = $w_stmt->fetch(PDO::FETCH_ASSOC);

    $w_name = $warden_user ? $warden_user['full_name'] : $warden_param;
    $w_bio  = $warden_user ? $warden_user['username']  : $warden_param;

    if ($is_admin && (!isset($_GET['warden_username']) || strtolower(trim($_GET['warden_username'])) === 'admin')) {
        $is_admin = true;
    }

    // 2. Fetch list of ALL rooms assigned to this warden (from rooms_groups_details AND profile table)
    $myRoomsQuery = "
        SELECT DISTINCT rgd.room_number, rgd.group_name as floor_name, rgd.hostel_name, rgd.warden_name, rgd.available_beds, rgd.occupied_beds, rgd.total_beds, rgd.room_type
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
        LEFT JOIN profile p ON (
            (LOWER(p.warden) = LOWER(:w_name) OR LOWER(p.warden) = LOWER(:w_bio))
            AND p.room_allocation = rgd.room_number
        )
        WHERE (
            LOWER(rgd.warden_name) = LOWER(:w_name)
            OR LOWER(rgd.warden_bio_id) = LOWER(:w_bio)
            OR LOWER(rgd.warden_user_id) = LOWER(:w_bio)
            OR ms.id IS NOT NULL
            OR p.id IS NOT NULL
        )
        AND rgd.room_number IS NOT NULL AND rgd.room_number != ''
        ORDER BY rgd.room_number ASC
    ";
    $myRoomsStmt = $db->prepare($myRoomsQuery);
    $myRoomsStmt->execute([
        ':w_name' => $w_name,
        ':w_bio'  => $w_bio,
    ]);
    $my_rooms = $myRoomsStmt->fetchAll(PDO::FETCH_ASSOC);

    // Build a mapping: normalized room number → original format from profile.room_allocation
    // This ensures ALL room numbers display as the original API format (e.g. T-32 F02- W0-R16)
    $normalizedToOriginal = [];
    $mapStmt = $db->query("
        SELECT REPLACE(REPLACE(TRIM(room_allocation), ' ', ''), '-', '') as norm, MAX(room_allocation) as orig
        FROM profile
        WHERE room_allocation IS NOT NULL AND room_allocation != ''
        GROUP BY REPLACE(REPLACE(TRIM(room_allocation), ' ', ''), '-', '')
    ");
    foreach ($mapStmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $normalizedToOriginal[strtoupper($row['norm'])] = $row['orig'];
    }

    // Apply original room number format to all rooms
    foreach ($my_rooms as &$room) {
        $norm = strtoupper(str_replace([' ', '-'], '', $room['room_number']));
        if (isset($normalizedToOriginal[$norm])) {
            $room['room_number'] = $normalizedToOriginal[$norm];
        }
    }
    unset($room);

    $my_room_numbers = array_values(array_unique(array_column($my_rooms, 'room_number')));

    if (empty($room_param)) {
        echo json_encode([
            "success" => true,
            "warden_name" => $w_name,
            "allocated_rooms" => $my_room_numbers,
            "room_details" => $my_rooms,
            "students" => [],
            "message" => "Please enter or select a room number to search."
        ]);
        exit();
    }

    // 3. Search logged-in warden's rooms FIRST!
    $target_room_number = null;
    $target_hostel_name = null;
    $target_floor_name  = null;
    $target_warden_name = null;

    $search_clean = strtolower(str_replace([' ', '-'], '', $room_param));

    // Try exact match in warden's rooms
    foreach ($my_rooms as $mr) {
        $mr_clean = strtolower(str_replace([' ', '-'], '', $mr['room_number']));
        if ($mr_clean === $search_clean || strtolower(trim($mr['room_number'])) === strtolower(trim($room_param))) {
            $target_room_number = $mr['room_number'];
            $target_hostel_name = $mr['hostel_name'];
            $target_floor_name  = $mr['floor_name'];
            $target_warden_name = $mr['warden_name'] ?: $w_name;
            break;
        }
    }

    // Try partial match in warden's rooms
    if (!$target_room_number) {
        foreach ($my_rooms as $mr) {
            $mr_clean = strtolower(str_replace([' ', '-'], '', $mr['room_number']));
            if (str_contains($mr_clean, $search_clean) || str_contains(strtolower($mr['room_number']), strtolower($room_param))) {
                $target_room_number = $mr['room_number'];
                $target_hostel_name = $mr['hostel_name'];
                $target_floor_name  = $mr['floor_name'];
                $target_warden_name = $mr['warden_name'] ?: $w_name;
                break;
            }
        }
    }

    // Global Check if not in warden's rooms
    if (!$target_room_number) {
        $globalCheck = $db->prepare("
            SELECT rgd.room_number, rgd.group_name, rgd.hostel_name, rgd.warden_name
            FROM rooms_groups_details rgd
            WHERE rgd.room_number = :r
               OR REPLACE(rgd.room_number, ' ', '') = REPLACE(:r, ' ', '')
            LIMIT 1
        ");
        $globalCheck->execute([':r' => $room_param]);
        $existing_room = $globalCheck->fetch(PDO::FETCH_ASSOC);

        if (!$existing_room) {
            echo json_encode([
                "success" => true,
                "room_found" => false,
                "access_denied" => false,
                "allocated_rooms" => $my_room_numbers,
                "room_details" => $my_rooms,
                "students" => [],
                "message" => "Room '$room_param' does not exist in the hostel system."
            ]);
            exit();
        }

        if (!$is_admin) {
            echo json_encode([
                "success" => true,
                "room_found" => true,
                "access_denied" => true,
                "allocated_rooms" => $my_room_numbers,
                "room_details" => $my_rooms,
                "students" => [],
                "message" => "Access Denied: Room '$room_param' is assigned to another warden (" . ($existing_room['warden_name'] ?: 'Other Warden') . ")."
            ]);
            exit();
        } else {
            $target_room_number = $existing_room['room_number'];
            $target_hostel_name = $existing_room['hostel_name'];
            $target_floor_name  = $existing_room['group_name'];
            $target_warden_name = $existing_room['warden_name'];
        }
    }

    // 4. Fast Index-backed Students Query directly from profile table
    $studentsQuery = "
        SELECT DISTINCT
            p.full_name as student_name,
            p.reg_no,
            p.personal_phone,
            p.email,
            COALESCE(DATE_FORMAT(p.check_in_date, '%Y-%m-%d'), DATE_FORMAT(p.valid_from, '%Y-%m-%d'), 'N/A') as check_in_date,
            COALESCE(DATE_FORMAT(p.renewal_date, '%Y-%m-%d'), DATE_FORMAT(p.valid_to, '%Y-%m-%d'), 'N/A') as renewal_date,
            COALESCE(NULLIF(p.institution, ''), u.Institution, 'SIMATS') as institution,
            COALESCE(NULLIF(p.hostel_name, ''), u.HostelName, rgd.hostel_name, 'Hostel') as hostel_name,
            COALESCE(NULLIF(p.room_allocation, ''), u.RoomId, rgd.room_number) as room_allocation,
            u.id as user_id,
            u.username,
            COALESCE(u.Status, 'Active') as status,
            rgd.group_name as floor_name,
            rgd.room_number,
            rgd.room_type,
            rgd.warden_name
        FROM profile p
        LEFT JOIN users u ON (p.reg_no = u.username)
        LEFT JOIN rooms_groups_details rgd ON (
            rgd.room_number = :tr
            OR REPLACE(REPLACE(TRIM(rgd.room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(:tr2), ' ', ''), '-', '')
        )
        WHERE REPLACE(REPLACE(TRIM(p.room_allocation), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(:tr3), ' ', ''), '-', '')
           OR REPLACE(REPLACE(TRIM(u.RoomId), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(:tr4), ' ', ''), '-', '')
        ORDER BY p.full_name ASC
    ";
    $studentsStmt = $db->prepare($studentsQuery);
    $studentsStmt->execute([':tr' => $target_room_number, ':tr2' => $target_room_number, ':tr3' => $target_room_number, ':tr4' => $target_room_number]);
    $students = $studentsStmt->fetchAll(PDO::FETCH_ASSOC);

    // 5. Fetch room specifications
    $roomSpecStmt = $db->prepare("
        SELECT total_beds, occupied_beds, available_beds, room_type
        FROM rooms_groups_details
        WHERE room_number = :tr
           OR REPLACE(REPLACE(TRIM(room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(:tr2), ' ', ''), '-', '')
        LIMIT 1
    ");
    $roomSpecStmt->execute([':tr' => $target_room_number, ':tr2' => $target_room_number]);
    $room_spec = $roomSpecStmt->fetch(PDO::FETCH_ASSOC) ?: [];

    $totalBeds    = intval($room_spec['total_beds'] ?? 4);
    // Prefer external API's occupied count (from rooms_groups_details) over local profile count
    // Local profile may miss students whose room_allocation format differs
    $localCount   = count($students);
    $apiOccupied  = intval($room_spec['occupied_beds'] ?? -1);
    $occupiedBeds = ($apiOccupied >= 0) ? max($apiOccupied, $localCount) : $localCount;
    $vacancyBeds  = max(0, $totalBeds - $occupiedBeds);
    $roomType = !empty($room_spec['room_type']) ? $room_spec['room_type'] : ($students[0]['room_type'] ?? '3 IN 1 B and T Attached AC');

    // Get original room number format from profile (e.g. T-32 F02- W0-R16 as the API returns it)
    $origRoomStmt = $db->prepare("
        SELECT room_allocation FROM profile 
        WHERE REPLACE(REPLACE(TRIM(room_allocation), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(:rn), ' ', ''), '-', '')
          AND room_allocation IS NOT NULL AND room_allocation != ''
        LIMIT 1
    ");
    $origRoomStmt->execute([':rn' => $target_room_number]);
    $origRoom = $origRoomStmt->fetchColumn() ?: $target_room_number;

    echo json_encode([
        "success" => true,
        "room_found" => true,
        "access_denied" => false,
        "room_number" => $origRoom,
        "hostel_name" => $target_hostel_name,
        "floor_name" => $target_floor_name,
        "warden_name" => $target_warden_name,
        "total_beds" => $totalBeds,
        "occupied_beds" => $occupiedBeds,
        "vacancy_beds" => $vacancyBeds,
        "room_type" => $roomType,
        "allocated_rooms" => $my_room_numbers,
        "room_details" => $my_rooms,
        "student_count" => count($students),
        "students" => $students,
        "message" => count($students) > 0 
            ? "Found " . count($students) . " student(s) allocated to " . $target_room_number
            : "No students are currently allocated to this room."
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Server error: " . $e->getMessage()
    ]);
}
