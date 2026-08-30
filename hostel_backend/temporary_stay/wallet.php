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

function getOrCreateWallet($db, $email, $studentId = null, $regNo = null) {
    $email = trim($email);
    $variants = [];
    if (!empty($email)) {
        $variants[] = $email;
        $variants[] = strtolower($email);
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
    }
    if (!empty($regNo)) {
        $cleanReg = trim($regNo);
        $variants[] = $cleanReg;
        $variants[] = strtolower($cleanReg) . '.simats@saveetha.com';
        $variants[] = strtolower($cleanReg) . '@saveetha.com';
    }

    $variants = array_values(array_unique(array_filter($variants)));
    
    // Fast direct indexed lookup
    if (!empty($variants)) {
        $placeholders = implode(',', array_fill(0, count($variants), '?'));
        $stmt = $db->prepare("SELECT * FROM user_wallets WHERE email IN ($placeholders) ORDER BY balance DESC, id DESC LIMIT 1");
        $stmt->execute($variants);
        $wallet = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($wallet) {
            return [
                'id' => (int)$wallet['id'],
                'email' => $wallet['email'],
                'balance' => (float)$wallet['balance'],
                'currency' => $wallet['currency'] ?? 'INR'
            ];
        }
    }

    // If still not found, check users table by username/email with targeted indexed lookup
    if (!empty($regNo) || !empty($studentId) || !empty($email)) {
        $checkParams = [];
        $whereClauses = [];
        if (!empty($regNo)) {
            $whereClauses[] = "username = ?";
            $checkParams[] = $regNo;
        }
        if (!empty($email)) {
            $whereClauses[] = "email = ?";
            $checkParams[] = $email;
        }
        if (!empty($studentId) && (int)$studentId > 0) {
            $whereClauses[] = "id = ?";
            $checkParams[] = (int)$studentId;
        }
        if (!empty($whereClauses)) {
            $u_stmt = $db->prepare("SELECT id, username, email FROM users WHERE " . implode(' OR ', $whereClauses) . " LIMIT 1");
            $u_stmt->execute($checkParams);
            $u_row = $u_stmt->fetch(PDO::FETCH_ASSOC);
            if ($u_row) {
                $userVariants = [];
                if (!empty($u_row['email'])) $userVariants[] = $u_row['email'];
                if (!empty($u_row['username'])) {
                    $userVariants[] = $u_row['username'];
                    $userVariants[] = strtolower($u_row['username']) . '.simats@saveetha.com';
                }
                $userVariants = array_values(array_unique(array_filter($userVariants)));
                if (!empty($userVariants)) {
                    $ph = implode(',', array_fill(0, count($userVariants), '?'));
                    $w_stmt = $db->prepare("SELECT * FROM user_wallets WHERE email IN ($ph) ORDER BY balance DESC, id DESC LIMIT 1");
                    $w_stmt->execute($userVariants);
                    $wallet = $w_stmt->fetch(PDO::FETCH_ASSOC);
                    if ($wallet) {
                        return [
                            'id' => (int)$wallet['id'],
                            'email' => $wallet['email'],
                            'balance' => (float)$wallet['balance'],
                            'currency' => $wallet['currency'] ?? 'INR'
                        ];
                    }
                }
            }
        }
    }

    // If no wallet exists yet, create one
    $primaryEmail = (strpos($email, '@') === false && !empty($email)) ? $email . '.simats@saveetha.com' : (!empty($email) ? $email : ($regNo . '.simats@saveetha.com'));
    try {
        $ins = $db->prepare("INSERT INTO user_wallets (email, balance) VALUES (?, 0.00)");
        $ins->execute([$primaryEmail]);
        $walletId = $db->lastInsertId();
        return [
            'id' => (int)$walletId,
            'email' => $primaryEmail,
            'balance' => 0.00,
            'currency' => 'INR'
        ];
    } catch (Exception $eIns) {
        // In case of race condition / unique duplicate
        $stmt = $db->prepare("SELECT * FROM user_wallets WHERE email = ? LIMIT 1");
        $stmt->execute([$primaryEmail]);
        $wallet = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($wallet) {
            return [
                'id' => (int)$wallet['id'],
                'email' => $wallet['email'],
                'balance' => (float)$wallet['balance'],
                'currency' => $wallet['currency'] ?? 'INR'
            ];
        }
    }

    return [
        'id' => 0,
        'email' => $primaryEmail,
        'balance' => 0.00,
        'currency' => 'INR'
    ];
}

