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
                $create = $db->prepare("INSERT INTO request1 (request_id, student_id, request_type, department, status, purpose) VALUES (?, ?, 'General Inquiry', ?, 'pending', 'Auto-created via chat')");
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
        $loc_query = "SELECT hr.hostel_name, hr.floor, hr.wing_code
                      FROM users u
                      JOIN profile p ON (CONVERT(u.username USING utf8mb4) = CONVERT(p.reg_no USING utf8mb4))
                      JOIN hostel_rooms hr ON (CONVERT(p.room_allocation USING utf8mb4) = CONVERT(hr.room_code USING utf8mb4))
                      WHERE u.id = ? LIMIT 1";
        $loc_stmt = $db->prepare($loc_query);
        $loc_stmt->execute([$effective_student_id]);
        $loc = $loc_stmt->fetch(PDO::FETCH_ASSOC);
        
        // Resolve the role for mapping_staff query
        $mapping_role = 'Warden';
        if ($target_dept === 'security') $mapping_role = 'Security';
        if ($target_dept === 'maintenance') $mapping_role = 'Maintenance';

        if ($loc) {
            $warden_query = "SELECT username FROM mapping_staff 
                            WHERE (CONVERT(hostel_name USING utf8mb4) = CONVERT(:hostel USING utf8mb4) OR hostel_name IS NULL OR hostel_name = '')
                            AND (CONVERT(floor_name USING utf8mb4) = CONVERT(:floor USING utf8mb4)
                                 OR (floor_name = 'Ground' AND :floor = 'F00')
                                 OR (floor_name = '1st Floor' AND :floor = 'F01')
                                 OR (floor_name = '2nd Floor' AND :floor = 'F02')
                                 OR floor_name IS NULL OR floor_name = '')
                            AND (CONVERT(wing_name USING utf8mb4) = CONVERT(:wing USING utf8mb4) OR wing_name IS NULL OR wing_name = '')
                            AND role = :role
                            ORDER BY (CASE WHEN CONVERT(wing_name USING utf8mb4) = CONVERT(:wing2 USING utf8mb4) THEN 4 ELSE 0 END) + 
                                     (CASE WHEN CONVERT(floor_name USING utf8mb4) = CONVERT(:floor2 USING utf8mb4) THEN 2 ELSE 0 END) +
                                     (CASE WHEN CONVERT(hostel_name USING utf8mb4) = CONVERT(:hostel2 USING utf8mb4) THEN 1 ELSE 0 END) DESC
                            LIMIT 1";
            $warden_stmt = $db->prepare($warden_query);
            $warden_stmt->execute([
                ':hostel' => $loc['hostel_name'], 
                ':floor' => $loc['floor'], 
                ':wing' => $loc['wing_code'], 
                ':role' => $mapping_role,
                ':wing2' => $loc['wing_code'], 
                ':floor2' => $loc['floor'], 
                ':hostel2' => $loc['hostel_name']
            ]);
            $receiver = $warden_stmt->fetch(PDO::FETCH_ASSOC);
            if ($receiver) $receiver_id = $receiver['username'];
        }
        
        if (!$receiver_id) {
            $stmt = $db->prepare("SELECT username FROM users WHERE (CONVERT(role USING utf8mb4) = CONVERT(? USING utf8mb4)) LIMIT 1");
            $stmt->execute([$mapping_role]);
            $receiver = $stmt->fetch(PDO::FETCH_ASSOC);
            if ($receiver) $receiver_id = $receiver['username'];
        }
    } else {
        $info_stmt = $db->prepare("SELECT department, student_id FROM request1 WHERE (CONVERT(request_id USING utf8mb4) = CONVERT(? USING utf8mb4))");
        $info_stmt->execute([$request_id]);
        $info = $info_stmt->fetch(PDO::FETCH_ASSOC);
        if ($info) {
            if ($info['department'] === 'parent_warden') {
                $stmt = $db->prepare("SELECT psm.parent_id as username FROM parent_student_map psm JOIN users s ON (CONVERT(psm.student_id USING utf8mb4) = CONVERT(s.username USING utf8mb4)) WHERE s.id = ? LIMIT 1");
                $stmt->execute([$info['student_id']]);
            } else {
                $stmt = $db->prepare("SELECT username FROM users WHERE id = ? LIMIT 1");
                $stmt->execute([$info['student_id']]);
            }
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if ($row) $receiver_id = $row['username'];
        }
    }

    if (!$receiver_id) {
        echo json_encode(["success" => false, "message" => "Receiver ID not found"]);
        exit;
    }

    // 4. Insert message
    $insert = $db->prepare("INSERT INTO chat_messages (request_id, sender_id, receiver_id, message, message_type, status) VALUES (?, ?, ?, ?, ?, 'sent')");
    if ($insert->execute([$request_id, $sender_username, $receiver_id, $message, $message_type])) {
        $message_id = $db->lastInsertId();
        echo json_encode(["success" => true, "message" => "Message sent", "message_id" => $message_id, "request_id" => $request_id, "receiver_id" => $receiver_id]);
        
        $receiver_details_stmt = $db->prepare("SELECT fcm_token FROM users WHERE (CONVERT(username USING utf8mb4) = CONVERT(? USING utf8mb4)) LIMIT 1");
        $receiver_details_stmt->execute([$receiver_id]);
        $recv = $receiver_details_stmt->fetch(PDO::FETCH_ASSOC);
        if ($recv && !empty($recv['fcm_token'])) {
            try {
                if ($sender_role === 'student') {
                    $deptName = ($target_dept === 'parent_warden') ? 'Warden' : ucfirst($target_dept);
                    $title = "New " . $deptName . " Message: " . $sender['full_name'] . " (" . $sender_username . ")";
                } else {
                    $title = "New Message from " . ($sender_role === 'warden' ? 'Warden' : ($sender_role === 'parent' ? 'Parent' : ucfirst($sender_role)));
                }
                sendFCM($recv['fcm_token'], $title, $message, $request_id, $sender_username, $sender['full_name'], $message, 'chat', $target_dept);
            } catch (Exception $e) {}
        } else {
            // Also try to notify via parent_users table if receiver is a parent
            $parent_recv_stmt = $db->prepare("SELECT fcm_token FROM parent_users WHERE (CONVERT(parent_id USING utf8mb4) = CONVERT(? USING utf8mb4)) LIMIT 1");
            $parent_recv_stmt->execute([$receiver_id]);
            $parent_recv = $parent_recv_stmt->fetch(PDO::FETCH_ASSOC);
            if ($parent_recv && !empty($parent_recv['fcm_token'])) {
                try {
                    $title = "New Message from " . ucfirst($sender_role);
                    sendFCM($parent_recv['fcm_token'], $title, $message, $request_id, $sender_username, $sender['full_name'], $message, 'chat', 'parent_warden');
                } catch (Exception $e) {}
            }
        }
    } else {
        echo json_encode(["success" => false, "error" => $insert->errorInfo()]);
    }
} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Fatal Error: " . $e->getMessage()]);
}
?>