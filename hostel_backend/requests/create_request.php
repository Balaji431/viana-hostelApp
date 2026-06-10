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

            // Determine Receiver (Warden by default for all requests for now, or based on dept)
            $receiver_username = 'warden1'; // Default fallback
            $warden_query = $db->prepare("SELECT username FROM users WHERE role = 'warden' LIMIT 1");
            $warden_query->execute();
            $warden_row = $warden_query->fetch(PDO::FETCH_ASSOC);
            if ($warden_row) {
                $receiver_username = $warden_row['username'];
            }

            $skip_message = isset($data['skip_message']) && ($data['skip_message'] == 1 || $data['skip_message'] == true || $data['skip_message'] === '1');

            if (!$skip_message) {
                $card = json_encode([
                    "type" => "request_card",
                    "request_id" => $request_id,
                    "title" => $data['request_type'],
                    "status" => "pending"
                ]);

                $chat_query = "INSERT INTO chat_messages (request_id, sender_id, receiver_id, message, message_type, status) VALUES (?, ?, ?, ?, 'request_card', 'sent')";
                $chat_stmt = $db->prepare($chat_query);
                $chat_stmt->execute([$request_id, $stu_username, $receiver_username, $card]);
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
                $deptName = ($dept === 'parent_warden') ? 'Warden' : ucfirst($dept);
                $title = "New " . $deptName . " Request: " . $stu_name . " (" . $stu_username . ")";
                $body = "Room: " . $data['room_number'] . " | Type: " . $data['request_type'] . " | Purpose: " . $data['purpose'];
                
                log_debug("NOTIFYING: " . $warden['full_name'] . " (Token: " . substr($warden['fcm_token'], 0, 10) . "...)");
                
                // Use the sendFCM function
                sendFCM($warden['fcm_token'], $title, $body, $request_id, $stu_username, $stu_name, $body, 'new_request');
            } else {
                log_debug("NO TOKEN FOUND for notification");
            }
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
