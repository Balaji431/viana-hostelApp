<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

$database = new Database();
$db = $database->getConnection();

$target_dept = strtolower($_GET['department'] ?? $_GET['channel'] ?? 'warden');
if (strpos($target_dept, 'maint') !== false) $target_dept = 'maintenance';
if (strpos($target_dept, 'sec') !== false) $target_dept = 'security';
$warden_username = $_GET['warden_username'] ?? $_GET['staff_username'] ?? null;

try {
    // 1. Resolve mapping_role from mapping_staff (use actual stored role, case-insensitive)
    $mapping_role = null;
    if ($warden_username) {
        $role_check = $db->prepare("SELECT role FROM mapping_staff WHERE LOWER(TRIM(username)) = LOWER(TRIM(?)) OR LOWER(TRIM(staff_bio_id)) = LOWER(TRIM(?)) LIMIT 1");
        $role_check->execute([$warden_username, $warden_username]);
        $mapping_role = $role_check->fetchColumn();
    }
    // Fallback: derive from dept name
    if (!$mapping_role) {
        if ($target_dept === 'warden' || $target_dept === 'parent_warden') $mapping_role = 'Warden';
        else if ($target_dept === 'security') $mapping_role = 'Security';
        else if ($target_dept === 'maintenance') $mapping_role = 'Maintenance';
        else $mapping_role = ucfirst($target_dept);
    }

    // 2. Resolve all student IDs mapped to this warden
    $mapped_student_ids = [];

    if ($warden_username && $warden_username === 'warden1' && ($target_dept === 'warden' || $target_dept === 'parent_warden')) {
        // warden1 is the main warden: handles room allocation requests from vstudy_payments
        // Fetches all students present in vstudy_payments who don't have a room yet
        $sub_stmt = $db->prepare("SELECT u.id FROM users u 
                          JOIN profile p ON (CONVERT(u.username USING utf8mb4) = CONVERT(p.reg_no USING utf8mb4))
                          JOIN vstudy_payments vp ON (CONVERT(p.reg_no USING utf8mb4) = CONVERT(vp.roll_number USING utf8mb4))
                          WHERE (p.room_allocation IS NULL 
                             OR p.room_allocation = '' 
                             OR LOWER(TRIM(p.room_allocation)) = 'unallocated')");
        $sub_stmt->execute();
        $mapped_student_ids = $sub_stmt->fetchAll(PDO::FETCH_COLUMN);

    } else if ($warden_username) {
        // Normal warden / staff: students in matching hostel/floor/wing from rooms_groups_details & mapping_staff
        $sub_stmt = $db->prepare("
            SELECT DISTINCT u.id 
            FROM users u
            JOIN profile p ON TRIM(u.username) = TRIM(p.reg_no)
            JOIN rooms_groups_details rgd ON TRIM(p.room_allocation) = TRIM(rgd.room_number)
            JOIN mapping_staff ms ON (TRIM(ms.username) = TRIM(?) OR TRIM(ms.staff_bio_id) = TRIM(?))
            WHERE (
                LOWER(TRIM(ms.role)) = LOWER(TRIM(?))
                OR (LOWER(TRIM(?)) IN ('warden', 'parent_warden') AND LOWER(TRIM(ms.role)) LIKE '%warden%')
                OR (LOWER(TRIM(?)) = 'security' AND LOWER(TRIM(ms.role)) LIKE '%security%')
                OR (LOWER(TRIM(?)) = 'maintenance' AND LOWER(TRIM(ms.role)) LIKE '%maint%')
            )
            AND (
                LOWER(TRIM(ms.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(rgd.hostel_name)), '%')
                OR LOWER(TRIM(rgd.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(ms.hostel_name)), '%')
                OR ms.hostel_name IS NULL OR ms.hostel_name = ''
            )
            AND (
                LOWER(TRIM(ms.floor_name)) LIKE CONCAT('%', LOWER(TRIM(rgd.group_name)), '%')
                OR LOWER(TRIM(rgd.group_name)) LIKE CONCAT('%', LOWER(TRIM(ms.floor_name)), '%')
                OR ms.floor_name IS NULL OR ms.floor_name = ''
            )
            AND (
                rgd.room_number LIKE CONCAT('%-', TRIM(ms.wing_name), '-%')
                OR ms.wing_name IS NULL OR ms.wing_name = '' OR TRIM(ms.wing_name) = 'W0' OR LOWER(TRIM(ms.wing_name)) = 'all'
            )
        ");
        $sub_stmt->execute([$warden_username, $warden_username, $mapping_role, $target_dept, $target_dept, $target_dept]);
        $mapped_student_ids = $sub_stmt->fetchAll(PDO::FETCH_COLUMN);

        // Also fetch any student who has an existing chat message or request with this staff member
        $existing_stmt = $db->prepare("
            SELECT DISTINCT r.student_id 
            FROM request1 r
            JOIN chat_messages cm ON (CONVERT(r.request_id USING utf8mb4) = CONVERT(cm.request_id USING utf8mb4))
            WHERE (cm.sender_id = ? OR cm.receiver_id = ?)
              AND (LOWER(r.department) = LOWER(?) OR LOWER(r.department) LIKE CONCAT('%', LOWER(SUBSTRING(?, 1, 4)), '%'))
        ");
        $existing_stmt->execute([$warden_username, $warden_username, $target_dept, $target_dept]);
        $existing_ids = $existing_stmt->fetchAll(PDO::FETCH_COLUMN);
        
        $mapped_student_ids = array_unique(array_merge($mapped_student_ids, $existing_ids));
    }

    // 3. (On-Demand Mode) No pre-creation of dummy request1 rows.
    // Threads are created in request1 ONLY when a real message is sent.

    // Build safe IN clause
    $id_list_placeholder = "0";
    if (!empty($mapped_student_ids)) {
        $id_list_placeholder = implode(',', array_map('intval', $mapped_student_ids));
    }

    // 4. Fetch conversation summaries for all mapped students
    $query = "
        SELECT 
            COALESCE(
                (SELECT r2.request_id FROM request1 r2 
                 WHERE r2.student_id = u.id AND LOWER(r2.department) = LOWER(:target_dept) 
                 ORDER BY r2.id DESC LIMIT 1),
                CONCAT(UPPER(SUBSTRING(:target_dept, 1, 3)), '-', u.id)
            ) as request_id,
            u.id as student_id,
            u.username as student_username,
            CASE 
                WHEN LOWER(:target_dept2) = 'parent_warden' THEN CONCAT('Parent of ', u.full_name)
                ELSE u.full_name 
            END as name,
            (SELECT p2.room_allocation FROM profile p2 
             WHERE LOWER(TRIM(p2.reg_no)) = LOWER(TRIM(u.username)) LIMIT 1) as room_allocation,
            COALESCE(
                (SELECT cm.message FROM chat_messages cm 
                 JOIN request1 r4 ON (CONVERT(cm.request_id USING utf8mb4) = CONVERT(r4.request_id USING utf8mb4)) 
                 WHERE r4.student_id = u.id AND LOWER(r4.department) = LOWER(:target_dept3)
                 ORDER BY cm.id DESC LIMIT 1), 
                'No messages yet'
            ) as last_msg,
            COALESCE(
                (SELECT cm2.timestamp FROM chat_messages cm2 
                 JOIN request1 r5 ON (CONVERT(cm2.request_id USING utf8mb4) = CONVERT(r5.request_id USING utf8mb4)) 
                 WHERE r5.student_id = u.id AND LOWER(r5.department) = LOWER(:target_dept4)
                 ORDER BY cm2.id DESC LIMIT 1), 
                (SELECT MAX(r6.created_at) FROM request1 r6 
                 WHERE r6.student_id = u.id AND LOWER(r6.department) = LOWER(:target_dept5))
            ) as last_time,
            (SELECT COUNT(*) FROM chat_messages cm3 
             JOIN request1 r7 ON (CONVERT(cm3.request_id USING utf8mb4) = CONVERT(r7.request_id USING utf8mb4)) 
             WHERE r7.student_id = u.id AND LOWER(r7.department) = LOWER(:target_dept6)
             AND cm3.status IN ('sent', 'delivered')
             AND cm3.message_type NOT IN ('request_card', 'status')
             AND (
                 CONVERT(cm3.sender_id USING utf8mb4) = CONVERT(u.username USING utf8mb4)
                 OR CONVERT(cm3.sender_id USING utf8mb4) = CONVERT(u.id USING utf8mb4)
                 OR CONVERT(cm3.sender_id USING utf8mb4) LIKE 'p-%'
             )
            ) as unread_count
        FROM users u
        WHERE u.id IN ($id_list_placeholder)
        ORDER BY unread_count DESC, last_time DESC
    ";

    $params = [
        ':target_dept'  => $target_dept,
        ':target_dept2' => $target_dept,
        ':target_dept3' => $target_dept,
        ':target_dept4' => $target_dept,
        ':target_dept5' => $target_dept,
        ':target_dept6' => $target_dept,
    ];

    $stmt = $db->prepare($query);
    $stmt->execute($params);
    $conversations = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "success" => true,
        "data" => $conversations
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Database error: " . $e->getMessage()
    ]);
}
?>