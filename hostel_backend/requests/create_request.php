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

// 🔥 DEBUG LOG SETUP
ini_set("display_errors", 0);
error_reporting(E_ALL);
function log_debug($msg) {
    file_put_contents(__DIR__ . '/create_request_debug.log', date('Y-m-d H:i:s') . " - $msg\n", FILE_APPEND);
}

require_once '../send_notification.php';
require_once '../utils/activity_logger.php';

$database = new Database();
$db = $database->getConnection();

$raw = file_get_contents("php://input");
log_debug("RAW INPUT: $raw");

$data = json_decode($raw, true);
if (json_last_error() !== JSON_ERROR_NONE) {
    log_debug("JSON PARSE ERROR: " . json_last_error_msg());
}

if(!$data){
    echo json_encode([
        "success"=>false,
        "message"=>"No JSON received",
        "raw"=> ($raw === "" ? "empty" : $raw)
    ]);
    exit;
}

// 1. Basic validation
if(
    isset($data['student_id']) &&
    isset($data['request_type']) &&
    isset($data['purpose']) &&
    isset($data['room_number'])
){

    // 2. Generate request ID based on department
    $dept = $data['department'] ?? 'warden';
    $prefix = "WRD-";
    if($dept == 'security') $prefix = "SEC-";
    if($dept == 'maintenance') $prefix = "MNT-";
    if($dept == 'parent_warden') $prefix = "PRW-";
    
    $request_id = $prefix . time();

    // 3. Database Insert (Using 'request1' table)
    $query = "INSERT INTO request1
    (request_id, student_id, request_type, departure_date, return_date, destination, purpose, room_number, status, department) 
    VALUES 
    (:request_id, :student_id, :request_type, :departure_date, :return_date, :destination, :purpose, :room_number, 'pending', :department)";

    $stmt = $db->prepare($query);

    // Make optional fields null if not provided
    $departure_date = $data['departure_date'] ?? null;
    $return_date = $data['return_date'] ?? null;
    $destination = $data['destination'] ?? null;

    $stmt->bindParam(":request_id", $request_id);
    $stmt->bindParam(":student_id", $data['student_id']);
    $stmt->bindParam(":request_type", $data['request_type']);
    $stmt->bindParam(":departure_date", $departure_date);
    $stmt->bindParam(":return_date", $return_date);
    $stmt->bindParam(":destination", $destination);
    $stmt->bindParam(":purpose", $data['purpose']);
    $stmt->bindParam(":room_number", $data['room_number']);
    $stmt->bindParam(":department", $dept);

    try {
        if($stmt->execute()){
            log_debug("INSERT SUCCESS: $request_id");
            
            // 4. ALSO Insert Chat Request Card (Required for UI)
            // Get student username for sender_id consistency
            $stu_stmt = $db->prepare("SELECT username, full_name FROM users WHERE id = ?");
            $stu_stmt->execute([$data['student_id']]);
            $stu = $stu_stmt->fetch(PDO::FETCH_ASSOC);
            $stu_username = ($stu) ? $stu['username'] : $data['student_id'];
            $stu_name = ($stu) ? $stu['full_name'] : "Student";

            // Log Audit state transition
            logAudit(
                $data['student_id'],
                $stu_username,
                'student',
                'REQUEST_CREATE',
                'Requests',
                null,
                [
                    'request_id' => $request_id,
                    'request_type' => $data['request_type'],
                    'room_number' => $data['room_number'],
                    'purpose' => $data['purpose'],
                    'department' => $dept,
                    'status' => 'pending'
                ]
            );

            // Determine Receiver (Floorwise warden, hostel warden, or default main warden)
            $receiver_username = 'warden1'; // Default fallback
            
            // 1. Check if the student has a room allocation
            $loc_query = "SELECT hr.hostel_name, hr.floor, hr.wing_code
                          FROM users u
                          JOIN profile p ON (CONVERT(u.username USING utf8mb4) = CONVERT(p.reg_no USING utf8mb4))
                          JOIN hostel_rooms hr ON (CONVERT(p.room_allocation USING utf8mb4) = CONVERT(hr.room_code USING utf8mb4))
                          WHERE u.id = ? LIMIT 1";
            $loc_stmt = $db->prepare($loc_query);
            $loc_stmt->execute([$data['student_id']]);
            $loc = $loc_stmt->fetch(PDO::FETCH_ASSOC);

            $resolved_hostel = null;
            $resolved_floor = null;
            $resolved_wing = null;

            if ($loc && !empty($loc['hostel_name'])) {
                $resolved_hostel = $loc['hostel_name'];
                $resolved_floor = $loc['floor'];
                $resolved_wing = $loc['wing_code'];
            } else {
                // 2. Check if student is a new paid student in vstudy_payments
                $pay_query = "SELECT hostel_name FROM vstudy_payments WHERE TRIM(roll_number) = TRIM(?) LIMIT 1";
                $pay_stmt = $db->prepare($pay_query);
                $pay_stmt->execute([$stu_username]);
                $pay_row = $pay_stmt->fetch(PDO::FETCH_ASSOC);
                if ($pay_row && !empty($pay_row['hostel_name'])) {
                    $resolved_hostel = $pay_row['hostel_name'];
                }
            }

            if ($resolved_hostel) {
                // Find matching warden in mapping_staff
                $warden_query = "SELECT username FROM mapping_staff 
                                 WHERE (LOWER(TRIM(hostel_name)) = LOWER(TRIM(:hostel)) OR hostel_name IS NULL OR hostel_name = '')
                                 AND (:floor IS NULL OR floor_name IS NULL OR floor_name = '' OR LOWER(TRIM(floor_name)) = LOWER(TRIM(:floor))
                                      OR (floor_name = 'Ground' AND :floor2 = 'F00')
                                      OR (floor_name = '1st Floor' AND :floor2 = 'F01')
                                      OR (floor_name = '2nd Floor' AND :floor2 = 'F02'))
                                 AND (:wing IS NULL OR wing_name IS NULL OR wing_name = '' OR LOWER(TRIM(wing_name)) = LOWER(TRIM(:wing)))
                                 AND role = 'Warden'
                                 ORDER BY (CASE WHEN wing_name IS NOT NULL AND wing_name != '' THEN 4 ELSE 0 END) + 
                                          (CASE WHEN floor_name IS NOT NULL AND floor_name != '' THEN 2 ELSE 0 END) +
                                          (CASE WHEN hostel_name IS NOT NULL AND hostel_name != '' THEN 1 ELSE 0 END) DESC
                                 LIMIT 1";
                $warden_stmt = $db->prepare($warden_query);
                $warden_stmt->execute([
                    ':hostel' => $resolved_hostel,
                    ':floor' => $resolved_floor,
                    ':floor2' => $resolved_floor,
                    ':wing' => $resolved_wing
                ]);
                $warden_row = $warden_stmt->fetch(PDO::FETCH_ASSOC);
                if ($warden_row) {
                    $receiver_username = $warden_row['username'];
                }
            }

            $skip_message = isset($data['skip_message']) && ($data['skip_message'] == 1 || $data['skip_message'] == true || $data['skip_message'] === '1');

            if (!$skip_message) {
                $cardText = !empty($data['purpose']) ? $data['purpose'] : "Created a new " . $data['request_type'] . " request.";

                $chat_query = "INSERT INTO chat_messages (request_id, sender_id, receiver_id, message, message_type, status) VALUES (?, ?, ?, ?, 'request_card', 'sent')";
                $chat_stmt = $db->prepare($chat_query);
                $chat_stmt->execute([$request_id, $stu_username, $receiver_username, $cardText]);
            }

            // 🔥 Logic fix for Blue Ticks: Mark previous messages in this conversation as seen
            $update_query = "UPDATE chat_messages 
                            SET status = 'seen' 
                            WHERE request_id = ? 
                            AND sender_id != ? 
                            AND status != 'seen'";
            $update_stmt = $db->prepare($update_query);
            $update_stmt->execute([$request_id, $receiver_username]);

        // 🔥 NOTIFICATION Logic
        try {
            // Get the receiver token for notification
            $warden_stmt = $db->prepare("SELECT full_name, fcm_token FROM users WHERE username = ?");
            $warden_stmt->execute([$receiver_username]);
            $warden = $warden_stmt->fetch(PDO::FETCH_ASSOC);

            if ($warden && !empty($warden['fcm_token'])) {
                // Format: Student Name (Reg No) -> e.g. BIRAJ CHAUDHARY (192514071)
                $title = $stu_name . " (" . $stu_username . ")";
                $body = "Room: " . $data['room_number'] . " | Type: " . $data['request_type'] . " | Purpose: " . $data['purpose'];
                
                log_debug("NOTIFYING: " . $warden['full_name'] . " (Token: " . substr($warden['fcm_token'], 0, 10) . "...)");
                
                // Use the sendFCM function
                sendFCM($warden['fcm_token'], $title, $body, $request_id, $stu_username, $stu_name, $body, 'new_request');
            } else {
                log_debug("NO TOKEN FOUND for notification");
            }

            // Notify Student's Mapped Parent in Parent-Warden Chat & Send FCM Push Notification
            try {
                $p_stmt = $db->prepare("SELECT pu.fcm_token, pu.parent_id FROM parent_student_map psm JOIN parent_users pu ON psm.parent_id = pu.parent_id WHERE psm.student_id = ? OR psm.student_id = ? LIMIT 1");
                $p_stmt->execute([$stu_username, $data['student_id'] ?? 0]);
                $parent_res = $p_stmt->fetch(PDO::FETCH_ASSOC);

                if ($parent_res) {
                    $parent_id = $parent_res['parent_id'];
                    $parent_token = $parent_res['fcm_token'];

                    // Find or create parent_warden chat thread
                    $pw_lookup = $db->prepare("SELECT request_id FROM request1 WHERE student_id = ? AND department = 'parent_warden' ORDER BY id DESC LIMIT 1");
                    $pw_lookup->execute([$student_id_int]);
                    $pw_row = $pw_lookup->fetch(PDO::FETCH_ASSOC);

                    if ($pw_row) {
                        $parent_req_id = $pw_row['request_id'];
                    } else {
                        $parent_req_id = "PAR-" . time() . rand(10, 99);
                        $pw_create = $db->prepare("INSERT INTO request1 (request_id, student_id, request_type, department, status, purpose) VALUES (?, ?, 'General Inquiry', 'parent_warden', 'pending', 'Category Request Alert')");
                        $pw_create->execute([$parent_req_id, $student_id_int]);
                    }

                    // Insert chat message into parent_warden chat channel
                    $p_msg = "📢 [CATEGORY REQUEST SUBMITTED]\nChild: " . $stu_name . " (" . $stu_username . ")\nType: " . $data['request_type'] . "\nPurpose: " . $data['purpose'];
                    $p_insert = $db->prepare("INSERT INTO chat_messages (request_id, sender_id, receiver_id, message, message_type, status) VALUES (?, ?, ?, ?, 'status', 'sent')");
                    $p_insert->execute([$parent_req_id, $stu_username, $parent_id, $p_msg]);

                    // Send FCM push notification to parent if token exists
                    if (!empty($parent_token)) {
                        // Title format: Student Name (Reg No) -> e.g. BIRAJ CHAUDHARY (192514071)
                        $p_title = $stu_name . " (" . $stu_username . ")";
                        $p_body = "Category Request: Your child " . $stu_name . " (" . $stu_username . ") submitted a " . $data['request_type'] . " request. Purpose: " . $data['purpose'];
                        sendFCM($parent_token, $p_title, $p_body, $parent_req_id, $stu_username, $stu_name, $p_body, 'category_request', 'parent_warden');
                    }
                }
            } catch (Exception $e) {}
        } catch (Exception $e) {
            log_debug("NOTIFICATION FAILED: " . $e->getMessage());
        }

            echo json_encode([
                "success" => true,
                "request_id" => $request_id
            ]);

        }else{
            log_debug("INSERT FAILED (stmt execute false): " . json_encode($stmt->errorInfo()));
            echo json_encode([
                "success" => false,
                "message" => "Insert failed: " . $stmt->errorInfo()[2]
            ]);
        }
    } catch (PDOException $e) {
        log_debug("CAUGHT EXCEPTION: " . $e->getMessage());
        echo json_encode([
            "success" => false, 
            "message" => "Database exception: " . $e->getMessage()
        ]);
    }

}else{
    // List missing fields for easy debugging
    $missing = [];
    if(!isset($data['student_id'])) $missing[] = 'student_id';
    if(!isset($data['request_type'])) $missing[] = 'request_type';
    if(!isset($data['purpose'])) $missing[] = 'purpose';
    if(!isset($data['room_number'])) $missing[] = 'room_number';

    echo json_encode([
        "success" => false,
        "message" => "Incomplete data sent.",
        "missing" => $missing,
        "received" => $data
    ]);
}
?>
