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
require_once __DIR__ . '/../config/api_config.php';
require_once __DIR__ . '/../utils/activity_logger.php';
require_once __DIR__ . '/../utils/auth_helper.php';

$authUser = requireAuth();

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
$months    = max(1, (int)($input['months'] ?? 12));
$roomRentInput = isset($input['room_rent']) ? (float)$input['room_rent'] : 0.0;
$foodInput = isset($input['food']) ? (float)$input['food'] : 0.0;
$multiplierInput = isset($input['premium_multiplier']) ? (float)$input['premium_multiplier'] : 1.0;

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

    $userRole = strtolower($authUser['role'] ?? '');
    if ($userRole === 'student') {
        $authUsername = strtolower($authUser['username'] ?? '');
        $profReg = strtolower($profile['reg_no'] ?? '');
        $profUserDbId = (int)($profile['user_db_id'] ?? 0);
        if ($authUsername !== $profReg && (int)$authUser['id'] !== $profUserDbId) {
            http_response_code(403);
            echo json_encode(["success" => false, "message" => "Forbidden: You are not authorized to renew another student's booking."]);
            exit();
        }
    }

    // Strict Renewal Deadline: Must renew on or before renewal due date at 11:59:59 PM
    $currentRenewalDate = $profile['renewal_date'] ?? ($profile['valid_to'] ?? null);
    if (!empty($currentRenewalDate)) {
        $deadlineTs = strtotime($currentRenewalDate . ' 23:59:59');
        if (time() > $deadlineTs) {
            echo json_encode([
                "success" => false,
                "renewal_expired" => true,
                "message" => "Renewal window closed on " . date('d M Y', strtotime($currentRenewalDate)) . " at 11:59 PM. Late renewal is not permitted as the room is freed for new applicants. Please apply freshly via the VStudy portal."
            ]);
            exit();
        }
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
        "Hostel Booking Renewal ($months Months Extended) - Ref: $refId"
    ]);

    // Extend renewal_date and valid_to by chosen months from the existing renewal date
    $baseDate = !empty($currentRenewalDate) ? $currentRenewalDate : date('Y-m-d');
    $newRenewalDate = date('Y-m-d', strtotime($baseDate . " +$months months"));
    $daysRemaining = max(0, (int)round((strtotime($newRenewalDate) - time()) / 86400));

    $stmtUpProf = $db->prepare("
        UPDATE profile 
        SET 
            renewal_date = ?, 
            valid_to = ?,
            remaining_days = ?
        WHERE reg_no = ? OR id = ?
    ");
    $stmtUpProf->execute([$newRenewalDate, $newRenewalDate, $daysRemaining, $effectiveRegNo, $profile['id']]);

    // Also synchronize users.DOL and vstudy_payments table
    $db->prepare("UPDATE users SET DOL = ? WHERE username = ? OR id = ?")->execute([$newRenewalDate, $effectiveRegNo, $effectiveUserId]);
    $db->prepare("UPDATE vstudy_payments SET renewal_date = ?, remaining_days = ? WHERE roll_number = ?")->execute([$newRenewalDate, $daysRemaining, $effectiveRegNo]);

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

    // --- Outbound Real-time Sync to VStudy ERP ---
    $vstudyRenewalUrl = defined('VSTUDY_RENEWAL_API_URL') ? VSTUDY_RENEWAL_API_URL : 'https://vstudy.saveetha.com/api/hostel-applications/external/renew';
    $vstudyClientId = defined('VSTUDY_CLIENT_ID') ? VSTUDY_CLIENT_ID : '';
    $vstudyClientSecret = defined('VSTUDY_CLIENT_SECRET') ? VSTUDY_CLIENT_SECRET : '';

    $vstudySyncResult = null;
    if (!empty($vstudyRenewalUrl) && !empty($vstudyClientId) && !empty($vstudyClientSecret)) {
        $roomRent = isset($input['room_rent']) ? (float)$input['room_rent'] : 0.0;
        $foodRent = isset($input['food']) ? (float)$input['food'] : 0.0;
        $premiumMultiplier = isset($input['premium_multiplier']) ? (float)$input['premium_multiplier'] : 1.0;

        // --- Fetch correct roomRent + food from VStudy Pricing API ---
        // Step 1: Get the student's room type
        $roomType = '';
        if ($roomRent <= 0 || $foodRent <= 0) {
            try {
                $rtStmt = $db->prepare("SELECT RoomType FROM users WHERE username = ? OR id = ? LIMIT 1");
                $rtStmt->execute([$effectiveRegNo, $effectiveUserId]);
                $roomType = trim((string)$rtStmt->fetchColumn());

                // Fallback: get room type from room_master using room_code
                if (empty($roomType)) {
                    $rmStmt = $db->prepare("SELECT room_type FROM room_master WHERE room_code = ? LIMIT 1");
                    $rmStmt->execute([$roomNum]);
                    $roomType = trim((string)$rmStmt->fetchColumn());
                }
            } catch (Exception $rtErr) {}
        }

        // Step 2: Validate room type against VStudy's official room-types API
        // Only proceed with pricing API if the room type is a valid VStudy room type
        $isValidRoomType = false;
        if (!empty($roomType)) {
            try {
                $roomTypesUrl = defined('VSTUDY_ROOM_TYPES_API_URL')
                    ? VSTUDY_ROOM_TYPES_API_URL
                    : 'https://vstudy.saveetha.com/api/hostel-settings/room-types/external';

                $rtCh = curl_init($roomTypesUrl);
                curl_setopt($rtCh, CURLOPT_RETURNTRANSFER, true);
                curl_setopt($rtCh, CURLOPT_HTTPHEADER, [
                    'Content-Type: application/json',
                    'x-client-id: ' . $vstudyClientId,
                    'x-client-secret: ' . $vstudyClientSecret,
                ]);
                curl_setopt($rtCh, CURLOPT_TIMEOUT, 8);
                curl_setopt($rtCh, CURLOPT_SSL_VERIFYPEER, false);
                $rtRes  = curl_exec($rtCh);
                $rtCode = curl_getinfo($rtCh, CURLINFO_HTTP_CODE);
                curl_close($rtCh);

                if ($rtCode === 200) {
                    $rtData = json_decode($rtRes, true);
                    if (!empty($rtData['success']) && is_array($rtData['data'])) {
                        // Case-insensitive match against the official room types list
                        $officialTypes = array_map('strtolower', $rtData['data']);
                        $isValidRoomType = in_array(strtolower($roomType), $officialTypes, true);
                    }
                }
            } catch (Exception $rtErr) {}
        }

        // Step 3: Call pricing API ONLY if room type is valid per VStudy
        if ($isValidRoomType && ($roomRent <= 0 || $foodRent <= 0)) {
            try {
                $pricingUrl = defined('VSTUDY_PRICING_API_URL')
                    ? VSTUDY_PRICING_API_URL
                    : 'https://vstudy.saveetha.com/api/hostel-applications/external/pricing';

                $pCh = curl_init($pricingUrl);
                curl_setopt($pCh, CURLOPT_RETURNTRANSFER, true);
                curl_setopt($pCh, CURLOPT_POST, true);
                curl_setopt($pCh, CURLOPT_POSTFIELDS, json_encode(['roomType' => $roomType]));
                curl_setopt($pCh, CURLOPT_HTTPHEADER, [
                    'Content-Type: application/json',
                    'x-client-id: ' . $vstudyClientId,
                    'x-client-secret: ' . $vstudyClientSecret,
                ]);
                curl_setopt($pCh, CURLOPT_TIMEOUT, 8);
                curl_setopt($pCh, CURLOPT_SSL_VERIFYPEER, false);
                $pRes  = curl_exec($pCh);
                $pCode = curl_getinfo($pCh, CURLINFO_HTTP_CODE);
                curl_close($pCh);

                if ($pCode === 200) {
                    $pData = json_decode($pRes, true);
                    if (!empty($pData['success']) && !empty($pData['data']['renewals'])) {
                        $matchedTier = null;

                        // Find the renewal tier that matches the chosen months
                        foreach ($pData['data']['renewals'] as $tier) {
                            if ((int)$tier['months'] === (int)$months) {
                                $matchedTier = $tier;
                                break;
                            }
                        }
                        // If no exact month match, fall back to first (12-month) tier
                        if ($matchedTier === null && !empty($pData['data']['renewals'][0])) {
                            $matchedTier = $pData['data']['renewals'][0];
                        }

                        if ($matchedTier !== null) {
                            $apiFood      = (float)$matchedTier['food'];
                            $apiRoomRent  = (float)$matchedTier['roomRent'];
                            $premiumMultiplier = (float)($matchedTier['premiumMultiplier'] ?? 1.0);

                            // Food cap: if pricing API returns food > ₹50,000, cap it at ₹50,000
                            // (₹50,000 is the maximum annual food charge)
                            $foodRent = $apiFood > 50000 ? 50000.0 : $apiFood;

                            // roomRent = total amount paid - food (ensures the split is exact)
                            $roomRent = round($amount - $foodRent, 2);
                        }
                    }
                }
            } catch (Exception $pricingErr) {
                // Pricing API failed — fall back to room_master DB
            }
        }

        // Step 4: Fallback — room_master DB (correct columns, room_code)
        if ($roomRent <= 0) {
            try {
                $rmStmt = $db->prepare("SELECT amount, food FROM room_master WHERE room_code = ? LIMIT 1");
                $rmStmt->execute([$roomNum]);
                $rmRow = $rmStmt->fetch(PDO::FETCH_ASSOC);
                if ($rmRow && (float)$rmRow['amount'] > 0) {
                    $roomRent = (float)$rmRow['amount'];
                    if ($foodRent <= 0) $foodRent = (float)$rmRow['food'];
                }
            } catch (Exception $ign) {}
        }

        // Step 5: Absolute last resort
        if ($roomRent <= 0) $roomRent = round($amount * 0.75, 2);
        if ($foodRent  <= 0) $foodRent  = round(max(0, $amount - $roomRent), 2);

        if (!function_exists('generateUuidV4')) {
            function generateUuidV4() {
                $data = random_bytes(16);
                $data[6] = chr(ord($data[6]) & 0x0f | 0x40);
                $data[8] = chr(ord($data[8]) & 0x3f | 0x80);
                return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
            }
        }
        $eventId = generateUuidV4();

        $vstudyPayload = [
            'externalEventId'    => $eventId,
            'rollNumber'         => $effectiveRegNo,
            'months'             => (int)$months,
            'amount'             => (float)$amount,
            'roomRent'           => (float)$roomRent,
            'food'               => (float)$foodRent,
            'premiumMultiplier'  => (float)$premiumMultiplier
        ];

        try {
            $ch = curl_init($vstudyRenewalUrl);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($vstudyPayload));
            curl_setopt($ch, CURLOPT_HTTPHEADER, [
                'Content-Type: application/json',
                'x-client-id: ' . $vstudyClientId,
                'x-client-secret: ' . $vstudyClientSecret
            ]);
            curl_setopt($ch, CURLOPT_TIMEOUT, 8);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
            $vstudyRaw = curl_exec($ch);
            $vstudyCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);

            $vstudyJson = json_decode($vstudyRaw, true);
            $vstudySyncResult = [
                'http_code' => $vstudyCode,
                'synced'    => ($vstudyCode === 200 && ($vstudyJson['success'] ?? false) === true),
                'response'  => $vstudyJson
            ];

            // If VStudy returns an authoritative renewalDate, update profile card data immediately
            if (!empty($vstudyJson['data']['renewalDate'])) {
                $confirmedDate = trim($vstudyJson['data']['renewalDate']);
                $confirmedDays = max(0, (int)round((strtotime($confirmedDate) - time()) / 86400));

                $db->prepare("
                    UPDATE profile 
                    SET renewal_date = ?, valid_to = ?, remaining_days = ? 
                    WHERE reg_no = ? OR user_id = ?
                ")->execute([$confirmedDate, $confirmedDate, $confirmedDays, $effectiveRegNo, $effectiveUserId]);

                $db->prepare("
                    UPDATE users SET DOL = ? WHERE username = ? OR id = ?
                ")->execute([$confirmedDate, $effectiveRegNo, $effectiveUserId]);

                $db->prepare("
                    UPDATE vstudy_payments SET renewal_date = ?, remaining_days = ? WHERE roll_number = ?
                ")->execute([$confirmedDate, $confirmedDays, $effectiveRegNo]);

                $newRenewalDate = $confirmedDate;
                $daysRemaining = $confirmedDays;
            }

            // Append VStudy renewalId to renewal_requests remarks
            $vRenewalId = $vstudyJson['data']['renewalId'] ?? '';
            if (!empty($vRenewalId)) {
                $db->prepare("
                    UPDATE renewal_requests 
                    SET remarks = CONCAT(remarks, ' | VStudy Renewal ID: ', ?)
                    WHERE student_reg_no = ? ORDER BY id DESC LIMIT 1
                ")->execute([$vRenewalId, $effectiveRegNo]);
            }

            // Record in dedicated vstudy_renewal_syncs table
            try {
                $insSync = $db->prepare("
                    INSERT INTO vstudy_renewal_syncs (
                        external_event_id, roll_number, student_name, renewal_id,
                        application_id, months, amount, room_rent, food,
                        premium_multiplier, previous_renewal_date, new_renewal_date,
                        status, sync_status, replayed, request_payload, response_payload
                    ) VALUES (
                        :external_event_id, :roll_number, :student_name, :renewal_id,
                        :application_id, :months, :amount, :room_rent, :food,
                        :premium_multiplier, :previous_renewal_date, :new_renewal_date,
                        :status, :sync_status, :replayed, :request_payload, :response_payload
                    ) ON DUPLICATE KEY UPDATE 
                        renewal_id = VALUES(renewal_id),
                        new_renewal_date = VALUES(new_renewal_date),
                        status = VALUES(status),
                        sync_status = VALUES(sync_status),
                        replayed = VALUES(replayed),
                        response_payload = VALUES(response_payload)
                ");

                $vData = $vstudyJson['data'] ?? [];
                $insSync->execute([
                    ':external_event_id'      => $eventId,
                    ':roll_number'             => $effectiveRegNo,
                    ':student_name'            => $name,
                    ':renewal_id'              => $vData['renewalId'] ?? null,
                    ':application_id'          => $vData['applicationId'] ?? null,
                    ':months'                  => (int)($vData['months'] ?? $months),
                    ':amount'                  => (float)$amount,
                    ':room_rent'               => (float)$roomRent,
                    ':food'                    => (float)$foodRent,
                    ':premium_multiplier'      => (float)$premiumMultiplier,
                    ':previous_renewal_date'   => !empty($vData['previousRenewalDate']) ? $vData['previousRenewalDate'] : null,
                    ':new_renewal_date'        => !empty($vData['renewalDate']) ? $vData['renewalDate'] : $newRenewalDate,
                    ':status'                  => $vData['status'] ?? 'PAID',
                    ':sync_status'             => ($vstudyCode === 200 && ($vstudyJson['success'] ?? false)) ? 'synced' : 'failed',
                    ':replayed'                => !empty($vstudyJson['replayed']) ? 1 : 0,
                    ':request_payload'         => json_encode($vstudyPayload),
                    ':response_payload'        => $vstudyRaw
                ]);
            } catch (Exception $syncErr) {}

            // Also record in vstudy_webhook_events table
            try {
                $insWb = $db->prepare("
                    INSERT INTO vstudy_webhook_events (
                        event_id, event_type, entity_type, entity_id,
                        roll_number, room_number, hostel_name, status,
                        occurred_at, payload, response, created_at, updated_at
                    ) VALUES (
                        ?, 'booking.renewed', 'HOSTEL_BOOKING', ?,
                        ?, ?, ?, 'PROCESSED',
                        NOW(), ?, ?, NOW(), NOW()
                    ) ON DUPLICATE KEY UPDATE status = 'PROCESSED'
                ");
                $insWb->execute([
                    $eventId,
                    $vRenewalId ?: $eventId,
                    $effectiveRegNo,
                    $currentRoom,
                    $hostelName,
                    json_encode([
                        'eventId'         => $eventId,
                        'externalEventId' => $eventId,
                        'eventType'       => 'booking.renewed',
                        'entityType'      => 'HOSTEL_BOOKING',
                        'entityId'        => $vRenewalId ?: $eventId,
                        'occurredAt'      => date('c'),
                        'data'            => $vstudyPayload
                    ]),
                    $vstudyRaw ?: json_encode(['received' => true, 'synced' => true])
                ]);
            } catch (Exception $wbErr) {}

            // Record VStudy sync audit log
            try {
                $stmtAudit = $db->prepare("
                    INSERT INTO audit_logs (username, role, action, module_name, new_value, ip_address)
                    VALUES (?, 'system', 'OUTBOUND_VSTUDY_RENEWAL_SYNC', 'vstudy_sync', ?, ?)
                ");
                $stmtAudit->execute([
                    $effectiveRegNo,
                    json_encode([
                        'endpoint' => $vstudyRenewalUrl,
                        'payload'  => $vstudyPayload,
                        'result'   => $vstudySyncResult
                    ]),
                    $ip
                ]);
            } catch (Exception $aErr) {}
        } catch (Exception $vErr) {
            $vstudySyncResult = ['synced' => false, 'error' => $vErr->getMessage()];
        }
    }

    $durationMsg = ($months == 12) ? "1 year" : "$months months";

    echo json_encode([
        "success" => true,
        "message" => "Hostel renewal successful! Stay extended by $durationMsg.",
        "new_balance" => $newBalance,
        "renewal_date" => $newRenewalDate,
        "remaining_days" => $daysRemaining,
        "ref_id" => $refId,
        "vstudy_sync" => $vstudySyncResult
    ]);

} catch (Exception $e) {
    if (isset($db) && $db->inTransaction()) {
        $db->rollBack();
    }
    http_response_code(500);
    echo json_encode(["success" => false, "message" => "Renewal failed: " . $e->getMessage()]);
}
