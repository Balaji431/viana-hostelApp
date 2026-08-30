<?php
/**
 * renew_hostel_wallet.php
 * Dynamic endpoint for student hostel booking renewal via wallet payment.
 * Verifies live wallet balance before confirming, deducts the fee, and extends stay by 1 year.
 */

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept, X-User-Id, X-User-Username, X-User-Role');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/activity_logger.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo json_encode(["success" => false, "message" => "Database connection failed."]);
    exit();
}

$input = json_decode(file_get_contents('php://input'), true) ?? [];

$regNo     = trim($input['reg_no'] ?? '');
$email     = trim($input['email'] ?? '');
$studentId = (int)($input['student_id'] ?? 0);
$amount    = (float)($input['amount'] ?? 120000.0);

if (empty($regNo) && empty($email) && empty($studentId)) {
    echo json_encode(["success" => false, "message" => "Student identification is required."]);
    exit();
}

try {
    // 1. Fetch Profile
    $stmtProf = $db->prepare("
        SELECT p.*, u.id as user_db_id, u.full_name as user_full_name 
        FROM profile p
        LEFT JOIN users u ON (u.username = p.reg_no OR u.id = p.user_id)
        WHERE p.reg_no = ? OR p.user_id = ? OR LOWER(p.email) = LOWER(?)
        LIMIT 1
    ");
    $stmtProf->execute([$regNo, $studentId, $email]);
    $profile = $stmtProf->fetch(PDO::FETCH_ASSOC);

    if (!$profile) {
        echo json_encode(["success" => false, "message" => "Student profile not found."]);
        exit();
    }

    $effectiveRegNo = $profile['reg_no'] ?: $regNo;
    $effectiveEmail = $profile['email'] ?: ($email ?: "$effectiveRegNo.simats@saveetha.com");
    $effectiveUserId = (int)($profile['user_db_id'] ?: $studentId);

    // 2. Fetch Wallet with variant matching
    $variants = [$effectiveEmail, strtolower($effectiveEmail), $effectiveRegNo, strtolower($effectiveRegNo)];
    if (strpos($effectiveEmail, '@') !== false) {
        $variants[] = explode('@', $effectiveEmail)[0];
        $variants[] = explode('.', explode('@', $effectiveEmail)[0])[0] . '.simats@saveetha.com';
    } else {
        $variants[] = strtolower($effectiveEmail) . '.simats@saveetha.com';
    }
    $variants = array_values(array_unique(array_filter($variants)));
    $placeholders = implode(',', array_fill(0, count($variants), '?'));

    $db->beginTransaction();

    $stmtWallet = $db->prepare("SELECT * FROM user_wallets WHERE LOWER(email) IN ($placeholders) ORDER BY balance DESC, id DESC LIMIT 1 FOR UPDATE");
    $stmtWallet->execute(array_map('strtolower', $variants));
    $wallet = $stmtWallet->fetch(PDO::FETCH_ASSOC);

    $currentBalance = $wallet ? (float)$wallet['balance'] : 0.00;

    // 3. Dynamic Balance Check
    if ($currentBalance < $amount) {
        $db->rollBack();
        $shortage = $amount - $currentBalance;
        echo json_encode([
            "success" => false,
            "insufficient_balance" => true,
            "current_balance" => $currentBalance,
            "required_amount" => $amount,
            "shortage" => $shortage,
            "message" => "Insufficient wallet balance. Please top up your wallet and try again."
        ]);
        exit();
    }

    // 4. Sufficient balance — Deduct and Extend
    $newBalance = $currentBalance - $amount;
    $walletId = (int)$wallet['id'];

    $db->prepare("UPDATE user_wallets SET balance = ? WHERE id = ?")->execute([$newBalance, $walletId]);

    // Record wallet transaction
    $refId = 'REN' . time() . rand(100, 999);
    $db->prepare("
        INSERT INTO wallet_transactions (wallet_id, email, txn_type, amount, balance_after, reference_id, description)
        VALUES (?, ?, 'debit', ?, ?, ?, ?)
    ")->execute([
        $walletId,
        $wallet['email'],
        $amount,
        $newBalance,
        $refId,
        "Hostel Booking Renewal (1 Year Extended) - Ref: $refId"
    ]);

    // Update profile dates: Extend renewal_date by 1 year
    $curRenewalDate = $profile['renewal_date'] ?: date('Y-m-d');
    $newRenewalDate = date('Y-m-d', strtotime($curRenewalDate . ' +1 year'));
    
    // If renewal date was in the past, set it to 1 year from today
    if (strtotime($newRenewalDate) < time()) {
        $newRenewalDate = date('Y-m-d', strtotime('+1 year'));
    }

    $daysRemaining = max(0, (int)round((strtotime($newRenewalDate) - time()) / 86400));

    $stmtUpProf = $db->prepare("
        UPDATE profile 
        SET 
            renewal_date = ?, 
            remaining_days = ?
        WHERE reg_no = ? OR id = ?
    ");
    $stmtUpProf->execute([$newRenewalDate, $daysRemaining, $effectiveRegNo, $profile['id']]);

    // Record in payment table for accounting history
    $campus = $profile['institution'] ?? "Thandalam Campus";
    $name = $profile['full_name'] ?? "Student";
    $phone = $profile['personal_phone'] ?? "N/A";
    $gatewayRes = json_encode(['gateway' => 'Wallet', 'status' => 'SUCCESS', 'ref_id' => $refId]);
    $ip = getClientIp();

    $stmtPay = $db->prepare("
        INSERT INTO payment (campus, registerNumber, name, email, contactNumber, payment_type, payment_id, amount, status, admin_status, gateway_response, user_id, ip_address, paid_at)
        VALUES (?, ?, ?, ?, ?, 'Hostel Renewal', ?, ?, 'Success', 'Confirmed', ?, ?, ?, NOW())
    ");
    $stmtPay->execute([$campus, $effectiveRegNo, $name, $effectiveEmail, $phone, $refId, $amount, $gatewayRes, $effectiveUserId, $ip]);

    // Record in renewal_requests so Warden management portal tracks the renewal immediately
    $roomNum = $profile['room_allocation'] ?: 'T-32 F02- W0-R16';
    $stmtRenReq = $db->prepare("
        INSERT INTO renewal_requests 
        (student_id, student_name, student_reg_no, room_number, reason, status, requested_at, processed_by, processed_by_name, processed_at, remarks)
        VALUES (?, ?, ?, ?, '1 Year Hostel Renewal (Wallet Payment)', 'approved', NOW(), 1, 'Institutional Wallet', NOW(), ?)
    ");
    $stmtRenReq->execute([
        $effectiveUserId,
        $name,
        $effectiveRegNo,
        $roomNum,
        "Auto-approved: Paid ₹" . number_format($amount, 2) . " via Wallet (Ref: $refId)"
    ]);

    $db->commit();

    echo json_encode([
        "success" => true,
        "message" => "Hostel renewal successful! Stay extended by 1 year.",
        "new_balance" => $newBalance,
        "renewal_date" => $newRenewalDate,
        "remaining_days" => $daysRemaining,
        "ref_id" => $refId,
    ]);

} catch (Exception $e) {
    if (isset($db) && $db->inTransaction()) {
        $db->rollBack();
    }
    http_response_code(500);
    echo json_encode(["success" => false, "message" => "Renewal failed: " . $e->getMessage()]);
}
