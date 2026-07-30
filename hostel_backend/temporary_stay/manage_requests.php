<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../send_notification.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $status = isset($_GET['status']) ? trim($_GET['status']) : 'pending';
    try {
        if ($status === 'all') {
            $stmt = $db->prepare("SELECT * FROM temporary_stay_requests ORDER BY id DESC");
            $stmt->execute();
        } else {
            $stmt = $db->prepare("SELECT * FROM temporary_stay_requests WHERE status = ? ORDER BY id DESC");
            $stmt->execute([$status]);
        }
        $requests = $stmt->fetchAll(PDO::FETCH_ASSOC);

        echo json_encode([
            "success" => true,
            "requests" => $requests
        ]);
    } catch (Exception $e) {
        echo json_encode(["success" => false, "message" => $e->getMessage()]);
    }
    exit();
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = json_decode(file_get_contents('php://input'), true);
    $request_id = trim($input['request_id'] ?? '');
    $status = trim($input['status'] ?? '');
    $admin_notes = trim($input['admin_notes'] ?? ($input['rejection_reason'] ?? ''));

    if (empty($request_id) || !in_array($status, ['approved', 'rejected', 'pending'])) {
        echo json_encode(["success" => false, "message" => "Invalid parameters"]);
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

        // Calculate amount if missing
        $amount = (float)($req['amount'] ?? 0);
        if ($amount <= 0 && $status === 'approved') {
            $annualFee = 75000;
            try {
                $stmtFee = $db->prepare("SELECT total_fee, hostel_fee FROM hostel_renew_fee WHERE LOWER(room_type) = LOWER(?) LIMIT 1");
                $stmtFee->execute([trim($req['room_type'])]);
                $rowFee = $stmtFee->fetch(PDO::FETCH_ASSOC);
                if ($rowFee && !empty($rowFee['total_fee']) && (float)$rowFee['total_fee'] > 0) {
                    $annualFee = (float)$rowFee['total_fee'];
                }
            } catch (Exception $eFee) {}
            $dailyRate = $annualFee / 365.0;
            $durVal = max(1, (int)($req['duration_value'] ?? 1));
            $durDays = (strtolower($req['duration_type'] ?? 'days') === 'months') ? ($durVal * 30) : $durVal;
            $amount = round($dailyRate * $durDays, 2);

            $db->prepare("UPDATE temporary_stay_requests SET amount = ?, annual_fee = ? WHERE request_id = ?")->execute([$amount, $annualFee, $request_id]);
        }

        $stmtUpd = $db->prepare("UPDATE temporary_stay_requests SET status = ?, admin_notes = ? WHERE request_id = ?");
        $stmtUpd->execute([$status, $admin_notes, $request_id]);

        // Check if applicant has an FCM token in users table via email
        $userStmt = $db->prepare("SELECT fcm_token FROM users WHERE LOWER(email) = LOWER(?) AND fcm_token IS NOT NULL AND fcm_token != '' LIMIT 1");
        $userStmt->execute([$req['email']]);
        $user = $userStmt->fetch(PDO::FETCH_ASSOC);

        if ($user && !empty($user['fcm_token'])) {
            if ($status === 'rejected') {
                $notifTitle = "VSTAY - Temporary Stay Request Rejected ❌";
                $reasonText = !empty($admin_notes) ? $admin_notes : "Administrative decision";
                $notifBody = "Your temporary stay application has been rejected due to: " . $reasonText;
            } else {
                $notifTitle = "VSTAY - Temporary Stay Request Approved! 🎉";
                $roomCodeDisplay = !empty($req['room_code']) ? $req['room_code'] : $req['room_no'];
                $formattedAmount = number_format($amount, 2);
                $notifBody = "Your temporary stay request for room " . $roomCodeDisplay . " (" . $req['hostel_name'] . ") is APPROVED! Total Amount: ₹" . $formattedAmount . ". Please complete your payment to finalize room allocation.";
            }

            sendFCM($user['fcm_token'], $notifTitle, $notifBody, $request_id, 'admin', 'VSTAY Admin', $notifBody, 'temporary_stay', 'student');
        }

        echo json_encode([
            "success" => true,
            "message" => "Request $request_id updated to $status",
            "request_id" => $request_id,
            "status" => $status,
            "rejection_reason" => $admin_notes
        ]);
    } catch (Exception $e) {
        echo json_encode(["success" => false, "message" => $e->getMessage()]);
    }
    exit();
}
?>
