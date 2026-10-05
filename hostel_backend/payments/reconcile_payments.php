<?php
/**
 * reconcile_payments.php
 * Reconciles captured payments on Razorpay against database wallet_transactions.
 * Automatically identifies any payments captured on Razorpay that were not credited to the DB.
 */

require_once __DIR__ . '/../config/database.php';

$secrets_file = __DIR__ . '/../config/secrets.php';
$secrets = [];
if (file_exists($secrets_file)) {
    $secrets = include($secrets_file);
}

$RAZORPAY_KEY_ID     = getenv('RAZORPAY_KEY_ID')     ?: ($secrets['RAZORPAY_KEY_ID']     ?? '');
$RAZORPAY_KEY_SECRET = getenv('RAZORPAY_KEY_SECRET') ?: ($secrets['RAZORPAY_KEY_SECRET'] ?? '');

header('Content-Type: application/json; charset=UTF-8');

try {
    $db = (new Database())->getConnection();

    // 1. Fetch recent payments from Razorpay (up to 100)
    $ch = curl_init("https://api.razorpay.com/v1/payments?count=100");
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_USERPWD        => "$RAZORPAY_KEY_ID:$RAZORPAY_KEY_SECRET",
        CURLOPT_TIMEOUT        => 20,
    ]);
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($httpCode !== 200) {
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => 'Failed to fetch payments from Razorpay API.']);
        exit();
    }

    $rzpData = json_decode($response, true);
    $payments = $rzpData['items'] ?? [];

    $reconciled = [];
    $missing    = [];
    $action     = $_GET['action'] ?? 'report'; // 'report' or 'credit_missing'

    foreach ($payments as $p) {
        if (($p['status'] ?? '') !== 'captured') {
            continue; // Skip failed or created orders that were never paid
        }

        $paymentId = $p['id'];
        $amount    = (float)(($p['amount'] ?? 0) / 100);
        $email     = trim($p['notes']['email'] ?? ($p['email'] ?? ''));
        $orderId   = $p['order_id'] ?? '';
        $createdAt = date('Y-m-d H:i:s', $p['created_at']);

        // Check if exists in wallet_transactions
        $checkStmt = $db->prepare("SELECT id, wallet_id, email, balance_after, created_at FROM wallet_transactions WHERE reference_id = ? LIMIT 1");
        $checkStmt->execute([$paymentId]);
        $txn = $checkStmt->fetch(PDO::FETCH_ASSOC);

        if ($txn) {
            $reconciled[] = [
                'payment_id' => $paymentId,
                'amount'     => $amount,
                'email'      => $email,
                'db_txn_id'  => $txn['id'],
                'created_at' => $createdAt,
            ];
        } else {
            $missingItem = [
                'payment_id' => $paymentId,
                'order_id'   => $orderId,
                'amount'     => $amount,
                'email'      => $email,
                'contact'    => $p['contact'] ?? '',
                'method'     => $p['method'] ?? '',
                'created_at' => $createdAt,
            ];

            if ($action === 'credit_missing' && !empty($email) && $amount > 0) {
                // Perform credit
                // Resolve wallet
                $wStmt = $db->prepare("SELECT id, balance FROM user_wallets WHERE LOWER(email) = LOWER(?) LIMIT 1 FOR UPDATE");
                $wStmt->execute([$email]);
                $w = $wStmt->fetch(PDO::FETCH_ASSOC);

                if (!$w) {
                    $db->prepare("INSERT INTO user_wallets (email, balance) VALUES (?, ?)")->execute([$email, $amount]);
                    $wId = $db->lastInsertId();
                    $newBal = $amount;
                } else {
                    $wId = $w['id'];
                    $newBal = (float)$w['balance'] + $amount;
                    $db->prepare("UPDATE user_wallets SET balance = ? WHERE id = ?")->execute([$newBal, $wId]);
                }

                $db->prepare("
                    INSERT INTO wallet_transactions (wallet_id, email, txn_type, amount, balance_after, reference_id, description)
                    VALUES (?, ?, 'credit', ?, ?, ?, ?)
                ")->execute([
                    $wId,
                    $email,
                    $amount,
                    $newBal,
                    $paymentId,
                    "Wallet Top-up via Reconciliation (Order: $orderId)"
                ]);

                $missingItem['action_taken'] = "Credited to wallet ID $wId. New balance: $newBal";
            }

            $missing[] = $missingItem;
        }
    }

    echo json_encode([
        'success'               => true,
        'total_captured_rzp'    => count($reconciled) + count($missing),
        'reconciled_count'      => count($reconciled),
        'missing_in_db_count'   => count($missing),
        'missing_payments'      => $missing,
        'action'                => $action,
    ], JSON_PRETTY_PRINT);

} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => $e->getMessage()]);
}