// ─────────────────────────────────────────────
// GET: Fetch Wallet Balance, Transactions, and Stay Request Info
// ─────────────────────────────────────────────
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'GET') {
    $email = trim($_GET['email'] ?? '');
    $request_id = trim($_GET['request_id'] ?? '');
    $student_id = trim($_GET['student_id'] ?? '');
    $reg_no = trim($_GET['reg_no'] ?? '');

    if (empty($email) && empty($reg_no)) {
        echo json_encode(["success" => false, "message" => "Email or Registration Number is required"]);
        exit();
    }

    try {
        $wallet = getOrCreateWallet($db, $email, $student_id, $reg_no);

        // Fetch recent transactions using indexed wallet_id or email
        $transactions = [];
        if (!empty($wallet['id'])) {
            $stmtTxn = $db->prepare("SELECT * FROM wallet_transactions WHERE wallet_id = ? ORDER BY id DESC LIMIT 30");
            $stmtTxn->execute([(int)$wallet['id']]);
            $transactions = $stmtTxn->fetchAll(PDO::FETCH_ASSOC);
        }

        // Fetch stay request details using indexed request_id or email
        $stayRequest = null;
        if (!empty($request_id)) {
            $stmtReq = $db->prepare("SELECT *, GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), hold_expires_at)) as hold_remaining_seconds 
                                     FROM temporary_stay_requests WHERE request_id = ? LIMIT 1");
            $stmtReq->execute([$request_id]);
            $stayRequest = $stmtReq->fetch(PDO::FETCH_ASSOC);
        } else if (!empty($email) || !empty($reg_no)) {
            $checkEmail = !empty($email) ? $email : $wallet['email'];
            $stmtReq = $db->prepare("SELECT *, GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), hold_expires_at)) as hold_remaining_seconds 
                                     FROM temporary_stay_requests WHERE email = ? ORDER BY id DESC LIMIT 1");
            $stmtReq->execute([$checkEmail]);
            $stayRequest = $stmtReq->fetch(PDO::FETCH_ASSOC);
        }

        echo json_encode([
            "success" => true,
            "wallet" => $wallet,
            "balance" => (float)$wallet['balance'],
            "transactions" => $transactions,
            "stay_request" => $stayRequest
        ]);
    } catch (Exception $e) {
        echo json_encode(["success" => false, "message" => $e->getMessage()]);
    }
    exit();
}

// ─────────────────────────────────────────────
// POST: Add Funds or Pay for Stay
// ─────────────────────────────────────────────
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
    $input = json_decode(file_get_contents('php://input'), true);
    $action = trim($input['action'] ?? 'add_funds');
    $email = trim($input['email'] ?? '');
    $student_id = trim($input['student_id'] ?? '');
    $reg_no = trim($input['reg_no'] ?? '');

    if (empty($email) && empty($reg_no)) {
        echo json_encode(["success" => false, "message" => "Email is required"]);
        exit();
    }

    try {
        $wallet = getOrCreateWallet($db, $email, $student_id, $reg_no);

        // 1. ADD FUNDS
        if ($action === 'add_funds') {
            $amount = (float)($input['amount'] ?? 0);
            if ($amount <= 0) {
                echo json_encode(["success" => false, "message" => "Amount must be greater than 0"]);
                exit();
            }

            $paymentMethod = trim($input['payment_method'] ?? 'UPI / NetBanking');
            $refId = 'TOPUP-' . strtoupper(substr(md5(uniqid(mt_rand(), true)), 0, 8));
            $newBalance = $wallet['balance'] + $amount;

            $db->beginTransaction();
            $db->prepare("UPDATE user_wallets SET balance = ? WHERE id = ?")->execute([$newBalance, $wallet['id']]);
            $db->prepare("INSERT INTO wallet_transactions (wallet_id, email, txn_type, amount, balance_after, reference_id, description) VALUES (?, ?, 'credit', ?, ?, ?, ?)")
               ->execute([$wallet['id'], $email, $amount, $newBalance, $refId, "Wallet Top-up via " . $paymentMethod]);
            $db->commit();

            echo json_encode([
                "success" => true,
                "message" => "₹" . number_format($amount, 2) . " successfully added to your wallet!",
                "balance" => $newBalance,
                "txn_id" => $refId
            ]);
            exit();
        }

        // 2. PAY FOR TEMPORARY STAY
        if ($action === 'pay_stay') {
            $request_id = trim($input['request_id'] ?? '');
            if (empty($request_id)) {
                echo json_encode(["success" => false, "message" => "Request ID is required"]);
                exit();
            }

            $stmtReq = $db->prepare("SELECT * FROM temporary_stay_requests WHERE request_id = ? LIMIT 1");
            $stmtReq->execute([$request_id]);
            $req = $stmtReq->fetch(PDO::FETCH_ASSOC);

            if (!$req) {
                echo json_encode(["success" => false, "message" => "Temporary stay request not found"]);
                exit();
            }

            if ($req['payment_status'] === 'paid') {
                echo json_encode([
                    "success" => true,
                    "message" => "This stay is already paid and allocated.",
                    "status" => "allocated",
                    "payment_status" => "paid",
                    "payment_txn_id" => $req['payment_txn_id']
                ]);
                exit();
            }

            if ($req['status'] === 'rejected' || $req['status'] === 'timed_out') {
                echo json_encode(["success" => false, "message" => "Cannot pay for a " . $req['status'] . " request."]);
                exit();
            }

            // Check if 24-hour hold expired
            if (!empty($req['hold_expires_at'])) {
                $holdExp = strtotime($req['hold_expires_at']);
                if (time() > $holdExp) {
                    $db->prepare("UPDATE temporary_stay_requests SET status = 'timed_out', hold_status = 'expired' WHERE request_id = ?")->execute([$request_id]);
                    echo json_encode(["success" => false, "message" => "24-hour payment window expired. The room hold has timed out."]);
                    exit();
                }
            }

            $feeToPay = (float)($req['amount'] ?? 0);
            if ($feeToPay <= 0) {
                $feeToPay = 500.00;
            }

            if ($wallet['balance'] < $feeToPay) {
                $shortage = $feeToPay - $wallet['balance'];
                echo json_encode([
                    "success" => false,
                    "insufficient_balance" => true,
                    "balance" => $wallet['balance'],
                    "amount_required" => $feeToPay,
                    "shortage" => $shortage,
                    "message" => "Insufficient wallet balance. Please add ₹" . number_format($shortage, 2) . " to complete payment."
                ]);
                exit();
            }

            $txnId = 'TXN-' . strtoupper(substr(md5(uniqid(mt_rand(), true)), 0, 10));
            $newBalance = $wallet['balance'] - $feeToPay;

            $db->beginTransaction();

            // 1. Debit Wallet
            $db->prepare("UPDATE user_wallets SET balance = ? WHERE id = ?")->execute([$newBalance, $wallet['id']]);
            $db->prepare("INSERT INTO wallet_transactions (wallet_id, email, txn_type, amount, balance_after, reference_id, description) VALUES (?, ?, 'debit', ?, ?, ?, ?)")
               ->execute([$wallet['id'], $email, $feeToPay, $newBalance, $txnId, "Stay Fee for Room " . $req['room_no'] . " (" . $req['hostel_name'] . ")"]);

            // 2. Mark Temporary Stay as Paid & Allocated
            $db->prepare("UPDATE temporary_stay_requests SET payment_status = 'paid', status = 'allocated', hold_status = 'confirmed', payment_txn_id = ? WHERE request_id = ?")
               ->execute([$txnId, $request_id]);

            // 3. Decrement available room beds
            $rCode = !empty($req['room_code']) ? $req['room_code'] : $req['room_no'];
            if (!empty($rCode)) {
                try {
                    $db->prepare("UPDATE rooms_groups_details SET available_beds = GREATEST(0, available_beds - 1), occupied_beds = occupied_beds + 1 WHERE room_number = ?")->execute([$rCode]);
                    $db->prepare("UPDATE room_master SET available_beds = GREATEST(0, available_beds - 1), occupied_beds = occupied_beds + 1 WHERE room_code = ? OR room_no = ?")->execute([$rCode, $rCode]);
                } catch (Exception $eR) {}
            }

            // 4. Activate User Account with role 'guest'
            try {
                $checkU = $db->prepare("SELECT id FROM users WHERE email = ? LIMIT 1");
                $checkU->execute([$email]);
                $userU = $checkU->fetch(PDO::FETCH_ASSOC);
                if ($userU) {
                    $db->prepare("UPDATE users SET role = 'guest', Status = 'active', RoomId = ?, HostelId = ? WHERE id = ?")
                       ->execute([$req['room_no'], $req['hostel_name'], $userU['id']]);
                }
            } catch (Exception $eU) {}

            $db->commit();

            // 5. Send confirmation push notification
            try {
                $userStmt = $db->prepare("SELECT fcm_token FROM users WHERE email = ? AND fcm_token IS NOT NULL AND fcm_token != '' LIMIT 1");
                $userStmt->execute([$email]);
                $userFCM = $userStmt->fetch(PDO::FETCH_ASSOC);
                if ($userFCM && !empty($userFCM['fcm_token'])) {
                    $notifTitle = "VSTAY - Stay Confirmed! 🔑";
                    $notifBody = "Payment of ₹" . number_format($feeToPay, 2) . " successful! Room " . $req['room_no'] . " (" . $req['hostel_name'] . ") is allocated from " . $req['from_date'] . " to " . $req['to_date'] . ".";
                    sendFCM($userFCM['fcm_token'], $notifTitle, $notifBody, $request_id, 'system', 'VSTAY Allocation', $notifBody, 'temporary_stay', 'student');
                }
            } catch (Exception $eNotif) {}

            echo json_encode([
                "success" => true,
                "message" => "Payment successful! Room " . $req['room_no'] . " allocated successfully.",
                "request_id" => $request_id,
                "status" => "allocated",
                "payment_status" => "paid",
                "payment_txn_id" => $txnId,
                "balance" => $newBalance
            ]);
            exit();
        }

        echo json_encode(["success" => false, "message" => "Invalid action"]);
    } catch (Exception $e) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        echo json_encode(["success" => false, "message" => $e->getMessage()]);
    }
    exit();
}
?>
