<?php
/**
 * razorpay_callback.php
 * Receives POST from razorpay_checkout.php after payment, verifies the
 * Razorpay HMAC signature, credits the wallet, and renders a result page.
 *
 * POST fields: razorpay_payment_id, razorpay_order_id, razorpay_signature, email, amount
 */

require_once __DIR__ . '/../config/database.php';

$secrets_file = __DIR__ . '/../config/secrets.php';
$secrets = [];
if (file_exists($secrets_file)) {
    $secrets = include($secrets_file);
}

$RAZORPAY_KEY_SECRET = getenv('RAZORPAY_KEY_SECRET') ?: ($secrets['RAZORPAY_KEY_SECRET'] ?? 'd2gnwZ52h6jypg2fzI04jVxj');

// ─── Grab POST fields ───────────────────────────────────────────────────────
$paymentId = trim($_POST['razorpay_payment_id'] ?? '');
$orderId   = trim($_POST['razorpay_order_id']   ?? '');
$signature = trim($_POST['razorpay_signature']  ?? '');
$email     = trim($_POST['email']               ?? '');
$amount    = (float)($_POST['amount']           ?? 0);

// ─── Helper: render result page ──────────────────────────────────────────────
function renderPage(bool $success, string $title, string $message, float $amount = 0, string $txnId = ''): void {
    $icon    = $success ? '✅' : '❌';
    $color   = $success ? '#16a34a' : '#dc2626';
    $bgColor = $success ? '#f0fdf4' : '#fef2f2';
    $btnText = 'Return to VStay App';
    $amtStr  = $amount > 0 ? '₹' . number_format($amount, 2) : '';
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  <title>VStay – Payment <?= $success ? 'Success' : 'Failed' ?></title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      min-height: 100vh;
      background: linear-gradient(135deg, #0f1d35 0%, #1b3a6b 60%, #0f1d35 100%);
      display: flex; align-items: center; justify-content: center;
      font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    }
    .card {
      background: rgba(255,255,255,0.96);
      border-radius: 24px;
      padding: 44px 36px 36px;
      max-width: 380px; width: 92%;
      text-align: center;
      box-shadow: 0 24px 64px rgba(0,0,0,0.4);
    }
    .icon { font-size: 56px; margin-bottom: 16px; display: block; }
    h1 { font-size: 22px; font-weight: 800; color: <?= $color ?>; margin-bottom: 8px; }
    .msg { font-size: 14px; color: #475569; line-height: 1.5; margin-bottom: 20px; }
    .amount-badge {
      background: <?= $bgColor ?>;
      border: 1.5px solid <?= $color ?>;
      color: <?= $color ?>;
      border-radius: 50px;
      padding: 10px 28px;
      font-size: 22px; font-weight: 800;
      display: inline-block; margin-bottom: 24px;
    }
    .txn { font-size: 11px; color: #94a3b8; margin-bottom: 24px; font-family: monospace; }
    .btn {
      display: block; width: 100%;
      padding: 15px;
      background: linear-gradient(135deg, #D4AF37, #f5e07e);
      color: #0f1d35;
      border: none; border-radius: 14px;
      font-size: 15px; font-weight: 800;
      cursor: pointer; text-decoration: none;
      box-shadow: 0 6px 20px rgba(212,175,55,0.4);
    }
  </style>
</head>
<body>
<div class="card">
  <span class="icon"><?= $icon ?></span>
  <h1><?= htmlspecialchars($title) ?></h1>
  <p class="msg"><?= htmlspecialchars($message) ?></p>
  <?php if ($amtStr): ?>
    <div class="amount-badge"><?= $amtStr ?> Added</div>
  <?php endif; ?>
  <?php if ($txnId): ?>
    <p class="txn">Transaction ID: <?= htmlspecialchars($txnId) ?></p>
  <?php endif; ?>
  <a class="btn" href="javascript:window.close()"><?= $btnText ?></a>
</div>
</body>
</html>
<?php
    exit();
}

// ─── Validate inputs ─────────────────────────────────────────────────────────
if (empty($paymentId) || empty($orderId) || empty($signature) || empty($email) || $amount <= 0) {
    renderPage(false, 'Invalid Request', 'Missing payment details. Please try again from the app.');
}

if (empty($RAZORPAY_KEY_SECRET)) {
    renderPage(false, 'Server Error', 'Payment gateway is not configured on the server. Contact support.');
}

// ─── Verify HMAC SHA256 signature ────────────────────────────────────────────
$expectedSignature = hash_hmac('sha256', $orderId . '|' . $paymentId, $RAZORPAY_KEY_SECRET);

if (!hash_equals($expectedSignature, $signature)) {
    renderPage(false, 'Signature Mismatch', 'Payment verification failed. If money was deducted, it will be auto-refunded within 5–7 business days. Contact support.');
}

// ─── Verified! Credit the wallet ─────────────────────────────────────────────
try {
    $db = (new Database())->getConnection();

    // Create wallet_transactions table if not exists (safety net)
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

    // Get or create wallet
    $stmt = $db->prepare("SELECT id, balance FROM user_wallets WHERE LOWER(email) = LOWER(?) LIMIT 1 FOR UPDATE");
    $stmt->execute([$email]);
    $wallet = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$wallet) {
        $db->prepare("INSERT INTO user_wallets (email, balance) VALUES (?, ?)")->execute([$email, $amount]);
        $walletId    = $db->lastInsertId();
        $newBalance  = $amount;
    } else {
        $walletId   = $wallet['id'];
        $newBalance = (float)$wallet['balance'] + $amount;
        $db->prepare("UPDATE user_wallets SET balance = ? WHERE id = ?")->execute([$newBalance, $walletId]);
    }

    // Record transaction (idempotent — skip if payment_id already processed)
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

    renderPage(true,
        'Payment Successful!',
        'Your wallet has been topped up. Open the VStay app to see your updated balance.',
        $amount,
        $paymentId
    );

} catch (Exception $e) {
    if (isset($db) && $db->inTransaction()) {
        $db->rollBack();
    }
    // Payment verified but DB failed — log and notify
    error_log("RAZORPAY WALLET CREDIT FAILED: payment=$paymentId order=$orderId email=$email amount=$amount err=" . $e->getMessage());
    renderPage(false,
        'Credit Failed',
        'Your payment was received by Razorpay but could not be credited to your wallet automatically. Please contact support with Payment ID: ' . $paymentId
    );
}
?>
