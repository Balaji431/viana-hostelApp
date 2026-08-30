<?php
/**
 * razorpay_create_order.php
 * Creates a Razorpay order and returns the checkout URL + order details.
 *
 * POST body (JSON): { "email": "...", "amount": 500, "name": "Student Name" }
 * Response: { "success": true, "order_id": "...", "key_id": "...", "checkout_url": "..." }
 */

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
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

$RAZORPAY_KEY_ID     = getenv('RAZORPAY_KEY_ID')     ?: ($secrets['RAZORPAY_KEY_ID']     ?? 'rzp_live_TUPCTe6VWo1LGj');
$RAZORPAY_KEY_SECRET = getenv('RAZORPAY_KEY_SECRET') ?: ($secrets['RAZORPAY_KEY_SECRET'] ?? 'd2gnwZ52h6jypg2fzI04jVxj');

if (empty($RAZORPAY_KEY_ID) || empty($RAZORPAY_KEY_SECRET)) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Razorpay credentials not configured on server.']);
    exit();
}

$body  = json_decode(file_get_contents('php://input'), true) ?? [];
$email  = trim($body['email']  ?? '');
$amount = (float)($body['amount'] ?? 0);
$name   = trim($body['name']   ?? 'Student');

if (empty($email) || $amount <= 0) {
    echo json_encode(['success' => false, 'message' => 'Email and a positive amount are required.']);
    exit();
}

// Razorpay amount is in paise (INR × 100)
$amountPaise = (int)round($amount * 100);

$receiptId = 'WALLET-' . strtoupper(substr(md5(uniqid(mt_rand(), true)), 0, 10));

$orderPayload = json_encode([
    'amount'          => $amountPaise,
    'currency'        => 'INR',
    'receipt'         => $receiptId,
    'notes'           => [
        'email'   => $email,
        'purpose' => 'VStay Wallet Top-up',
    ],
]);

$ch = curl_init('https://api.razorpay.com/v1/orders');
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST           => true,
    CURLOPT_POSTFIELDS     => $orderPayload,
    CURLOPT_USERPWD        => "$RAZORPAY_KEY_ID:$RAZORPAY_KEY_SECRET",
    CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
    CURLOPT_TIMEOUT        => 15,
    CURLOPT_SSL_VERIFYPEER => true,
]);
$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$curlErr  = curl_error($ch);
curl_close($ch);

if ($curlErr) {
    echo json_encode(['success' => false, 'message' => 'Network error: ' . $curlErr]);
    exit();
}

$rzpRes = json_decode($response, true);

if ($httpCode !== 200 || empty($rzpRes['id'])) {
    $errDesc = $rzpRes['error']['description'] ?? 'Unknown Razorpay error';
    echo json_encode(['success' => false, 'message' => "Razorpay error: $errDesc"]);
    exit();
}

$orderId = $rzpRes['id'];

// Build the checkout page URL (hosted on THIS backend)
$proto = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on') ||
         (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') ? 'https' : 'http';
$host = $_SERVER['HTTP_X_FORWARDED_HOST'] ?? ($_SERVER['HTTP_HOST'] ?? '');
if (empty($host) || $host === 'localhost' || $host === 'backend' || strpos($host, 'localhost:') === 0) {
    $host = 'vstay.saveetha.com';
}
if (strpos($host, 'saveetha.com') !== false) {
    $proto = 'https';
}
$baseUrl = $proto . '://' . $host;
$checkoutUrl = $baseUrl . '/payments/razorpay_checkout.php'
    . '?order_id='   . urlencode($orderId)
    . '&email='      . urlencode($email)
    . '&amount='     . urlencode((string)$amount)
    . '&name='       . urlencode($name)
    . '&key_id='     . urlencode($RAZORPAY_KEY_ID);

echo json_encode([
    'success'      => true,
    'order_id'     => $orderId,
    'key_id'       => $RAZORPAY_KEY_ID,
    'amount'       => $amount,
    'amount_paise' => $amountPaise,
    'checkout_url' => $checkoutUrl,
    'receipt'      => $receiptId,
]);
?>
