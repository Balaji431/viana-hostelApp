<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';
require_once "../send_notification.php";

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

try {
    // Debug log incoming data
    file_put_contents('debug_chat.log', date('[Y-m-d H:i:s] ') . "Incoming: " . file_get_contents("php://input") . PHP_EOL, FILE_APPEND);

    $request_id = $data->request_id ?? null;
    $sender_input = $data->sender_id ?? null;
    $message = $data->message ?? null;
    $message_type = $data->message_type ?? 'text';
    $target_dept = strtolower($data->department ?? 'warden'); 

    if (empty($sender_input) || empty($message)) {
        echo json_encode(["success" => false, "message" => "Missing sender_id or message", "debug" => $data]);
        exit;
    }

    // 1. Resolve sender with Universal Translation
    $sender_query = "SELECT id, username, full_name, role FROM users WHERE (CONVERT(username USING utf8mb4) = CONVERT(? USING utf8mb4)) OR id = ? LIMIT 1";
    $stmt = $db->prepare($sender_query);
    $stmt->execute([$sender_input, $sender_input]);
    $sender = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$sender) {
        $p_query = "SELECT parent_id as username, 'Parent' as full_name, 'parent' as role, id FROM parent_users WHERE (CONVERT(parent_id USING utf8mb4) = CONVERT(? USING utf8mb4)) OR id = ? LIMIT 1";
        $p_stmt = $db->prepare($p_query);
        $p_stmt->execute([$sender_input, $sender_input]);
        $sender = $p_stmt->fetch(PDO::FETCH_ASSOC);
        if (!$sender) {
            echo json_encode(["success" => false, "message" => "Sender not found", "debug" => $sender_input]);
            exit;
        }
    }

    $sender_username = $sender['username'];
    $sender_role = $sender['role'];
    $sender_id_int = $sender['id'];

    // Resolve actual student database ID if parent
    $effective_student_id = $sender_id_int;
    if ($sender_role === 'parent') {
        $map_query = $db->prepare("SELECT s.id FROM parent_student_map psm JOIN users s ON psm.student_id = s.username WHERE psm.parent_id = ? LIMIT 1");
        $map_query->execute([$sender_username]);
        $map_row = $map_query->fetch(PDO::FETCH_ASSOC);
        if ($map_row) {
            $effective_student_id = $map_row['id'];
        }
    }

    // 2. Handle missing request_id (Auto-create if needed)
    if (empty($request_id) || $request_id === 'null' || $request_id === '') {
        if ($sender_role === 'student' || $sender_role === 'parent') {
            $lookup = $db->prepare("SELECT request_id FROM request1 WHERE student_id = ? AND (CONVERT(department USING utf8mb4) = CONVERT(? USING utf8mb4)) ORDER BY id DESC LIMIT 1");
            $lookup->execute([$effective_student_id, $target_dept]);
            $row = $lookup->fetch(PDO::FETCH_ASSOC);
            
            if ($row) {
                $request_id = $row['request_id'];
            } else {
                $prefix = strtoupper(substr($target_dept, 0, 3));
                $new_request_id = $prefix . "-" . time() . rand(10, 99);
                $create = $db->prepare("INSERT INTO request1 (request_id, student_id, request_type, department, status, purpose) VALUES (?, ?, 'General Inquiry', ?, 'chat', 'Auto-created via chat')");
                if ($create->execute([$new_request_id, $effective_student_id, $target_dept])) {
                    $request_id = $new_request_id;
                } else {
                    echo json_encode(["success" => false, "message" => "Failed to create request", "error" => $create->errorInfo()]);
                    exit;
                }
            }
        }
    }

    if (empty($request_id)) {
        echo json_encode(["success" => false, "message" => "Request ID is required but could not be found or created."]);
        exit;
    }

    // 3. Find receiver
    $receiver_id = null;
    if ($sender_role === 'student' || $sender_role === 'parent') {
        // Resolve target role pattern
        $role_pattern = '%warden%';
        if (strpos($target_dept, 'security') !== false) $role_pattern = '%security%';
        if (strpos($target_dept, 'maint') !== false) $role_pattern = '%maint%';

        // 1. Direct priority for Warden / Parent-Warden: resolve directly from student's profile & rooms_groups_details
        if ($target_dept === 'warden' || $target_dept === 'parent_warden') {
            $direct_warden_query = "
                SELECT COALESCE(u.username, rgd.warden_bio_id, ms.username, ms.staff_bio_id, p.warden) as resolved_username
                FROM users stu
                LEFT JOIN profile p ON TRIM(stu.username) = TRIM(p.reg_no)
                LEFT JOIN rooms_groups_details rgd ON (
                    TRIM(p.room_allocation) = TRIM(rgd.room_number)
                    OR REPLACE(REPLACE(TRIM(rgd.room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(COALESCE(p.room_allocation, '')), ' ', ''), '-', '')
                )
                LEFT JOIN users u ON (
                    CONVERT(u.username USING utf8mb4) = CONVERT(rgd.warden_bio_id USING utf8mb4)
                    OR LOWER(TRIM(u.full_name)) = LOWER(TRIM(COALESCE(rgd.warden_name, p.warden, '')))
                )
                LEFT JOIN mapping_staff ms ON (
                    (CONVERT(ms.staff_bio_id USING utf8mb4) = CONVERT(rgd.warden_bio_id USING utf8mb4) OR CONVERT(ms.username USING utf8mb4) = CONVERT(rgd.warden_bio_id USING utf8mb4) OR LOWER(TRIM(ms.name)) = LOWER(TRIM(COALESCE(rgd.warden_name, p.warden, ''))))
                    AND LOWER(ms.role) LIKE '%warden%'
                )
                WHERE stu.id = ? AND (rgd.warden_bio_id IS NOT NULL OR p.warden IS NOT NULL)
                LIMIT 1
            ";
            $direct_stmt = $db->prepare($direct_warden_query);
            $direct_stmt->execute([$effective_student_id]);
            $direct_row = $direct_stmt->fetch(PDO::FETCH_ASSOC);
            if ($direct_row && !empty($direct_row['resolved_username'])) {
                $receiver_id = $direct_row['resolved_username'];
            }
        }

        // 2. Second attempt: resolve via rooms_groups_details / profile location matching in mapping_staff
        if (!$receiver_id) {
            $loc_query = "SELECT rgd.hostel_name, rgd.group_name as floor_group, p.room_allocation
                          FROM users u
                          LEFT JOIN profile p ON TRIM(u.username) = TRIM(p.reg_no)
                          LEFT JOIN rooms_groups_details rgd ON TRIM(p.room_allocation) = TRIM(rgd.room_number)
                          WHERE u.id = ? LIMIT 1";
            $loc_stmt = $db->prepare($loc_query);
            $loc_stmt->execute([$effective_student_id]);
            $loc = $loc_stmt->fetch(PDO::FETCH_ASSOC);

            if ($loc && !empty($loc['room_allocation'])) {
                $h_name = $loc['hostel_name'] ?? '';
                $room = trim($loc['room_allocation']);
                $parts = explode('-', $room);
                $f_name = '';
                $w_name = '';

                foreach ($parts as $part) {
                    $p = strtolower(trim($part));
                    if (strpos($p, 'f00') !== false || $p === 'ground') $f_name = 'ground';
                    else if (strpos($p, 'f01') !== false || $p === 'first') $f_name = 'first';
                    else if (strpos($p, 'f02') !== false || $p === 'second') $f_name = 'second';
                    else if (strpos($p, 'f03') !== false || $p === 'third') $f_name = 'third';
                    else if (strpos($p, 'f04') !== false || $p === 'fourth') $f_name = 'fourth';
                    else if (strpos($p, 'f05') !== false || $p === 'fifth') $f_name = 'fifth';
                    else if (strpos($p, 'f06') !== false || $p === 'sixth') $f_name = 'sixth';
                    else if (strpos($p, 'f07') !== false || $p === 'seventh') $f_name = 'seventh';
                    else if (strpos($p, 'f08') !== false || $p === 'eighth') $f_name = 'eighth';
                    else if (strpos($p, 'f09') !== false || $p === 'ninth') $f_name = 'ninth';
                    
                    if (preg_match('/w[a-z0-9]*/i', $p, $w_matches)) {
                        $w_name = strtolower(trim($w_matches[0]));
                    }
                }
                if (empty($f_name) && !empty($loc['floor_group'])) {
                    $fg = strtolower($loc['floor_group']);
                    if (strpos($fg, 'ground') !== false) $f_name = 'ground';
                    else if (strpos($fg, 'first') !== false) $f_name = 'first';
                    else if (strpos($fg, 'second') !== false) $f_name = 'second';
                    else if (strpos($fg, 'third') !== false) $f_name = 'third';
                    else if (strpos($fg, 'fourth') !== false) $f_name = 'fourth';
                    else if (strpos($fg, 'fifth') !== false) $f_name = 'fifth';
                    else if (strpos($fg, 'sixth') !== false) $f_name = 'sixth';
                }

                $warden_query = "SELECT 
                                    COALESCE(u.username, ms.staff_bio_id, ms.username) as resolved_username
                                 FROM mapping_staff ms
                                 LEFT JOIN users u ON (
                                     CONVERT(ms.staff_bio_id USING utf8mb4) = CONVERT(u.username USING utf8mb4)
                                     OR CONVERT(ms.username USING utf8mb4) = CONVERT(u.username USING utf8mb4)
                                 )
                                 WHERE LOWER(ms.role) LIKE :role_pat
                                 AND (
                                     LOWER(TRIM(ms.hostel_name)) = LOWER(TRIM(:h_name))
                                     OR LOWER(TRIM(ms.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(:h_name)), '%')
                                     OR LOWER(TRIM(:h_name)) LIKE CONCAT('%', LOWER(TRIM(ms.hostel_name)), '%')
                                     OR ms.hostel_name IS NULL OR ms.hostel_name = ''
                                 )
                                 AND (
                                     LOWER(TRIM(ms.floor_name)) LIKE CONCAT('%', LOWER(TRIM(:f_name)), '%')
                                     OR LOWER(TRIM(:f_name)) LIKE CONCAT('%', LOWER(TRIM(ms.floor_name)), '%')
                                     OR ms.floor_name IS NULL OR ms.floor_name = ''
                                 )
                                 AND (
                                     LOWER(TRIM(ms.wing_name)) = LOWER(TRIM(:w_name))
                                     OR LOWER(TRIM(ms.wing_name)) LIKE CONCAT('%', LOWER(TRIM(:w_name)), '%')
                                     OR LOWER(TRIM(:w_name)) LIKE CONCAT('%', LOWER(TRIM(ms.wing_name)), '%')
                                     OR ms.wing_name IS NULL OR ms.wing_name = ''
                                     OR LOWER(TRIM(ms.wing_name)) = 'w0'
                                     OR LOWER(TRIM(ms.wing_name)) = 'all'
                                 )
                                 ORDER BY (CASE WHEN LOWER(TRIM(ms.wing_name)) = LOWER(TRIM(:w_name2)) THEN 10 ELSE 0 END) +
                                          (CASE WHEN LOWER(TRIM(ms.floor_name)) LIKE CONCAT('%', LOWER(TRIM(:f_name2)), '%') THEN 5 ELSE 0 END) +
                                          (CASE WHEN LOWER(TRIM(ms.hostel_name)) = LOWER(TRIM(:h_name2)) THEN 1 ELSE 0 END) DESC
                                 LIMIT 1";
                $warden_stmt = $db->prepare($warden_query);
                $warden_stmt->execute([
                    ':role_pat' => $role_pattern,
                    ':h_name'   => $h_name,
                    ':f_name'   => $f_name,
                    ':w_name'   => $w_name,
                    ':w_name2'  => $w_name,
                    ':f_name2'  => $f_name,
                    ':h_name2'  => $h_name,
                ]);
                $receiver = $warden_stmt->fetch(PDO::FETCH_ASSOC);
                if ($receiver) $receiver_id = $receiver['resolved_username'];
            }
        }
        
        if (!$receiver_id) {
            // Fallback: pick any matching staff, resolving users.username
            $stmt = $db->prepare(
                "SELECT COALESCE(u.username, ms.staff_bio_id, ms.username) as resolved_username
                 FROM mapping_staff ms
                 LEFT JOIN users u ON (
                     CONVERT(ms.staff_bio_id USING utf8mb4) = CONVERT(u.username USING utf8mb4)
                     OR CONVERT(ms.username USING utf8mb4) = CONVERT(u.username USING utf8mb4)
                 )
                 WHERE LOWER(ms.role) LIKE ? LIMIT 1"
            );
            $stmt->execute([$role_pattern]);
            $receiver = $stmt->fetch(PDO::FETCH_ASSOC);
            if ($receiver) $receiver_id = $receiver['resolved_username'];
        }
    } else {
        $info_stmt = $db->prepare("SELECT department, student_id FROM request1 WHERE (CONVERT(request_id USING utf8mb4) = CONVERT(? USING utf8mb4))");
        $info_stmt->execute([$request_id]);
        $info = $info_stmt->fetch(PDO::FETCH_ASSOC);
        if ($info) {
            if ($info['department'] === 'parent_warden') {
                $stmt = $db->prepare("SELECT psm.parent_id as username FROM parent_student_map psm JOIN users s ON (CONVERT(psm.student_id USING utf8mb4) = CONVERT(s.username USING utf8mb4) OR CONVERT(psm.student_id USING utf8mb4) = CONVERT(s.id USING utf8mb4)) WHERE s.id = ? OR s.username = ? LIMIT 1");
                $stmt->execute([$info['student_id'], $info['student_id']]);
            } else {
                $stmt = $db->prepare("SELECT username FROM users WHERE (CONVERT(id USING utf8mb4) = CONVERT(? USING utf8mb4) OR CONVERT(username USING utf8mb4) = CONVERT(? USING utf8mb4)) LIMIT 1");
                $stmt->execute([$info['student_id'], $info['student_id']]);
            }
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if ($row) $receiver_id = $row['username'];
        }
    }

    if (!$receiver_id) {
        echo json_encode(["success" => false, "message" => "Receiver ID not found"]);
        exit;
    }

    $t0_http_received = (int)round(microtime(true) * 1000);

    // 4. Insert message
    $insert = $db->prepare("INSERT INTO chat_messages (request_id, sender_id, receiver_id, message, message_type, status) VALUES (?, ?, ?, ?, ?, 'sent')");
    if ($insert->execute([$request_id, $sender_username, $receiver_id, $message, $message_type])) {
        $t1_db_inserted = (int)round(microtime(true) * 1000);
        $message_id = $db->lastInsertId();
        
        // ─────────────────────────────────────────────────────────────────────
        // REDIS EVENT PUBLISH (Sub-second Real-time WebSocket Delivery)
        // ─────────────────────────────────────────────────────────────────────
        $t2_redis_published = $t1_db_inserted;
        try {
            $redis_host = getenv('REDIS_HOST') ?: 'redis';
            $redis_port = (int)(getenv('REDIS_PORT') ?: 6379);
            $redis_sock = @fsockopen($redis_host, $redis_port, $r_err, $r_msg, 0.5);
            if ($redis_sock) {
                stream_set_timeout($redis_sock, 1);
                $t2_redis_published = (int)round(microtime(true) * 1000);
                $event_payload = json_encode([
                    'event' => 'new_message',
                    'request_id' => $request_id,
                    'receiver_id' => $receiver_id,
                    'sender_id' => $sender_username,
                    'message' => $message,
                    'message_type' => $message_type,
                    'message_id' => $message_id,
                    'timestamp' => date('Y-m-d H:i:s'),
                    'timings' => [
                        't0_http_received_ms' => $t0_http_received,
                        't1_db_inserted_ms' => $t1_db_inserted,
                        't2_redis_published_ms' => $t2_redis_published,
                    ]
                ]);
                $cmd = "*3\r\n$7\r\nPUBLISH\r\n$17\r\nvstay_chat_events\r\n$" . strlen($event_payload) . "\r\n" . $event_payload . "\r\n";
                fwrite($redis_sock, $cmd);
                fgets($redis_sock);
                $t2_redis_published = (int)round(microtime(true) * 1000);
                fclose($redis_sock);
            }
        } catch (\Throwable $re) {
            // Non-blocking: Redis publish failure never blocks response or FCM
        }

        file_put_contents('debug_chat.log', sprintf("[%s] [TIMING] send_message.php req_id=%s msg_id=%s | t0_received=%d ms | t1_db_inserted=%d ms (+%d ms) | t2_redis_published=%d ms (+%d ms)\n", date('Y-m-d H:i:s'), $request_id, $message_id, $t0_http_received, $t1_db_inserted, ($t1_db_inserted - $t0_http_received), $t2_redis_published, ($t2_redis_published - $t1_db_inserted)), FILE_APPEND);

        echo json_encode([
            "success" => true,
            "message" => "Message sent",
            "message_id" => $message_id,
            "request_id" => $request_id,
            "receiver_id" => $receiver_id,
            "timings" => [
                "t0_http_received_ms" => $t0_http_received,
                "t1_db_inserted_ms" => $t1_db_inserted,
                "t2_redis_published_ms" => $t2_redis_published,
                "db_duration_ms" => ($t1_db_inserted - $t0_http_received),
                "redis_publish_duration_ms" => ($t2_redis_published - $t1_db_inserted),
            ]
        ]);
        
        // ─────────────────────────────────────────────────────────────────────
        // FCM TOKEN RESOLUTION — Critical fix for Student → Warden flow
        //
        // receiver_id may be a staff_bio_id (e.g. "ENG2345") from mapping_staff.
        // The users table stores the actual login username (e.g. "admin1").
        // We must try BOTH the raw receiver_id AND the mapped users.username
        // to find the correct FCM token.
        // ─────────────────────────────────────────────────────────────────────
        $fcm_token = null;

        // Attempt 1: Direct match in users table (covers warden, student, staff logins)
        $recv_stmt = $db->prepare(
            "SELECT fcm_token FROM users 
             WHERE (CONVERT(username USING utf8mb4) = CONVERT(? USING utf8mb4) 
                 OR CONVERT(id USING utf8mb4) = CONVERT(? USING utf8mb4))
             AND fcm_token IS NOT NULL AND fcm_token != ''
             LIMIT 1"
        );
        $recv_stmt->execute([$receiver_id, $receiver_id]);
        $recv_row = $recv_stmt->fetch(PDO::FETCH_ASSOC);
        if ($recv_row) $fcm_token = $recv_row['fcm_token'];

        // Attempt 2: receiver_id is a staff_bio_id → resolve actual username via mapping_staff → users
        if (!$fcm_token) {
            $bio_stmt = $db->prepare(
                "SELECT u.fcm_token FROM mapping_staff ms
                 JOIN users u ON (
                     CONVERT(ms.username USING utf8mb4) = CONVERT(u.username USING utf8mb4)
                     OR CONVERT(ms.staff_bio_id USING utf8mb4) = CONVERT(u.username USING utf8mb4)
                 )
                 WHERE (CONVERT(ms.staff_bio_id USING utf8mb4) = CONVERT(? USING utf8mb4)
                     OR CONVERT(ms.username USING utf8mb4) = CONVERT(? USING utf8mb4))
                 AND u.fcm_token IS NOT NULL AND u.fcm_token != ''
                 LIMIT 1"
            );
            $bio_stmt->execute([$receiver_id, $receiver_id]);
            $bio_row = $bio_stmt->fetch(PDO::FETCH_ASSOC);
            if ($bio_row) $fcm_token = $bio_row['fcm_token'];
        }

        // Attempt 3: Receiver is a parent user
        if (!$fcm_token) {
            $parent_recv_stmt = $db->prepare(
                "SELECT fcm_token FROM parent_users 
                 WHERE (CONVERT(parent_id USING utf8mb4) = CONVERT(? USING utf8mb4))
                 AND fcm_token IS NOT NULL AND fcm_token != ''
                 LIMIT 1"
            );
            $parent_recv_stmt->execute([$receiver_id]);
            $parent_recv = $parent_recv_stmt->fetch(PDO::FETCH_ASSOC);
            if ($parent_recv) $fcm_token = $parent_recv['fcm_token'];
        }

        // Send FCM if we found a token
        if ($fcm_token) {
            try {
                if ($sender_role === 'student') {
                    $title = $sender['full_name'] . " (" . $sender_username . ")";
                } else {
                    $s_name = !empty($sender['full_name']) ? $sender['full_name'] : $sender_username;
                    $s_role = ($sender_role === 'warden') ? 'Warden' : (($sender_role === 'parent') ? 'Parent' : ucfirst($sender_role));
                    $title = $s_name . " (" . $s_role . ")";
                }
                sendFCM($fcm_token, $title, $message, $request_id, $sender_username, $sender['full_name'], $message, 'chat', $target_dept);
            } catch (Exception $e) {
                file_put_contents('debug_chat.log', date('[Y-m-d H:i:s] ') . "FCM ERROR: " . $e->getMessage() . PHP_EOL, FILE_APPEND);
            }
        } else {
            file_put_contents('debug_chat.log', date('[Y-m-d H:i:s] ') . "FCM SKIPPED: No token found for receiver_id=" . $receiver_id . PHP_EOL, FILE_APPEND);
        }
    } else {
        echo json_encode(["success" => false, "error" => $insert->errorInfo()]);
    }
} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Fatal Error: " . $e->getMessage()]);
}
?>