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
    // 1. Filter students by mapping if warden_username is provided
    $warden_filter = "";
    $params = [
        ':target_dept' => $target_dept,
        ':warden_username' => $warden_username
    ];
    
    if ($warden_username) {
        // Dynamic mapping role: Try to match exactly or fallback to capitalized department name
        $mapping_role = $target_dept;
        if ($target_dept === 'warden') $mapping_role = 'Warden';
        else if ($target_dept === 'security') $mapping_role = 'Security';
        else if ($target_dept === 'maintenance') $mapping_role = 'Maintenance';
        else {
            // For dynamic roles like 'electricity', we check mapping_staff for the actual case used
            $role_check = $db->prepare("SELECT role FROM mapping_staff WHERE username = ? LIMIT 1");
            $role_check->execute([$warden_username]);
            $found_role = $role_check->fetchColumn();
            if ($found_role) {
                $mapping_role = $found_role;
            } else {
                // Capitalize first letter as a safe fallback
                $mapping_role = ucfirst($target_dept);
            }
        }

        $warden_filter = " AND (
            (
                :warden_username = 'warden1'
                AND :target_dept = 'warden'
                AND u.id NOT IN (
                    SELECT u2.id
                    FROM users u2
                    JOIN profile p ON (CONVERT(u2.username USING utf8mb4) = CONVERT(p.reg_no USING utf8mb4))
                    WHERE p.room_allocation IS NOT NULL
                      AND p.room_allocation != ''
                      AND LOWER(TRIM(p.room_allocation)) != 'unallocated'
                )
            )
            OR
            u.id IN (
                SELECT u2.id 
                FROM users u2
                JOIN profile p ON (CONVERT(u2.username USING utf8mb4) = CONVERT(p.reg_no USING utf8mb4))
                JOIN hostel_rooms hr ON (CONVERT(p.room_allocation USING utf8mb4) = CONVERT(hr.room_code USING utf8mb4))
                JOIN mapping_staff ms ON (CONVERT(ms.username USING utf8mb4) = CONVERT(:warden_username USING utf8mb4))
                WHERE (
                    LOWER(TRIM(ms.hostel_name)) = LOWER(TRIM(hr.hostel_name))
                    OR LOWER(TRIM(ms.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(hr.hostel_name)), '%')
                    OR LOWER(TRIM(hr.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(ms.hostel_name)), '%')
                )
                AND (
                    LOWER(TRIM(ms.floor_name)) = LOWER(TRIM(hr.floor))
                    OR (LOWER(TRIM(hr.floor)) IN ('f00', 'ground', 'ground floor') AND LOWER(TRIM(ms.floor_name)) IN ('f00', 'ground', 'ground floor'))
                    OR (LOWER(TRIM(hr.floor)) IN ('f01', '1st floor') AND LOWER(TRIM(ms.floor_name)) IN ('f01', '1st floor'))
                    OR (LOWER(TRIM(hr.floor)) IN ('f02', '2nd floor') AND LOWER(TRIM(ms.floor_name)) IN ('f02', '2nd floor'))
                    OR ms.floor_name IS NULL OR ms.floor_name = ''
                )
                AND (LOWER(TRIM(ms.wing_name)) = LOWER(TRIM(hr.wing_code)) OR ms.wing_name IS NULL OR ms.wing_name = '')
                AND ms.role = :mapping_role
            )
            OR
            EXISTS (
                SELECT 1 FROM chat_messages cm_un 
                JOIN request1 r_un ON (CONVERT(cm_un.request_id USING utf8mb4) = CONVERT(r_un.request_id USING utf8mb4))
                WHERE r_un.student_id = u.id 
                  AND CONVERT(r_un.department USING utf8mb4) = CONVERT(:target_dept USING utf8mb4)
                  AND CONVERT(cm_un.receiver_id USING utf8mb4) = CONVERT(:warden_username USING utf8mb4)
                  AND cm_un.status IN ('sent', 'delivered')
                  AND CONVERT(cm_un.sender_id USING utf8mb4) != CONVERT(cm_un.receiver_id USING utf8mb4)
            )
        )";
        $params[':warden_username'] = $warden_username;
        $params[':mapping_role'] = $mapping_role;
    }
    
    // 2. Bulletproof student-centric query to eliminate duplicate logs
    $query = "
        SELECT 
            (SELECT r2.request_id FROM request1 r2 
             WHERE r2.student_id = u.id AND CONVERT(r2.department USING utf8mb4) = CONVERT(:target_dept USING utf8mb4) 
             ORDER BY r2.id DESC LIMIT 1) as request_id,
            u.id as student_id,
            u.username as student_username,
            CASE 
                WHEN CONVERT(:target_dept USING utf8mb4) = 'parent_warden' THEN CONCAT('Parent of ', u.full_name)
                ELSE u.full_name 
            END as name,
            (SELECT r3.room_number FROM request1 r3 
             WHERE r3.student_id = u.id AND CONVERT(r3.department USING utf8mb4) = CONVERT(:target_dept USING utf8mb4) 
             ORDER BY r3.id DESC LIMIT 1) as room_allocation,
            COALESCE(
                (SELECT cm.message FROM chat_messages cm 
                 JOIN request1 r4 ON (CONVERT(cm.request_id USING utf8mb4) = CONVERT(r4.request_id USING utf8mb4)) 
                 WHERE r4.student_id = u.id AND CONVERT(r4.department USING utf8mb4) = CONVERT(:target_dept USING utf8mb4) 
                 ORDER BY cm.id DESC LIMIT 1), 
                'New Request'
            ) as last_msg,
            COALESCE(
                (SELECT cm.timestamp FROM chat_messages cm 
                 JOIN request1 r5 ON (CONVERT(cm.request_id USING utf8mb4) = CONVERT(r5.request_id USING utf8mb4)) 
                 WHERE r5.student_id = u.id AND CONVERT(r5.department USING utf8mb4) = CONVERT(:target_dept USING utf8mb4) 
                 ORDER BY cm.id DESC LIMIT 1), 
                (SELECT MAX(created_at) FROM request1 r6 
                 WHERE r6.student_id = u.id AND CONVERT(r6.department USING utf8mb4) = CONVERT(:target_dept USING utf8mb4))
            ) as last_time,
            (SELECT COUNT(*) FROM chat_messages cm2 
             JOIN request1 r7 ON (CONVERT(cm2.request_id USING utf8mb4) = CONVERT(r7.request_id USING utf8mb4)) 
             WHERE r7.student_id = u.id AND CONVERT(r7.department USING utf8mb4) = CONVERT(:target_dept USING utf8mb4) 
             AND cm2.status IN ('sent', 'delivered')
             AND cm2.message_type NOT IN ('request_card', 'status')
             AND CONVERT(cm2.sender_id USING utf8mb4) != CONVERT(cm2.receiver_id USING utf8mb4)
             AND (
                 (:warden_username IS NOT NULL AND :warden_username != '' AND CONVERT(cm2.receiver_id USING utf8mb4) = CONVERT(:warden_username USING utf8mb4))
                 OR
                 ((:warden_username IS NULL OR :warden_username = '') AND CONVERT(cm2.sender_id USING utf8mb4) != CONVERT(u.username USING utf8mb4))
             )
            ) as unread_count
        FROM users u
        WHERE u.id IN (
            SELECT student_id FROM request1 r_in 
            WHERE CONVERT(r_in.department USING utf8mb4) = CONVERT(:target_dept USING utf8mb4)
            AND EXISTS (SELECT 1 FROM chat_messages m_in WHERE CONVERT(m_in.request_id USING utf8mb4) = CONVERT(r_in.request_id USING utf8mb4))
        )
        $warden_filter
        ORDER BY last_time DESC
    ";

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