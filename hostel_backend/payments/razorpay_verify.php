<?php
/**
 * razorpay_verify.php
 * Verifies Razorpay payment signature and credits the student's wallet via JSON API.
 *
 * POST JSON: {
 *   "razorpay_payment_id": "...",
 *   "razorpay_order_id": "...",
 *   "razorpay_signature": "...",
 *   "email": "...",
 *   "amount": 500
 * }
 * Response: { "success": true, "message": "...", "balance": 1500.00 }
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

$secrets_file = __DIR__ . '/../config/secrets.php';
$secrets = [];
if (file_exists($secrets_file)) {
    $secrets = include($secrets_file);
}

$RAZORPAY_KEY_SECRET = getenv('RAZORPAY_KEY_SECRET') ?: ($secrets['RAZORPAY_KEY_SECRET'] ?? 'd2gnwZ52h6jypg2fzI04jVxj');

$body = json_decode(file_get_contents('php://input'), true) ?? [];

$paymentId = trim($body['razorpay_payment_id'] ?? '');
$orderId   = trim($body['razorpay_order_id']   ?? '');
$signature = trim($body['razorpay_signature']  ?? '');
$email     = trim($body['email']               ?? '');
$amount    = (float)($body['amount']           ?? 0);

if (empty($paymentId) || empty($orderId) || empty($signature) || empty($email) || $amount <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Missing required payment verification details.']);
    exit();
}

if (empty($RAZORPAY_KEY_SECRET)) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Payment gateway secret not configured on server.']);
    exit();
}

// ─── Verify HMAC SHA256 signature ────────────────────────────────────────────
$expectedSignature = hash_hmac('sha256', $orderId . '|' . $paymentId, $RAZORPAY_KEY_SECRET);

if (!hash_equals($expectedSignature, $signature)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Payment signature verification failed.']);
    exit();
}

// ─── Verified! Credit the wallet ─────────────────────────────────────────────
try {
    $db = (new Database())->getConnection();

    // Create tables if not exist (safety net)
    $db->exec("
        CREATE TABLE IF NOT EXISTS user_wallets (
            id INT AUTO_INCREMENT PRIMARY KEY,
            email VARCHAR(191) NOT NULL UNIQUE,
            balance DECIMAL(12,2) NOT NULL DEFAULT 0.00,
            currency VARCHAR(10) DEFAULT 'INR',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_email (email)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

        CREATE TABLE IF NOT EXISTS wallet_transactions (
            id INT AUTO_INCREMENT PRIMARY KEY,
            wallet_id INT NOT NULL,
            email VARCHAR(191) NOT NULL,
            txn_type VARCHAR(16) NOT NULL,
            amount DECIMAL(12,2) NOT NULL,
            balance_after DECIMAL(12,2) NOT NULL,
            reference_id VARCHAR(191) NULL,
            description VARCHAR(255) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_wallet_id (wallet_id),
            INDEX idx_email (email)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");

    $db->beginTransaction();

    // Get or create wallet (supporting roll number & email variants)
    $variants = [$email, strtolower($email)];
    if (strpos($email, '@') === false) {
        $variants[] = strtolower($email) . '.simats@saveetha.com';
        $variants[] = strtolower($email) . '@saveetha.com';
    } else {
        $prefix = explode('@', $email)[0];
        $variants[] = $prefix;
        $prefixClean = explode('.', $prefix)[0];
        $variants[] = $prefixClean;
        $variants[] = $prefixClean . '.simats@saveetha.com';
    }
    $variants = array_values(array_unique(array_filter($variants)));
    $placeholders = implode(',', array_fill(0, count($variants), '?'));

    $stmt = $db->prepare("SELECT id, email, balance FROM user_wallets WHERE LOWER(email) IN ($placeholders) ORDER BY balance DESC, id DESC LIMIT 1 FOR UPDATE");
    $stmt->execute(array_map('strtolower', $variants));
    $wallet = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$wallet) {
        $primaryEmail = (strpos($email, '@') === false) ? $email . '.simats@saveetha.com' : $email;
        $db->prepare("INSERT INTO user_wallets (email, balance) VALUES (?, ?)")->execute([$primaryEmail, $amount]);
        $walletId    = $db->lastInsertId();
        $newBalance  = $amount;
    } else {
        $walletId   = $wallet['id'];
        $newBalance = (float)$wallet['balance'] + $amount;
        $db->prepare("UPDATE user_wallets SET balance = ? WHERE id = ?")->execute([$newBalance, $walletId]);
    }

    // Record transaction (idempotent)
    $dupCheck = $db->prepare("SELECT id FROM wallet_transactions WHERE reference_id = ? LIMIT 1");
    $dupCheck->execute([$paymentId]);
    if (!$dupCheck->fetchColumn()) {
        $db->prepare("
            INSERT INTO wallet_transactions (wallet_id, email, txn_type, amount, balance_after, reference_id, description)
            VALUES (?, ?, 'credit', ?, ?, ?, ?)
        ")->execute([
            $walletId,
            $email,
            $amount,
            $newBalance,
            $paymentId,
            'Wallet Top-up via Razorpay (Order: ' . $orderId . ')',
        ]);
    }

    $db->commit();

    echo json_encode([
        'success' => true,
        'message' => 'Wallet credited successfully.',
        'payment_id' => $paymentId,
        'order_id' => $orderId,
        'amount' => $amount,
        'balance' => $newBalance,
    ]);
} catch (Exception $e) {
    if (isset($db) && $db->inTransaction()) {
        $db->rollBack();
    }
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $e->getMessage()]);
}
