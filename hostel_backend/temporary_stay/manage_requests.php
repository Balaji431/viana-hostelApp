<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
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

// Ensure table columns exist
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN warden_name VARCHAR(191) NULL AFTER fcm_token;");
} catch (Exception $eColW1) {}
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN warden_id VARCHAR(100) NULL AFTER warden_name;");
} catch (Exception $eColW2) {}
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN warden_bio_id VARCHAR(50) NULL AFTER warden_id;");
} catch (Exception $eColW3) {}
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN hold_expires_at DATETIME NULL AFTER warden_bio_id;");
} catch (Exception $eColW4) {}
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN hold_status VARCHAR(32) DEFAULT 'none' AFTER hold_expires_at;");
} catch (Exception $eColW5) {}

// Auto-expire approved requests that exceeded the 24-hour hold window without payment
try {
    $db->exec("UPDATE temporary_stay_requests 
               SET status = 'timed_out', hold_status = 'expired' 
               WHERE status = 'approved' AND payment_status != 'paid' AND hold_expires_at IS NOT NULL AND hold_expires_at < NOW()");
} catch (Exception $eExp) {}

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $status = isset($_GET['status']) ? trim($_GET['status']) : 'pending';
    $warden_id = isset($_GET['warden_id']) ? trim($_GET['warden_id']) : '';
    $warden_name = isset($_GET['warden_name']) ? trim($_GET['warden_name']) : '';

    try {
        $params = [];
        $where = [];

        if ($status !== 'all') {
            $where[] = "status = ?";
            $params[] = $status;
        }

        if (!empty($warden_id) || !empty($warden_name)) {
            $wClause = [];
            if (!empty($warden_id)) {
                $wClause[] = "warden_id = ?";
                $params[] = $warden_id;
                $wClause[] = "warden_bio_id = ?";
                $params[] = $warden_id;
                $wClause[] = "room_no IN (SELECT room_number FROM rooms_groups_details WHERE warden_user_id = ? OR warden_bio_id = ?)";
                $params[] = $warden_id;
                $params[] = $warden_id;
            }
            if (!empty($warden_name)) {
                $wClause[] = "LOWER(warden_name) = LOWER(?)";
                $params[] = $warden_name;
                $wClause[] = "room_no IN (SELECT room_number FROM rooms_groups_details WHERE LOWER(warden_name) = LOWER(?))";
                $params[] = $warden_name;
            }
            $where[] = "(" . implode(" OR ", $wClause) . ")";
        }

        $sql = "SELECT *, 
                       GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), hold_expires_at)) as hold_remaining_seconds
                FROM temporary_stay_requests";
        if (!empty($where)) {
            $sql .= " WHERE " . implode(" AND ", $where);
        }
        $sql .= " ORDER BY id DESC";

        $stmt = $db->prepare($sql);
        $stmt->execute($params);
        $requests = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Compute counts for warden / admin badge
        $countSql = "SELECT 
                        COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending_count,
                        COUNT(CASE WHEN status = 'approved' AND payment_status != 'paid' THEN 1 END) as approved_count,
                        COUNT(CASE WHEN status = 'allocated' OR payment_status = 'paid' THEN 1 END) as allocated_count,
                        COUNT(CASE WHEN status = 'rejected' OR status = 'timed_out' THEN 1 END) as rejected_count,
                        COUNT(*) as total_count
                     FROM temporary_stay_requests";
        $countParams = [];
        if (!empty($warden_id) || !empty($warden_name)) {
            $wClause = [];
            if (!empty($warden_id)) {
                $wClause[] = "warden_id = ?";
                $countParams[] = $warden_id;
                $wClause[] = "warden_bio_id = ?";
                $countParams[] = $warden_id;
                $wClause[] = "room_no IN (SELECT room_number FROM rooms_groups_details WHERE warden_user_id = ? OR warden_bio_id = ?)";
                $countParams[] = $warden_id;
                $countParams[] = $warden_id;
            }
            if (!empty($warden_name)) {
                $wClause[] = "LOWER(warden_name) = LOWER(?)";
                $countParams[] = $warden_name;
                $wClause[] = "room_no IN (SELECT room_number FROM rooms_groups_details WHERE LOWER(warden_name) = LOWER(?))";
                $countParams[] = $warden_name;
            }
            $countSql .= " WHERE (" . implode(" OR ", $wClause) . ")";
        }
        $stmtCounts = $db->prepare($countSql);
        $stmtCounts->execute($countParams);
        $counts = $stmtCounts->fetch(PDO::FETCH_ASSOC) ?: [
            "pending_count" => 0,
            "approved_count" => 0,
            "allocated_count" => 0,
            "rejected_count" => 0,
            "total_count" => 0
        ];

        echo json_encode([
            "success" => true,
            "requests" => $requests,
            "counts" => $counts
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

        if ($status === 'approved') {
            // Set 24-hour hold expiration
            $stmtUpd = $db->prepare("UPDATE temporary_stay_requests 
                                     SET status = 'approved', 
                                         hold_status = 'held', 
                                         hold_expires_at = DATE_ADD(NOW(), INTERVAL 24 HOUR), 
                                         admin_notes = ? 
                                     WHERE request_id = ?");
            $stmtUpd->execute([$admin_notes, $request_id]);
        } else if ($status === 'rejected') {
            $stmtUpd = $db->prepare("UPDATE temporary_stay_requests 
                                     SET status = 'rejected', 
                                         hold_status = 'released', 
                                         admin_notes = ? 
                                     WHERE request_id = ?");
            $stmtUpd->execute([$admin_notes, $request_id]);
        } else {
            $stmtUpd = $db->prepare("UPDATE temporary_stay_requests SET status = ?, admin_notes = ? WHERE request_id = ?");
            $stmtUpd->execute([$status, $admin_notes, $request_id]);
        }

        // Check if applicant has an FCM token in users table via email
        $userStmt = $db->prepare("SELECT fcm_token FROM users WHERE LOWER(email) = LOWER(?) AND fcm_token IS NOT NULL AND fcm_token != '' LIMIT 1");
        $userStmt->execute([$req['email']]);
        $user = $userStmt->fetch(PDO::FETCH_ASSOC);

        if ($user && !empty($user['fcm_token'])) {
            if ($status === 'rejected') {
                $notifTitle = "VSTAY - Short Stay Request Rejected ❌";
                $reasonText = !empty($admin_notes) ? $admin_notes : "Administrative decision";
                $notifBody = "Your short stay application has been rejected: " . $reasonText;
            } else if ($status === 'approved') {
                $notifTitle = "VSTAY - Short Stay Approved! 24h to Pay ⏳";
                $roomCodeDisplay = !empty($req['room_code']) ? $req['room_code'] : $req['room_no'];
                $formattedAmount = number_format($amount, 2);
                $notifBody = "Your room $roomCodeDisplay ($req[hostel_name]) is approved & held for 24 hours. Please pay ₹$formattedAmount via Wallet before the hold expires to confirm.";
            } else {
                $notifTitle = "VSTAY - Temporary Stay Status Update";
                $notifBody = "Your temporary stay request status has been updated to $status.";
            }

            sendFCM($user['fcm_token'], $notifTitle, $notifBody, $request_id, 'warden', 'Hostel Warden', $notifBody, 'temporary_stay', 'student');
        }

        echo json_encode([
            "success" => true,
            "message" => "Request $request_id updated to $status",
            "request_id" => $request_id,
            "status" => $status,
            "hold_status" => ($status === 'approved' ? 'held' : 'none'),
            "rejection_reason" => $admin_notes
        ]);
    } catch (Exception $e) {
        echo json_encode(["success" => false, "message" => $e->getMessage()]);
    }
    exit();
}
?>
