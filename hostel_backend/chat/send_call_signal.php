<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}
require_once '../config/database.php';

// Safe include for notifications - don't crash if vendor is missing
if (file_exists('../send_notification.php')) {
    include_once '../send_notification.php';
}

$raw_input = file_get_contents("php://input");
$data = json_decode($raw_input, true);

if (!$data) {
    echo json_encode(["success" => false, "message" => "No data provided"]);
    exit;
}

$target_id = $data['target_id'] ?? null;
$type = $data['type'] ?? 'call_offer'; // call_offer, call_hangup, offer, hangup
$channel_name = $data['channel_name'] ?? '';
$caller_name = $data['caller_name'] ?? 'Hostel Management';

// Normalize type for consistency
if ($type == 'offer') $type = 'call_offer';
if ($type == 'hangup') $type = 'call_hangup';

if (!$target_id) {
    echo json_encode(['success' => false, 'message' => 'Missing target_id']);
    exit;
}

$database = new Database();
$db = $database->getConnection();

// 1. Get the target user's username for notification
$query = "SELECT username FROM users WHERE id = :id";
$stmt = $db->prepare($query);
$stmt->bindParam(':id', $target_id);
$stmt->execute();
$user = $stmt->fetch(PDO::FETCH_ASSOC);

if ($user) {
    $target_username = $user['username'];
    
    // 2. Prepare Notification Data
    $notif_data = [
        'type' => $type == 'call_offer' ? 'call' : 'call_hangup',
        'channel_name' => $channel_name,
        'caller_name' => $caller_name,
        'title' => $type == 'call_offer' ? 'Incoming Call' : 'Call Ended',
        'body' => $type == 'call_offer' ? "$caller_name is calling you..." : "Call with $caller_name has ended"
    ];

    // 🔥 DB SIGNALING: Write to active_calls table
    if ($type == 'call_offer') {
        // Clear old calls for this target first
        $clear = $db->prepare("DELETE FROM active_calls WHERE target_id = :tid");
        $clear->bindParam(':tid', $target_id);
        $clear->execute();

        $ins = $db->prepare("INSERT INTO active_calls (caller_id, caller_name, target_id, channel_name, status) VALUES (:cid, :cname, :tid, :ch, 'ringing')");
        // We don't have caller_id in the payload, but we can extract it if needed. 
        // For now using 0 or a placeholder.
        $cid = 0; 
        $ins->bindParam(':cid', $cid);
        $ins->bindParam(':cname', $caller_name);
        $ins->bindParam(':tid', $target_id);
        $ins->bindParam(':ch', $channel_name);
        $ins->execute();
    } else if ($type == 'call_hangup' || $type == 'hangup') {
        $upd = $db->prepare("UPDATE active_calls SET status = 'ended' WHERE target_id = :tid OR caller_name = :cname");
        $upd->bindParam(':tid', $target_id);
        $upd->bindParam(':cname', $caller_name);
        $upd->execute();
    }

    // 3. Send via FCM with safety checks (Keep as secondary fallback)
    $fcm_sent = false;
    if (function_exists('sendFCM')) {
        try {
            // Get token for sendFCM
            $token_query = "SELECT fcm_token FROM users WHERE id = :id";
            $token_stmt = $db->prepare($token_query);
            $token_stmt->bindParam(':id', $target_id);
            $token_stmt->execute();
            $token_user = $token_stmt->fetch(PDO::FETCH_ASSOC);
            $fcm_token = $token_user['fcm_token'] ?? null;

            if ($fcm_token) {
                sendFCM(
                    $fcm_token, 
                    $notif_data['title'], 
                    $notif_data['body'], 
                    $target_id, 
                    'system', 
                    $caller_name, 
                    $channel_name, 
                    'call'
                );
                $fcm_sent = true;
            }
        } catch (Exception $e) {
            error_log("FCM Error in call signal: " . $e->getMessage());
        }
    }
    
    echo json_encode([
        'success' => true, 
        'message' => 'Signal sent',
        'fcm_sent' => $fcm_sent
    ]);
} else {
    echo json_encode(['success' => false, 'message' => 'Target user not found']);
}
?>
