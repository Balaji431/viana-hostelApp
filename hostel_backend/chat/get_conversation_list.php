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

$target_dept = $_GET['department'] ?? $_GET['channel'] ?? 'warden';
$warden_username = $_GET['warden_username'] ?? $_GET['staff_username'] ?? null;

try {
    // 1. Resolve mapping_role from mapping_staff (use actual stored role, case-insensitive)
    $mapping_role = null;
    if ($warden_username) {
        $role_check = $db->prepare("SELECT role FROM mapping_staff WHERE LOWER(TRIM(username)) = LOWER(TRIM(?)) LIMIT 1");
        $role_check->execute([$warden_username]);
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
        // Normal warden: students in matching hostel/floor/wing
        $sub_stmt = $db->prepare("SELECT u.id FROM users u 
                          JOIN profile p ON (CONVERT(u.username USING utf8mb4) = CONVERT(p.reg_no USING utf8mb4))
                          JOIN hostel_rooms hr ON (CONVERT(p.room_allocation USING utf8mb4) = CONVERT(hr.room_code USING utf8mb4))
                          JOIN mapping_staff ms ON LOWER(TRIM(ms.username)) = LOWER(TRIM(?))
                          WHERE LOWER(TRIM(ms.role)) = LOWER(TRIM(?))
                            AND (
                                LOWER(TRIM(ms.hostel_name)) = LOWER(TRIM(hr.hostel_name))
                                OR LOWER(TRIM(ms.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(hr.hostel_name)), '%')
                                OR LOWER(TRIM(hr.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(ms.hostel_name)), '%')
                            )
                            AND (
                                ms.floor_name IS NULL OR ms.floor_name = ''
                                OR LOWER(TRIM(ms.floor_name)) = LOWER(TRIM(hr.floor))
                                OR (LOWER(TRIM(hr.floor)) IN ('f00', 'ground', 'ground floor') AND LOWER(TRIM(ms.floor_name)) IN ('f00', 'ground', 'ground floor'))
                                OR (LOWER(TRIM(hr.floor)) IN ('f01', '1st floor') AND LOWER(TRIM(ms.floor_name)) IN ('f01', '1st floor'))
                                OR (LOWER(TRIM(hr.floor)) IN ('f02', '2nd floor') AND LOWER(TRIM(ms.floor_name)) IN ('f02', '2nd floor'))
                                OR (LOWER(TRIM(hr.floor)) IN ('f03', '3rd floor') AND LOWER(TRIM(ms.floor_name)) IN ('f03', '3rd floor'))
                                OR (LOWER(TRIM(hr.floor)) IN ('f04', '4th floor') AND LOWER(TRIM(ms.floor_name)) IN ('f04', '4th floor'))
                            )
                            AND (ms.wing_name IS NULL OR ms.wing_name = '' OR LOWER(TRIM(ms.wing_name)) = LOWER(TRIM(hr.wing_code)))");
        $sub_stmt->execute([$warden_username, $mapping_role]);
        $mapped_student_ids = $sub_stmt->fetchAll(PDO::FETCH_COLUMN);
    }

    // 3. Bulk INSERT IGNORE for all students missing a request1 row (single efficient query)
    if (!empty($mapped_student_ids)) {
        $id_list_str = implode(',', array_map('intval', $mapped_student_ids));
        $prefix = strtoupper(substr($target_dept, 0, 3));
        // Find only students who don't have a request1 row yet
        $missing_stmt = $db->query(
            "SELECT id FROM users WHERE id IN ($id_list_str)
             AND id NOT IN (
                 SELECT student_id FROM request1 WHERE LOWER(department) = LOWER('$target_dept')
             )"
        );
        $missing_ids = $missing_stmt->fetchAll(PDO::FETCH_COLUMN);
        if (!empty($missing_ids)) {
            $insert_values = [];
            foreach ($missing_ids as $sid) {
                $req_id = $prefix . "-" . time() . "-" . intval($sid);
                $escaped_req_id = $db->quote($req_id); // already wraps in quotes
                $insert_values[] = "($escaped_req_id, " . intval($sid) . ", 'General Inquiry', " . $db->quote($target_dept) . ", 'chat', 'Auto-created for warden logs')";
            }
            if (!empty($insert_values)) {
                try {
                    $db->exec("INSERT IGNORE INTO request1 (request_id, student_id, request_type, department, status, purpose) VALUES " . implode(',', $insert_values));
                } catch (Exception $e) { /* Silently skip duplicates */ }
            }
        }
    }

    // Build safe IN clause
    $id_list_placeholder = "0";
    if (!empty($mapped_student_ids)) {
        $id_list_placeholder = implode(',', array_map('intval', $mapped_student_ids));
    }

    // 4. Fetch conversation summaries for all mapped students
    $query = "
        SELECT 
            (SELECT r2.request_id FROM request1 r2 
             WHERE r2.student_id = u.id AND LOWER(r2.department) = LOWER(:target_dept) 
             ORDER BY r2.id DESC LIMIT 1) as request_id,
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
             AND CONVERT(cm3.sender_id USING utf8mb4) != CONVERT(cm3.receiver_id USING utf8mb4)
             AND (
                 (:warden_username IS NOT NULL AND :warden_username != '' AND CONVERT(cm3.receiver_id USING utf8mb4) = CONVERT(:warden_username2 USING utf8mb4))
                 OR
                 ((:warden_username3 IS NULL OR :warden_username3 = '') AND CONVERT(cm3.sender_id USING utf8mb4) != CONVERT(u.username USING utf8mb4))
             )
            ) as unread_count
        FROM users u
        WHERE u.id IN ($id_list_placeholder)
        ORDER BY last_time DESC
    ";

    $params = [
        ':target_dept'  => $target_dept,
        ':target_dept2' => $target_dept,
        ':target_dept3' => $target_dept,
        ':target_dept4' => $target_dept,
        ':target_dept5' => $target_dept,
        ':target_dept6' => $target_dept,
        ':warden_username'  => $warden_username,
        ':warden_username2' => $warden_username,
        ':warden_username3' => $warden_username,
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