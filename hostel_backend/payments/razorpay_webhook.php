<?php
/**
 * razorpay_webhook.php
 * Server-to-server webhook endpoint for Razorpay payment events.
 * Directly receives payment.captured and order.paid notifications from Razorpay servers.
 * Guarantees wallet crediting even if user browser / mobile app closes.
 */

// Return 200 immediately for pre-flight OPTIONS
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

$RAZORPAY_KEY_SECRET     = getenv('RAZORPAY_KEY_SECRET')     ?: ($secrets['RAZORPAY_KEY_SECRET']     ?? '');
$RAZORPAY_WEBHOOK_SECRET = getenv('RAZORPAY_WEBHOOK_SECRET') ?: ($secrets['RAZORPAY_WEBHOOK_SECRET'] ?? '');

// 1. Read raw request payload and signature header
$payload = file_get_contents('php://input');
$signature = $_SERVER['HTTP_X_RAZORPAY_SIGNATURE'] ?? '';

header('Content-Type: application/json; charset=UTF-8');

if (empty($payload)) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'Empty webhook payload.']);
    exit();
}

// 2. Verify Razorpay webhook signature (FAIL CLOSED: Reject if secret is missing or signature invalid)
$webhookSecret = !empty($RAZORPAY_WEBHOOK_SECRET) ? $RAZORPAY_WEBHOOK_SECRET : $RAZORPAY_KEY_SECRET;

if (empty($webhookSecret)) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Payment gateway webhook secret is not configured on the server.']);
    exit();
}

if (empty($signature)) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'Missing HTTP_X_RAZORPAY_SIGNATURE header.']);
    exit();
}

$expectedSignature = hash_hmac('sha256', $payload, $webhookSecret);
$validSignature = hash_equals($expectedSignature, $signature);

if (!$validSignature && !empty($RAZORPAY_KEY_SECRET)) {
    $fallbackSignature = hash_hmac('sha256', $payload, $RAZORPAY_KEY_SECRET);
    $validSignature = hash_equals($fallbackSignature, $signature);
}

if (!$validSignature) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'Invalid webhook signature.']);
    exit();
}

// 3. Parse JSON data
$data = json_decode($payload, true);
if (!$data || !isset($data['event'])) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'Invalid JSON event.']);
    exit();
}

$event = $data['event'];

