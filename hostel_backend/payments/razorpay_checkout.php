<?php
/**
 * razorpay_checkout.php
 * Backend-hosted HTML page that renders the Razorpay Web Checkout popup.
 * Flutter opens this via url_launcher. No native SDK needed.
 *
 * GET params: order_id, email, amount, name, key_id
 */

$orderId = htmlspecialchars($_GET['order_id'] ?? '', ENT_QUOTES);
$email   = htmlspecialchars($_GET['email']    ?? '', ENT_QUOTES);
$amount  = (float)($_GET['amount'] ?? 0);
$name    = htmlspecialchars($_GET['name']     ?? 'Student', ENT_QUOTES);
$keyId   = htmlspecialchars($_GET['key_id']   ?? '', ENT_QUOTES);

if (empty($orderId) || empty($keyId) || $amount <= 0) {
    http_response_code(400);
    echo '<h2 style="font-family:sans-serif;color:red;">Invalid payment link. Please try again from the app.</h2>';
    exit();
}

$amountPaise = (int)round($amount * 100);

// Callback URL (same server)
$proto = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on') ||
         (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') ? 'https' : 'http';
$host = $_SERVER['HTTP_X_FORWARDED_HOST'] ?? ($_SERVER['HTTP_HOST'] ?? '');
if (empty($host) || $host === 'localhost' || $host === 'backend' || strpos($host, 'localhost:') === 0) {
    $host = 'vstay.saveetha.com';
}
$baseUrl     = $proto . '://' . $host;
$callbackUrl = $baseUrl . '/payments/razorpay_callback.php';
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0" />
  <title>VStay – Add Funds</title>
  <script src="https://checkout.razorpay.com/v1/checkout.js"></script>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      min-height: 100vh;
      background: linear-gradient(135deg, #0f1d35 0%, #1b3a6b 60%, #0f1d35 100%);
      display: flex;
      align-items: center;
      justify-content: center;
      font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
      color: #ffffff;
    }

    .card {
      background: rgba(255,255,255,0.07);
      border: 1px solid rgba(255,255,255,0.15);
      border-radius: 24px;
      padding: 40px 36px 36px;
      max-width: 400px;
      width: 92%;
      text-align: center;
      backdrop-filter: blur(16px);
      box-shadow: 0 24px 64px rgba(0,0,0,0.4);
    }

    .logo {
      width: 64px;
      height: 64px;
      background: linear-gradient(135deg, #D4AF37, #f5e07e);
      border-radius: 18px;
      margin: 0 auto 20px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 28px;
      font-weight: 900;
      color: #0f1d35;
      box-shadow: 0 8px 24px rgba(212,175,55,0.4);
    }

    h1 {
      font-size: 22px;
      font-weight: 700;
      margin-bottom: 6px;
      letter-spacing: -0.3px;
    }

    .subtitle {
      font-size: 13px;
      color: rgba(255,255,255,0.55);
      margin-bottom: 28px;
    }

    .amount-pill {
      background: linear-gradient(135deg, #D4AF37, #f5e07e);
      color: #0f1d35;
      border-radius: 50px;
      padding: 14px 32px;
      display: inline-block;
      font-size: 28px;
      font-weight: 800;
      margin-bottom: 28px;
      letter-spacing: -0.5px;
      box-shadow: 0 6px 20px rgba(212,175,55,0.35);
    }

    .info-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 10px 0;
      border-bottom: 1px solid rgba(255,255,255,0.08);
      font-size: 13px;
    }
    .info-row:last-of-type { border-bottom: none; }
    .info-label { color: rgba(255,255,255,0.5); }
    .info-value { color: #fff; font-weight: 600; }

    .pay-btn {
      margin-top: 28px;
      width: 100%;
      padding: 16px;
      background: linear-gradient(135deg, #D4AF37, #f5e07e);
      color: #0f1d35;
      border: none;
      border-radius: 14px;
      font-size: 16px;
      font-weight: 800;
      cursor: pointer;
      letter-spacing: 0.3px;
      box-shadow: 0 6px 20px rgba(212,175,55,0.4);
      transition: transform 0.15s, box-shadow 0.15s;
    }
    .pay-btn:hover { transform: translateY(-1px); box-shadow: 0 10px 28px rgba(212,175,55,0.5); }
    .pay-btn:active { transform: translateY(1px); }
    .pay-btn:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }

    .spinner {
      display: none;
      width: 20px; height: 20px;
      border: 2px solid rgba(15,29,53,0.3);
      border-top-color: #0f1d35;
      border-radius: 50%;
      animation: spin 0.7s linear infinite;
      margin: 0 auto;
    }
    @keyframes spin { to { transform: rotate(360deg); } }

    .secure-note {
      margin-top: 20px;
      font-size: 11.5px;
      color: rgba(255,255,255,0.38);
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 5px;
    }

    .cancel-btn {
      display: block;
      margin-top: 14px;
      font-size: 12.5px;
      color: rgba(255,255,255,0.4);
      text-decoration: none;
      cursor: pointer;
      background: none;
      border: none;
      width: 100%;
    }
    .cancel-btn:hover { color: rgba(255,255,255,0.7); }
  </style>
</head>
<body>
<div class="card">
  <div class="logo">V</div>
  <h1>Add Funds to Wallet</h1>
  <p class="subtitle">VStay Hostel Management</p>

  <div class="amount-pill">₹<?= number_format($amount, 2) ?></div>

  <div class="info-row">
    <span class="info-label">Account</span>
    <span class="info-value"><?= $email ?></span>
  </div>
  <div class="info-row">
    <span class="info-label">Order ID</span>
    <span class="info-value" style="font-size:11px;opacity:0.7;"><?= $orderId ?></span>
  </div>
  <div class="info-row">
    <span class="info-label">Destination</span>
    <span class="info-value">VStay Wallet</span>
  </div>

  <button class="pay-btn" id="payBtn" onclick="startPayment()">
    Pay ₹<?= number_format($amount, 2) ?> Securely
  </button>
  <button class="cancel-btn" onclick="window.close()">Cancel &amp; return to app</button>

  <p class="secure-note">
    🔒 Secured by Razorpay · 256-bit SSL
  </p>
</div>

<script>
const options = {
  key:         '<?= $keyId ?>',
  amount:      <?= $amountPaise ?>,
  currency:    'INR',
  name:        'VStay',
  description: 'Wallet Top-up',
  order_id:    '<?= $orderId ?>',
  prefill: {
    email: '<?= $email ?>',
    name:  '<?= $name ?>',
  },
  theme: { color: '#1B2B48' },
  handler: function(response) {
    // Payment succeeded — POST to backend for verification & wallet credit
    const btn = document.getElementById('payBtn');
    btn.disabled  = true;
    btn.innerHTML = '<div class="spinner" style="display:inline-block;"></div>';

    const form = document.createElement('form');
    form.method = 'POST';
    form.action = 'razorpay_callback.php';

    const fields = {
      razorpay_payment_id: response.razorpay_payment_id,
      razorpay_order_id:   response.razorpay_order_id,
      razorpay_signature:  response.razorpay_signature,
      email:               '<?= $email ?>',
      amount:              '<?= $amount ?>',
    };

    for (const [k, v] of Object.entries(fields)) {
      const el = document.createElement('input');
      el.type  = 'hidden';
      el.name  = k;
      el.value = v;
      form.appendChild(el);
    }

    document.body.appendChild(form);
    form.submit();
  },
  modal: {
    ondismiss: function() {
      // User closed the payment sheet without paying
      document.getElementById('payBtn').disabled = false;
    }
  }
};

function startPayment() {
  const btn = document.getElementById('payBtn');
  btn.disabled = true;
  try {
    const rzp = new Razorpay(options);
    rzp.on('payment.failed', function(resp) {
      alert('Payment failed: ' + (resp.error.description || 'Unknown error'));
      btn.disabled = false;
    });
    rzp.open();
  } catch(e) {
    alert('Could not load payment gateway. Please check your connection and try again.');
    btn.disabled = false;
  }
}

// Auto-open checkout when page loads (best UX — no extra tap needed)
window.addEventListener('load', function() {
  setTimeout(startPayment, 600);
});
</script>
</body>
</html>
