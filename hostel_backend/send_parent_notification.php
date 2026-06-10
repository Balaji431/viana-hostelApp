<?php
/**
 * Send Attendance Notification to Parents
 */

require_once __DIR__ . '/config/database.php';
require_once __DIR__ . '/send_notification.php';

function sendAttendanceNotificationToParents($studentId, $studentName, $status, $date) {
    try {
        $database = new Database();
        $db = $database->getConnection();

        if (!$db) {
            return ["success" => false, "message" => "Database connection failed"];
        }

        // 1. Resolve student details (ID or Username)
        $stmt = $db->prepare("SELECT id, username, full_name FROM users WHERE id = ? OR username = ? LIMIT 1");
        $stmt->execute([$studentId, $studentId]);
        $student = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$student) {
            return ["success" => false, "message" => "Student not found in users table"];
        }
        $student_id_int = (int)$student['id'];
        $student_reg_no = $student['username'];
        $student_name = $student['full_name'];

        // 2. Find mapped parent
        $p_map_stmt = $db->prepare("SELECT parent_id FROM parent_student_map WHERE student_id = ? OR student_id = ? LIMIT 1");
        $p_map_stmt->execute([$student_reg_no, $student_id_int]);
        $p_map = $p_map_stmt->fetch(PDO::FETCH_ASSOC);
        if (!$p_map) {
            return ["success" => false, "message" => "No parent mapped to student registration number: $student_reg_no"];
        }
        $parent_id = $p_map['parent_id'];

        // 3. Find parent user info & FCM token
        $p_stmt = $db->prepare("SELECT id, fcm_token FROM parent_users WHERE parent_id = ? LIMIT 1");
        $p_stmt->execute([$parent_id]);
        $parent = $p_stmt->fetch(PDO::FETCH_ASSOC);
        if (!$parent) {
            return ["success" => false, "message" => "Parent user account not found for parent_id: $parent_id"];
        }
        $parent_fcm_token = $parent['fcm_token'];

        // 4. Resolve child floor warden
        $loc_query = "SELECT hr.hostel_name, hr.floor, hr.wing_code, p.room_allocation
                      FROM users u
                      JOIN profile p ON u.username = p.reg_no
                      JOIN hostel_rooms hr ON p.room_allocation = hr.room_code
                      WHERE u.id = ? LIMIT 1";
        $loc_stmt = $db->prepare($loc_query);
        $loc_stmt->execute([$student_id_int]);
        $loc = $loc_stmt->fetch(PDO::FETCH_ASSOC);
        
        $assigned_warden_username = 'warden1'; // Default chief warden fallback
        if ($loc) {
            $warden_query = "SELECT username FROM mapping_staff 
                            WHERE (LOWER(TRIM(hostel_name)) = LOWER(TRIM(:hostel)) OR hostel_name IS NULL OR hostel_name = '')
                            AND (LOWER(TRIM(floor_name)) = LOWER(TRIM(:floor))
                                 OR (LOWER(TRIM(floor_name)) IN ('ground', 'ground floor') AND LOWER(TRIM(:floor)) IN ('ground', 'ground floor', 'f00'))
                                 OR (LOWER(TRIM(floor_name)) IN ('1st floor') AND LOWER(TRIM(:floor)) IN ('1st floor', 'f01'))
                                 OR (LOWER(TRIM(floor_name)) IN ('2nd floor') AND LOWER(TRIM(:floor)) IN ('2nd floor', 'f02'))
                                 OR floor_name IS NULL OR floor_name = '')
                            AND (LOWER(TRIM(wing_name)) = LOWER(TRIM(:wing)) OR wing_name IS NULL OR wing_name = '')
                            AND role = 'Warden'
                            ORDER BY (CASE WHEN LOWER(TRIM(wing_name)) = LOWER(TRIM(:wing2)) THEN 4 ELSE 0 END) + 
                                     (CASE WHEN LOWER(TRIM(floor_name)) = LOWER(TRIM(:floor2)) THEN 2 ELSE 0 END) +
                                     (CASE WHEN LOWER(TRIM(hostel_name)) = LOWER(TRIM(:hostel2)) THEN 1 ELSE 0 END) DESC
                            LIMIT 1";
            $warden_stmt = $db->prepare($warden_query);
            $warden_stmt->execute([
                ':hostel' => $loc['hostel_name'], 
                ':floor' => $loc['floor'], 
                ':wing' => $loc['wing_code'], 
                ':wing2' => $loc['wing_code'], 
                ':floor2' => $loc['floor'], 
                ':hostel2' => $loc['hostel_name']
            ]);
            $warden = $warden_stmt->fetch(PDO::FETCH_ASSOC);
            if ($warden) {
                $assigned_warden_username = $warden['username'];
            }
        }

        // 5. Look up / Auto-create parent-warden chat request
        $lookup = $db->prepare("SELECT request_id FROM request1 WHERE student_id = ? AND department = 'parent_warden' ORDER BY id DESC LIMIT 1");
        $lookup->execute([$student_id_int]);
        $row = $lookup->fetch(PDO::FETCH_ASSOC);
        
        if ($row) {
            $request_id = $row['request_id'];
        } else {
            $request_id = "PAR-" . time() . rand(10, 99);
            $create = $db->prepare("INSERT INTO request1 (request_id, student_id, request_type, department, status, purpose) VALUES (?, ?, 'General Inquiry', 'parent_warden', 'pending', 'Attendance Alert')");
            $create->execute([$request_id, $student_id_int]);
        }

        // 6. Insert automated chat message from warden to parent as a structured JSON alert
        $absent_data = [
            "title" => "Attendance Alert ⚠️",
            "student_name" => $student_name,
            "status" => "ABSENT",
            "date" => $date,
            "message" => "Your child is missing from attendance today. Please reply with the reason for absence."
        ];
        $absent_json = json_encode($absent_data);
        
        $insert = $db->prepare("INSERT INTO chat_messages (request_id, sender_id, receiver_id, message, message_type, status) VALUES (?, ?, ?, ?, 'attendance_alert', 'sent')");
        $insert->execute([$request_id, $assigned_warden_username, $parent_id, $absent_json]);
 
        // 7. Send push notification to parent
        if (!empty($parent_fcm_token)) {
            $title = "Attendance Alert: $student_name is Absent";
            $body = "Your child is missing from attendance today ($date). Please reply with the reason.";
            $fcm_res = sendFCM($parent_fcm_token, $title, $body, $request_id, $assigned_warden_username, 'Warden', $absent_json, 'attendance_alert');
            return [
                "success" => true, 
                "message" => "Alert and push notification sent to parent",
                "request_id" => $request_id,
                "parent_id" => $parent_id,
                "fcm_response" => json_decode($fcm_res, true)
            ];
        }

        return [
            "success" => true, 
            "message" => "Alert created in chat, but parent FCM token is empty",
            "request_id" => $request_id,
            "parent_id" => $parent_id
        ];

    } catch (Exception $e) {
        return ["success" => false, "message" => "Error sending parent notification: " . $e->getMessage()];
    }
}
?>