try {
    $db = (new Database())->getConnection();

    // Ensure audit log table exists
    $db->exec("
        CREATE TABLE IF NOT EXISTS payment_webhook_logs (
            id INT AUTO_INCREMENT PRIMARY KEY,
            event VARCHAR(64) NOT NULL,
            payment_id VARCHAR(64) NULL,
            order_id VARCHAR(64) NULL,
            amount DECIMAL(12,2) NULL,
            email VARCHAR(191) NULL,
            status VARCHAR(32) NOT NULL,
            message TEXT NULL,
            raw_payload LONGTEXT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_payment_id (payment_id),
            INDEX idx_order_id (order_id),
            INDEX idx_email (email)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
            INDEX idx_email (email),
            INDEX idx_ref_id (reference_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");

    if ($event === 'payment.captured' || $event === 'order.paid') {
        $payment = $data['payload']['payment']['entity'] ?? null;
        if (!$payment && isset($data['payload']['order']['entity'])) {
            // For order.paid without direct payment entity attached
            $orderEntity = $data['payload']['order']['entity'];
            $orderId = $orderEntity['id'] ?? '';
            // Acknowledge order.paid; payment.captured handles individual ledger crediting
            http_response_code(200);
            echo json_encode(['status' => 'acknowledged', 'event' => $event, 'order_id' => $orderId]);
            exit();
        }

        if (!$payment) {
            http_response_code(200);
            echo json_encode(['status' => 'skipped', 'message' => 'No payment entity found.']);
            exit();
        }

        $paymentId = $payment['id'] ?? '';
        $orderId   = $payment['order_id'] ?? '';
        $amount    = (float)(($payment['amount'] ?? 0) / 100);
        $email     = trim($payment['notes']['email'] ?? ($payment['email'] ?? ''));
        $contact   = $payment['contact'] ?? '';

        if (empty($paymentId) || $amount <= 0) {
            http_response_code(200);
            echo json_encode(['status' => 'skipped', 'message' => 'Invalid payment ID or amount.']);
            exit();
        }

        // 4. Strict Idempotency Check: Don't double credit if already processed
        $dupCheck = $db->prepare("SELECT id FROM wallet_transactions WHERE reference_id = ? LIMIT 1");
        $dupCheck->execute([$paymentId]);
        if ($dupCheck->fetchColumn()) {
            // Already credited
            $logStmt = $db->prepare("INSERT INTO payment_webhook_logs (event, payment_id, order_id, amount, email, status, message) VALUES (?, ?, ?, ?, ?, 'already_credited', 'Transaction reference already recorded in wallet_transactions.')");
            $logStmt->execute([$event, $paymentId, $orderId, $amount, $email]);

            http_response_code(200);
            echo json_encode([
                'status' => 'already_credited',
                'payment_id' => $paymentId,
                'message' => 'Payment has already been credited to wallet.'
            ]);
            exit();
        }

        // 5. Resolve email and student wallet
        if (empty($email)) {
            // Attempt to find student from order notes or users table
            $stmtU = $db->prepare("SELECT email FROM users WHERE phone_number LIKE ? OR contact_no LIKE ? LIMIT 1");
            $stmtU->execute(["%$contact%", "%$contact%"]);
            $foundEmail = $stmtU->fetchColumn();
            if ($foundEmail) {
                $email = $foundEmail;
            }
        }

        if (empty($email)) {
            $logStmt = $db->prepare("INSERT INTO payment_webhook_logs (event, payment_id, order_id, amount, email, status, message, raw_payload) VALUES (?, ?, ?, ?, ?, 'failed_no_email', 'Cannot determine student email for wallet credit.', ?)");
            $logStmt->execute([$event, $paymentId, $orderId, $amount, $email, $payload]);

            http_response_code(200);
            echo json_encode(['status' => 'warning', 'message' => 'No email associated with payment. Logged for manual review.']);
            exit();
        }

        // Resolve email variants (support user_wallets matching)
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

        $db->beginTransaction();

        $stmt = $db->prepare("SELECT id, email, balance FROM user_wallets WHERE LOWER(email) IN ($placeholders) ORDER BY balance DESC, id DESC LIMIT 1 FOR UPDATE");
        $stmt->execute(array_map('strtolower', $variants));
        $wallet = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$wallet) {
            $primaryEmail = (strpos($email, '@') === false) ? $email . '.simats@saveetha.com' : $email;
            $db->prepare("INSERT INTO user_wallets (email, balance) VALUES (?, ?)")->execute([$primaryEmail, $amount]);
            $walletId   = $db->lastInsertId();
            $newBalance = $amount;
        } else {
            $walletId   = $wallet['id'];
            $newBalance = (float)$wallet['balance'] + $amount;
            $db->prepare("UPDATE user_wallets SET balance = ? WHERE id = ?")->execute([$newBalance, $walletId]);
        }

        // Insert into wallet_transactions
        $orderDesc = !empty($orderId) ? " (Order: $orderId)" : "";
        $desc = "Wallet Top-up via Razorpay Webhook$orderDesc";

        $db->prepare("
            INSERT INTO wallet_transactions (wallet_id, email, txn_type, amount, balance_after, reference_id, description)
            VALUES (?, ?, 'credit', ?, ?, ?, ?)
        ")->execute([
            $walletId,
            $email,
            $amount,
            $newBalance,
            $paymentId,
            $desc,
        ]);

        // Insert audit log
        $logStmt = $db->prepare("INSERT INTO payment_webhook_logs (event, payment_id, order_id, amount, email, status, message) VALUES (?, ?, ?, ?, ?, 'credited', ?)");
        $logStmt->execute([$event, $paymentId, $orderId, $amount, $email, "Successfully credited ₹$amount. New balance: ₹$newBalance"]);

        $db->commit();

        http_response_code(200);
        echo json_encode([
            'status' => 'success',
            'credited' => true,
            'payment_id' => $paymentId,
            'amount' => $amount,
            'email' => $email,
            'new_balance' => $newBalance
        ]);
        exit();
    }

    // Default for any other event
    $logStmt = $db->prepare("INSERT INTO payment_webhook_logs (event, status, message) VALUES (?, 'ignored', 'Unhandled event type.')");
    $logStmt->execute([$event]);

    http_response_code(200);
    echo json_encode(['status' => 'ignored', 'event' => $event]);
    exit();

} catch (Throwable $e) {
    if (isset($db) && $db->inTransaction()) {
        $db->rollBack();
    }
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'Internal server error processing webhook: ' . $e->getMessage()
    ]);
    exit();
}
