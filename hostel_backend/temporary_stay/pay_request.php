<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../send_notification.php';
require_once __DIR__ . '/../utils/auth_helper.php';

$authUser = requireAuth();

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

$input = json_decode(file_get_contents('php://input'), true);
$request_id = trim($input['request_id'] ?? '');
$renew_days = intval($input['renew_days'] ?? 0);
$renew_amount = floatval($input['renew_amount'] ?? 0);

if (empty($request_id)) {
    echo json_encode(["success" => false, "message" => "Request ID is required"]);
    exit();
}

try {
    $stmtCheck = $db->prepare("SELECT * FROM temporary_stay_requests WHERE request_id = ? LIMIT 1");
    $stmtCheck->execute([$request_id]);
    $req = $stmtCheck->fetch(PDO::FETCH_ASSOC);

    if (!$req) {
        echo json_encode(["success" => false, "message" => "Request not found"]);
        exit();
    }

    $userRole = strtolower($authUser['role'] ?? '');
    if ($userRole === 'student') {
        $callerEmail = strtolower($authUser['email'] ?? '');
        $callerUser = strtolower($authUser['username'] ?? '');
        $reqEmail = strtolower($req['email'] ?? '');
        $reqDoc = strtolower($req['doc_number'] ?? '');
        if ($callerEmail !== $reqEmail && $callerUser !== $reqDoc && (empty($callerUser) || strpos($reqEmail, $callerUser) === false)) {
            http_response_code(403);
            echo json_encode(["success" => false, "message" => "Forbidden: You are not authorized to pay for this temporary stay request."]);
            exit();
        }
    }

    if ($req['status'] === 'rejected') {
        echo json_encode(["success" => false, "message" => "Cannot pay for a rejected application."]);
        exit();
    }

    if ($req['payment_status'] === 'paid') {
        echo json_encode([
            "success" => true,
            "message" => "Payment already completed for this request.",
            "status" => "allocated",
            "payment_status" => "paid",
            "payment_txn_id" => $req['payment_txn_id']
        ]);
        exit();
    }

    $txn_id = 'TXN-' . strtoupper(substr(md5(uniqid(mt_rand(), true)), 0, 10));

    // Update payment_status = paid and status = allocated
    if ($renew_days > 0) {
        $stmtUpd = $db->prepare("UPDATE temporary_stay_requests SET to_date = DATE_ADD(to_date, INTERVAL ? DAY), amount = amount + ?, duration_value = duration_value + ?, payment_status = 'paid', payment_txn_id = ?, status = 'allocated' WHERE request_id = ?");
        $stmtUpd->execute([$renew_days, $renew_amount, $renew_days, $txn_id, $request_id]);
    } else {
        $stmtUpd = $db->prepare("UPDATE temporary_stay_requests SET payment_status = 'paid', payment_txn_id = ?, status = 'allocated' WHERE request_id = ?");
        $stmtUpd->execute([$txn_id, $request_id]);
    }

    // Decrement available room count in rooms_groups_details & room_master (only if not a renewal)
    if ($renew_days <= 0) {
        $rCode = !empty($req['room_code']) ? $req['room_code'] : $req['room_no'];
        if (!empty($rCode)) {
            try {
                $db->prepare("UPDATE rooms_groups_details SET available_beds = GREATEST(0, available_beds - 1), occupied_beds = occupied_beds + 1 WHERE room_number = ?")->execute([$rCode]);
                $db->prepare("UPDATE room_master SET available_beds = GREATEST(0, available_beds - 1), occupied_beds = occupied_beds + 1 WHERE room_code = ? OR room_no = ?")->execute([$rCode, $rCode]);
            } catch (Exception $eRoom) {}
        }
    }

    // Send FCM push notification to user device
    try {
        $userStmt = $db->prepare("SELECT fcm_token FROM users WHERE LOWER(email) = LOWER(?) AND fcm_token IS NOT NULL AND fcm_token != '' LIMIT 1");
        $userStmt->execute([$req['email']]);
        $user = $userStmt->fetch(PDO::FETCH_ASSOC);

        if ($user && !empty($user['fcm_token'])) {
            $roomCodeDisplay = !empty($req['room_code']) ? $req['room_code'] : $req['room_no'];
            $formattedAmount = number_format((float)($req['amount'] ?? 0), 2);
            $notifTitle = "VSTAY - Room Allocated! 🔑";
            $notifBody = "Payment of ₹" . $formattedAmount . " confirmed! Room " . $roomCodeDisplay . " (" . $req['hostel_name'] . ") is allocated for your stay from " . $req['from_date'] . " to " . $req['to_date'] . ".";

            sendFCM($user['fcm_token'], $notifTitle, $notifBody, $request_id, 'system', 'VSTAY Payment', $notifBody, 'temporary_stay', 'student');
        }
    } catch (Exception $eNotif) {}

    // Outbound real-time sync to VStudy Short Stay ERP API
    $vstudySync = null;
    try {
        require_once __DIR__ . '/../utils/vstudy_sync_helper.php';
        $rollNumber = explode('@', $req['email'])[0];
        if (!is_numeric($rollNumber) || empty($rollNumber)) {
            $uStmt = $db->prepare("SELECT username FROM users WHERE LOWER(email) = LOWER(?) LIMIT 1");
            $uStmt->execute([$req['email']]);
            $uRow = $uStmt->fetch(PDO::FETCH_ASSOC);
            if (!empty($uRow['username'])) {
                $rollNumber = $uRow['username'];
            } else {
                $rollNumber = !empty($req['doc_number']) ? $req['doc_number'] : $req['request_id'];
            }
        }
        $rCode = !empty($req['room_code']) ? $req['room_code'] : $req['room_no'];
        $vstudySync = syncShortStayToVStudy(
            $rollNumber,
            $rCode,
            $req['hostel_name'] ?? '',
            $req['from_date'] ?? date('Y-m-d'),
            $req['to_date'] ?? date('Y-m-d', strtotime('+1 day')),
            generateUuidV4()
        );
    } catch (Exception $eSync) {
        error_log("VStudy short stay sync error: " . $eSync->getMessage());
    }

    echo json_encode([
        "success" => true,
        "message" => "Payment successful! Room allocated successfully.",
        "request_id" => $request_id,
        "status" => "allocated",
        "payment_status" => "paid",
        "payment_txn_id" => $txn_id
    ]);
} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Payment failed: " . $e->getMessage()]);
}
?>
