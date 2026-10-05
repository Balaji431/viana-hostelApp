<?php
/**
 * vstudy.php - Single Unified Inbound Webhook Endpoint for VStudy -> VStay
 *
 * Implements VStudy Outbound Webhook Specification (Section 4):
 * 1. Validates x-client-id / x-client-secret headers
 * 2. Idempotent processing keyed on eventId (handles at-least-once deliveries)
 * 3. Handles all 6 eventTypes:
 *    - booking.paid
 *    - booking.renewed
 *    - booking.transferred
 *    - booking.cancelled
 *    - booking.released (lapsed bed freed)
 *    - booking.vacated (early vacation)
 * 4. Returns HTTP 200 {"received": true} on success
 */

header('Content-Type: application/json; charset=UTF-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, x-client-id, x-client-secret, X-Client-Id, X-Client-Secret');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    http_response_code(405);
    echo json_encode(['received' => false, 'error' => 'Method Not Allowed']);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/api_config.php';

// --- 1. VALIDATE HEADERS (x-client-id: vstudy & x-client-secret) ---
$headers = getallheaders();

// Normalize header lookups
$clientId = '';
$clientSecret = '';

foreach ($headers as $k => $v) {
    $lower = strtolower($k);
    if ($lower === 'x-client-id') {
        $clientId = trim($v);
    } elseif ($lower === 'x-client-secret') {
        $clientSecret = trim($v);
    }
}

if (empty($clientId) && !empty($_SERVER['HTTP_X_CLIENT_ID'])) {
    $clientId = trim($_SERVER['HTTP_X_CLIENT_ID']);
}
if (empty($clientSecret) && !empty($_SERVER['HTTP_X_CLIENT_SECRET'])) {
    $clientSecret = trim($_SERVER['HTTP_X_CLIENT_SECRET']);
}

$expectedSecret = defined('VSTUDY_CLIENT_SECRET') ? VSTUDY_CLIENT_SECRET : '';
$expectedApiKey = defined('VSTAAY_API_KEY') ? VSTAAY_API_KEY : '';
$configuredClientId = defined('VSTUDY_CLIENT_ID') ? strtolower(VSTUDY_CLIENT_ID) : '';

$validClientId = (!empty($clientId) && in_array(strtolower($clientId), array_filter(['vstudy', $configuredClientId])));
$validSecret = (!empty($clientSecret) && (
    (!empty($expectedSecret) && hash_equals($expectedSecret, $clientSecret)) || 
    (!empty($expectedApiKey) && hash_equals($expectedApiKey, $clientSecret))
));

if (!$validClientId || !$validSecret) {
    http_response_code(401);
    echo json_encode([
        'received' => false,
        'error'    => 'Unauthorized: Invalid x-client-id or x-client-secret'
    ]);
    exit();
}

// --- 2. PARSE BODY ---
$rawInput = file_get_contents('php://input');
$payload = json_decode($rawInput, true);

if (!is_array($payload) || empty($payload['eventId']) || empty($payload['eventType'])) {
    http_response_code(400);
    echo json_encode([
        'received' => false,
        'error'    => 'Bad Request: eventId and eventType are required'
    ]);
    exit();
}

$eventId    = trim($payload['eventId']);
$eventType  = trim($payload['eventType']);
$entityType = trim($payload['entityType'] ?? 'HOSTEL_BOOKING');
$entityId   = trim($payload['entityId'] ?? '');
$occurredAt = trim($payload['occurredAt'] ?? date('c'));
$data       = is_array($payload['data'] ?? null) ? $payload['data'] : [];

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    http_response_code(500);
    echo json_encode(['received' => false, 'error' => 'Database connection unavailable']);
    exit();
}

// Ensure deduplication table exists
$db->exec("
    CREATE TABLE IF NOT EXISTS vstudy_webhook_events (
        id INT AUTO_INCREMENT PRIMARY KEY,
        event_id VARCHAR(100) NOT NULL UNIQUE,
        event_type VARCHAR(100) NOT NULL,
        entity_type VARCHAR(100) DEFAULT 'HOSTEL_BOOKING',
        entity_id VARCHAR(100) NULL,
        roll_number VARCHAR(100) NULL,
        room_number VARCHAR(100) NULL,
        hostel_name VARCHAR(255) NULL,
        status VARCHAR(50) DEFAULT 'PROCESSED',
        occurred_at VARCHAR(100) NULL,
        payload LONGTEXT NULL,
        response LONGTEXT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_event_id (event_id),
        INDEX idx_event_type (event_type),
        INDEX idx_roll_number (roll_number)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
");

// --- 3. IDEMPOTENCY CHECK KEYED ON eventId ---
$stmtCheck = $db->prepare("SELECT id FROM vstudy_webhook_events WHERE event_id = ? LIMIT 1");
$stmtCheck->execute([$eventId]);
if ($stmtCheck->fetchColumn()) {
    // Event already processed previously (at-least-once delivery deduplication)
    http_response_code(200);
    echo json_encode([
        'received' => true,
        'replayed' => true,
        'eventId'  => $eventId
    ]);
    exit();
}

$rollNumber = trim($data['rollNumber'] ?? '');
// Support both legacy and new field names for room/hostel across all event types
$roomNumber = trim($data['newRoomNumber'] ?? $data['toRoomNumber'] ?? $data['roomNumber'] ?? '');
$hostelName = trim($data['newHostelName'] ?? $data['hostelName'] ?? '');
$applicationId = trim($data['applicationId'] ?? $entityId);

$ip = $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1';

try {
    $db->beginTransaction();

    switch ($eventType) {

        // =====================================================================
        // 1. booking.paid
        // =====================================================================
        case 'booking.paid':
            $totalFee = (float)($data['totalFee'] ?? 0.0);
            $status   = $data['status'] ?? 'PAID';

            if (!empty($rollNumber)) {
                // Update profile with room allocation
                $stmtProf = $db->prepare("
                    UPDATE profile 
                    SET room_allocation = ?, 
                        hostel_name = ?, 
                        valid_to = COALESCE(valid_to, DATE_ADD(CURRENT_DATE, INTERVAL 1 YEAR)),
                        renewal_date = COALESCE(renewal_date, DATE_ADD(CURRENT_DATE, INTERVAL 1 YEAR)),
                        remaining_days = GREATEST(365, COALESCE(remaining_days, 365))
                    WHERE reg_no = ?
                ");
                $stmtProf->execute([$roomNumber, $hostelName, $rollNumber]);

                // Sync vstudy_payments table
                $stmtPay = $db->prepare("
                    UPDATE vstudy_payments 
                    SET payment_status = 'PAID', 
                        application_status = 'ALLOCATED',
                        room_number = COALESCE(NULLIF(?, ''), room_number),
                        hostel_name = COALESCE(NULLIF(?, ''), hostel_name),
                        paid_amount = CASE WHEN ? > 0 THEN ? ELSE paid_amount END,
                        booking_id = COALESCE(NULLIF(?, ''), booking_id)
                    WHERE roll_number = ?
                ");
                $stmtPay->execute([$roomNumber, $hostelName, $totalFee, $totalFee, $applicationId, $rollNumber]);
            }
            break;

        // =====================================================================
        // 2. booking.renewed
        // =====================================================================
        case 'booking.renewed':
            $renewalId   = trim($data['renewalId'] ?? '');
            $renewalDate = trim($data['renewalDate'] ?? '');
            $months      = max(1, (int)($data['months'] ?? 12));
            $renewFee    = (float)($data['renewFee'] ?? 0.0);

            if (!empty($rollNumber)) {
                $days = 0;
                if (!empty($renewalDate)) {
                    $days = max(0, (int)round((strtotime($renewalDate) - time()) / 86400));
                }

                // Update profile renewal card
                if (!empty($renewalDate)) {
                    $db->prepare("
                        UPDATE profile 
                        SET renewal_date = ?, valid_to = ?, remaining_days = ?
                        WHERE reg_no = ?
                    ")->execute([$renewalDate, $renewalDate, $days, $rollNumber]);

                    // Update users DOL
                    $db->prepare("
                        UPDATE users SET DOL = ? WHERE username = ?
                    ")->execute([$renewalDate, $rollNumber]);

                    // Update vstudy_payments
                    $db->prepare("
                        UPDATE vstudy_payments SET renewal_date = ?, remaining_days = ? WHERE roll_number = ?
                    ")->execute([$renewalDate, $days, $rollNumber]);
                }

                // Append renewalId to renewal_requests if present
                if (!empty($renewalId)) {
                    $db->prepare("
                        UPDATE renewal_requests 
                        SET status = 'approved',
                            remarks = CONCAT(COALESCE(remarks, ''), ' | VStudy Renewal: ', ?)
                        WHERE student_reg_no = ? ORDER BY id DESC LIMIT 1
                    ")->execute([$renewalId, $rollNumber]);
                }

                // Record into vstudy_renewal_syncs
                $db->prepare("
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
                        sync_status = VALUES(sync_status)
                ")->execute([
                    ':external_event_id'      => $eventId,
                    ':roll_number'             => $rollNumber,
                    ':student_name'            => null,
                    ':renewal_id'              => $renewalId ?: null,
                    ':application_id'          => $applicationId ?: null,
                    ':months'                  => $months,
                    ':amount'                  => $renewFee,
                    ':room_rent'               => round($renewFee * 0.70, 2),
                    ':food'                    => round($renewFee * 0.30, 2),
                    ':premium_multiplier'      => 1.0,
                    ':previous_renewal_date'   => null,
                    ':new_renewal_date'        => $renewalDate ?: null,
                    ':status'                  => 'PAID',
                    ':sync_status'             => 'synced',
                    ':replayed'                => 0,
                    ':request_payload'         => json_encode($data),
                    ':response_payload'        => json_encode(['received' => true])
                ]);
            }
            break;

        // =====================================================================
        // 3. booking.transferred
        // =====================================================================
        case 'booking.transferred':
            // VStudy sends newRoomNumber / newHostelName (also support legacy toRoomNumber)
            $fromRoomNumber  = trim($data['fromRoomNumber'] ?? $data['oldRoomNumber'] ?? '');
            $toRoomNumber    = trim($data['newRoomNumber'] ?? $data['toRoomNumber'] ?? $data['roomNumber'] ?? '');
            $toHostelName    = trim($data['newHostelName'] ?? $data['hostelName'] ?? $hostelName);
            $transferReqId   = trim($data['transferRequestId'] ?? '');

            if (!empty($rollNumber) && !empty($toRoomNumber)) {
                // 3a. Update profile room allocation + hostel
                $db->prepare("
                    UPDATE profile 
                    SET room_allocation = ?, 
                        hostel_name = COALESCE(NULLIF(?, ''), hostel_name)
                    WHERE reg_no = ?
                ")->execute([$toRoomNumber, $toHostelName, $rollNumber]);

                // 3b. Update users table RoomId + HostelName
                $db->prepare("
                    UPDATE users 
                    SET RoomId      = ?,
                        HostelName  = COALESCE(NULLIF(?, ''), HostelName)
                    WHERE username = ? OR RegisterNumber = ?
                ")->execute([$toRoomNumber, $toHostelName, $rollNumber, $rollNumber]);

                // 3c. Update vstudy_payments
                $db->prepare("
                    UPDATE vstudy_payments 
                    SET room_number = ?, 
                        hostel_name = COALESCE(NULLIF(?, ''), hostel_name)
                    WHERE roll_number = ?
                ")->execute([$toRoomNumber, $toHostelName, $rollNumber]);

                // 3d. Update room_master + rooms_groups_details bed counts:
                //     Decrement old room (if known), increment new room
                if (!empty($fromRoomNumber)) {
                    $db->prepare("
                        UPDATE room_master 
                        SET occupied_beds   = GREATEST(0, occupied_beds - 1),
                            available_beds  = LEAST(total_beds, available_beds + 1)
                        WHERE room_code = ?
                    ")->execute([$fromRoomNumber]);

                    $db->prepare("
                        UPDATE rooms_groups_details 
                        SET occupied_beds   = GREATEST(0, occupied_beds - 1),
                            available_beds  = LEAST(total_beds, available_beds + 1)
                        WHERE room_number = ?
                    ")->execute([$fromRoomNumber]);
                }
                $db->prepare("
                    UPDATE room_master 
                    SET occupied_beds   = LEAST(total_beds, occupied_beds + 1),
                        available_beds  = GREATEST(0, available_beds - 1)
                    WHERE room_code = ?
                ")->execute([$toRoomNumber]);

                $db->prepare("
                    UPDATE rooms_groups_details 
                    SET occupied_beds   = LEAST(total_beds, occupied_beds + 1),
                        available_beds  = GREATEST(0, available_beds - 1)
                    WHERE room_number = ?
                ")->execute([$toRoomNumber]);

                // 3e. Mark any pending room_change_requests as approved
                try {
                    $db->prepare("
                        UPDATE room_change_requests 
                        SET status = 'approved',
                            remarks = CONCAT(COALESCE(remarks, ''), ' | Transferred to ', ?, ' (ReqID: ', ?, ')')
                        WHERE student_reg_no = ? AND status = 'pending'
                    ")->execute([$toRoomNumber, $transferReqId, $rollNumber]);
                } catch (Exception $ign) {}
            }
            break;

        // =====================================================================
        // 4. booking.cancelled
        // =====================================================================
        case 'booking.cancelled':
            if (!empty($rollNumber)) {
                // Look up current room BEFORE clearing (payload may not include it)
                $stmtCurrRoom = $db->prepare("SELECT room_allocation, hostel_name FROM profile WHERE reg_no = ? LIMIT 1");
                $stmtCurrRoom->execute([$rollNumber]);
                $currRow = $stmtCurrRoom->fetch(PDO::FETCH_ASSOC);
                $currRoom = $currRow['room_allocation'] ?? '';

                // Decrement room counts if student had a room
                if (!empty($currRoom)) {
                    $db->prepare("
                        UPDATE room_master 
                        SET occupied_beds  = GREATEST(0, occupied_beds - 1),
                            available_beds = LEAST(total_beds, available_beds + 1)
                        WHERE room_code = ?
                    ")->execute([$currRoom]);
                    $db->prepare("
                        UPDATE rooms_groups_details 
                        SET occupied_beds  = GREATEST(0, occupied_beds - 1),
                            available_beds = LEAST(total_beds, available_beds + 1)
                        WHERE room_number = ?
                    ")->execute([$currRoom]);
                }

                $db->prepare("
                    UPDATE vstudy_payments 
                    SET payment_status = 'CANCELLED', application_status = 'CANCELLED'
                    WHERE roll_number = ?
                ")->execute([$rollNumber]);

                // Clear room allocation + users room
                $db->prepare("
                    UPDATE profile 
                    SET room_allocation = NULL 
                    WHERE reg_no = ? AND room_allocation IS NOT NULL
                ")->execute([$rollNumber]);

                $db->prepare("
                    UPDATE users SET RoomId = NULL, RoomSharing = NULL
                    WHERE username = ? OR RegisterNumber = ?
                ")->execute([$rollNumber, $rollNumber]);
            }
            break;

        // =====================================================================
        // 5. booking.released (Nightly cron frees lapsed bed)
        // =====================================================================
        case 'booking.released':
            if (!empty($rollNumber)) {
                // Look up current room BEFORE clearing (payload may not include roomNumber)
                $stmtCurrRoom = $db->prepare("SELECT room_allocation, hostel_name FROM profile WHERE reg_no = ? LIMIT 1");
                $stmtCurrRoom->execute([$rollNumber]);
                $currRow = $stmtCurrRoom->fetch(PDO::FETCH_ASSOC);
                $currRoom = !empty($roomNumber) ? $roomNumber : ($currRow['room_allocation'] ?? '');
                $currHostel = !empty($hostelName) ? $hostelName : ($currRow['hostel_name'] ?? '');

                // Decrement room counts
                if (!empty($currRoom)) {
                    $db->prepare("
                        UPDATE room_master 
                        SET occupied_beds  = GREATEST(0, occupied_beds - 1),
                            available_beds = LEAST(total_beds, available_beds + 1)
                        WHERE room_code = ?
                    ")->execute([$currRoom]);
                    $db->prepare("
                        UPDATE rooms_groups_details 
                        SET occupied_beds  = GREATEST(0, occupied_beds - 1),
                            available_beds = LEAST(total_beds, available_beds + 1)
                        WHERE room_number = ?
                    ")->execute([$currRoom]);
                }

                $db->prepare("
                    UPDATE profile 
                    SET room_allocation = NULL, remaining_days = 0 
                    WHERE reg_no = ?
                ")->execute([$rollNumber]);

                // Clear users room
                $db->prepare("
                    UPDATE users SET RoomId = NULL, RoomSharing = NULL
                    WHERE username = ? OR RegisterNumber = ?
                ")->execute([$rollNumber, $rollNumber]);

                $db->prepare("
                    UPDATE vstudy_payments 
                    SET payment_status = 'EXPIRED', application_status = 'EXPIRED', remaining_days = 0 
                    WHERE roll_number = ?
                ")->execute([$rollNumber]);

                // Record checkout student entry
                try {
                    $db->prepare("
                        INSERT INTO checkout_students (reg_no, room_number, hostel_name, checkout_reason, checkout_date)
                        VALUES (?, ?, ?, 'renewal_lapsed', NOW())
                    ")->execute([$rollNumber, $currRoom, $currHostel]);
                } catch (Exception $ign) {}
            }
            break;

        // =====================================================================
        // 6. booking.vacated (Early vacation approved)
        // =====================================================================
        case 'booking.vacated':
            if (!empty($rollNumber)) {
                // Look up current room BEFORE clearing (booking.vacated payload has no roomNumber)
                $stmtCurrRoom = $db->prepare("SELECT room_allocation, hostel_name FROM profile WHERE reg_no = ? LIMIT 1");
                $stmtCurrRoom->execute([$rollNumber]);
                $currRow = $stmtCurrRoom->fetch(PDO::FETCH_ASSOC);
                $currRoom = !empty($roomNumber) ? $roomNumber : ($currRow['room_allocation'] ?? '');
                $currHostel = !empty($hostelName) ? $hostelName : ($currRow['hostel_name'] ?? '');

                // Decrement room counts
                if (!empty($currRoom)) {
                    $db->prepare("
                        UPDATE room_master 
                        SET occupied_beds  = GREATEST(0, occupied_beds - 1),
                            available_beds = LEAST(total_beds, available_beds + 1)
                        WHERE room_code = ?
                    ")->execute([$currRoom]);
                    $db->prepare("
                        UPDATE rooms_groups_details 
                        SET occupied_beds  = GREATEST(0, occupied_beds - 1),
                            available_beds = LEAST(total_beds, available_beds + 1)
                        WHERE room_number = ?
                    ")->execute([$currRoom]);
                }

                $db->prepare("
                    UPDATE profile 
                    SET room_allocation = NULL, remaining_days = 0 
                    WHERE reg_no = ?
                ")->execute([$rollNumber]);

                // Clear users room
                $db->prepare("
                    UPDATE users SET RoomId = NULL, RoomSharing = NULL
                    WHERE username = ? OR RegisterNumber = ?
                ")->execute([$rollNumber, $rollNumber]);

                $db->prepare("
                    UPDATE vstudy_payments 
                    SET payment_status = 'EXPIRED', application_status = 'VACATED', remaining_days = 0 
                    WHERE roll_number = ?
                ")->execute([$rollNumber]);

                // Record vacate checkout
                try {
                    $db->prepare("
                        INSERT INTO checkout_students (reg_no, room_number, hostel_name, checkout_reason, checkout_date)
                        VALUES (?, ?, ?, 'vacated', NOW())
                    ")->execute([$rollNumber, $currRoom, $currHostel]);
                } catch (Exception $ign) {}

                // Mark pending vacate requests as approved
                try {
                    $db->prepare("
                        UPDATE vacate_requests 
                        SET status = 'approved', remarks = 'Early vacation approved via VStudy webhook'
                        WHERE reg_no = ? AND status = 'pending'
                    ")->execute([$rollNumber]);
                } catch (Exception $ign) {}
            }
            break;

        // =====================================================================
        // 6b. booking.renewal_date_changed / booking.date_changed
        // =====================================================================
        case 'booking.renewal_date_changed':
        case 'booking.date_changed':
        case 'booking.renewal_date_update':
            $newDate = trim($data['renewalDate'] ?? $data['newRenewalDate'] ?? $data['renewal_date'] ?? $data['valid_to'] ?? '');
            if (!empty($rollNumber) && !empty($newDate)) {
                $days = max(0, (int)round((strtotime($newDate) - time()) / 86400));
                $db->prepare("UPDATE profile SET renewal_date = ?, valid_to = ?, remaining_days = ? WHERE reg_no = ?")->execute([$newDate, $newDate, $days, $rollNumber]);
                $db->prepare("UPDATE users SET DOL = ? WHERE username = ? OR RegisterNumber = ?")->execute([$newDate, $rollNumber, $rollNumber]);
                $db->prepare("UPDATE vstudy_payments SET renewal_date = ?, remaining_days = ? WHERE roll_number = ?")->execute([$newDate, $days, $rollNumber]);
            }
            break;

        // =====================================================================
        // 7. booking.short_stay / short_stay (Temporary / Guest stay booking)
        // =====================================================================
        case 'booking.short_stay':
        case 'short_stay':
            $ssRoll = !empty($rollNumber) ? $rollNumber : ($data['rollNumber'] ?? '');
            $ssRoom = !empty($roomNumber) ? $roomNumber : ($data['roomNumber'] ?? '');
            $ssHostel = !empty($hostelName) ? $hostelName : ($data['hostelName'] ?? '');
            $checkIn = !empty($data['checkIn']) ? date('Y-m-d', strtotime($data['checkIn'])) : date('Y-m-d');
            $checkOut = !empty($data['checkOut']) ? date('Y-m-d', strtotime($data['checkOut'])) : date('Y-m-d', strtotime('+1 day'));
            $totalAmount = (float)($data['total'] ?? 0);
            $bookingId = $data['bookingId'] ?? $eventId;
            $nights = (int)($data['nights'] ?? 1);

            if (!empty($ssRoll) && !empty($ssRoom)) {
                // 1. Ensure user exists
                $stmtU = $db->prepare("SELECT id, full_name, email FROM users WHERE username = ? OR RegisterNumber = ? LIMIT 1");
                $stmtU->execute([$ssRoll, $ssRoll]);
                $uRow = $stmtU->fetch(PDO::FETCH_ASSOC);

                $userName = $uRow['full_name'] ?? ($data['studentName'] ?? 'Guest Student');
                $userEmail = $uRow['email'] ?? ($data['email'] ?? ($ssRoll . '@saveetha.com'));

                // 2. Insert or update temporary_stay_requests
                $reqId = 'SS-' . strtoupper(substr(md5($bookingId), 0, 8));
                try {
                    $stmtSS = $db->prepare("
                        INSERT INTO temporary_stay_requests (
                            request_id, full_name, email, phone, gender,
                            institution_purpose, doc_type, doc_number,
                            hostel_name, room_type, room_no, room_code,
                            from_date, to_date, duration_type, duration_value,
                            amount, status, payment_status, payment_txn_id, hold_status
                        ) VALUES (
                            ?, ?, ?, ?, 'General',
                            'Short Stay Booking from VStudy', 'RollNumber', ?,
                            ?, 'Standard AC', ?, ?,
                            ?, ?, 'days', ?,
                            ?, 'allocated', 'paid', ?, 'confirmed'
                        ) ON DUPLICATE KEY UPDATE 
                            room_no = VALUES(room_no),
                            room_code = VALUES(room_code),
                            hostel_name = VALUES(hostel_name),
                            from_date = VALUES(from_date),
                            to_date = VALUES(to_date),
                            amount = VALUES(amount),
                            status = 'allocated',
                            payment_status = 'paid',
                            hold_status = 'confirmed'
                    ");
                    $stmtSS->execute([
                        $reqId, $userName, $userEmail, '',
                        $ssRoll, $ssHostel, $ssRoom, $ssRoom,
                        $checkIn, $checkOut, $nights,
                        $totalAmount, $bookingId
                    ]);
                } catch (Exception $eReq) {}

                // 3. Decrement available room count in room_master & rooms_groups_details
                try {
                    $db->prepare("
                        UPDATE room_master 
                        SET occupied_beds  = occupied_beds + 1,
                            available_beds = GREATEST(0, available_beds - 1)
                        WHERE room_code = ? OR room_no = ?
                    ")->execute([$ssRoom, $ssRoom]);
                    $db->prepare("
                        UPDATE rooms_groups_details 
                        SET occupied_beds  = occupied_beds + 1,
                            available_beds = GREATEST(0, available_beds - 1)
                        WHERE room_number = ?
                    ")->execute([$ssRoom]);
                } catch (Exception $eRoom) {}

                // 4. Update user RoomId
                try {
                    $db->prepare("
                        UPDATE users 
                        SET RoomId = ?, HostelName = ?, role = COALESCE(NULLIF(role,''), 'guest'), Status = '1', is_active = 1
                        WHERE username = ? OR RegisterNumber = ?
                    ")->execute([$ssRoom, $ssHostel, $ssRoll, $ssRoll]);
                } catch (Exception $eUser) {}

                // 5. Update profile table
                try {
                    $db->prepare("
                        INSERT INTO profile (
                            full_name, reg_no, email, room_allocation, hostel_name,
                            valid_from, valid_to, remaining_days
                        ) VALUES (
                            ?, ?, ?, ?, ?,
                            ?, ?, ?
                        ) ON DUPLICATE KEY UPDATE 
                            room_allocation = VALUES(room_allocation),
                            hostel_name = VALUES(hostel_name),
                            valid_from = VALUES(valid_from),
                            valid_to = VALUES(valid_to),
                            remaining_days = VALUES(remaining_days)
                    ")->execute([
                        $userName, $ssRoll, $userEmail, $ssRoom, $ssHostel,
                        $checkIn, $checkOut, $nights
                    ]);
                } catch (Exception $eProf) {}
            }
            break;

        default:
            // Unknown event type - log and ignore
            break;
    }

    // Record processed event in deduplication table
    $stmtInsEvent = $db->prepare("
        INSERT INTO vstudy_webhook_events (
            event_id, event_type, entity_type, entity_id,
            roll_number, room_number, hostel_name, status,
            occurred_at, payload, response
        ) VALUES (
            ?, ?, ?, ?,
            ?, ?, ?, 'PROCESSED',
            ?, ?, ?
        )
    ");
    $stmtInsEvent->execute([
        $eventId,
        $eventType,
        $entityType,
        $entityId,
        $rollNumber,
        $roomNumber,
        $hostelName,
        $occurredAt,
        $rawInput,
        json_encode(['received' => true])
    ]);

    // Record audit log
    try {
        $stmtAudit = $db->prepare("
            INSERT INTO audit_logs (username, role, action, module_name, new_value, ip_address)
            VALUES (?, 'vstudy_webhook', ?, 'vstudy_webhook', ?, ?)
        ");
        $stmtAudit->execute([
            $rollNumber ?: 'vstudy',
            'WEBHOOK_' . strtoupper(str_replace('.', '_', $eventType)),
            json_encode(['eventId' => $eventId, 'data' => $data]),
            $ip
        ]);
    } catch (Exception $audErr) {}

    $db->commit();

    // Success response: HTTP 200 {"received": true}
    http_response_code(200);
    echo json_encode(['received' => true]);

} catch (Exception $e) {
    if (isset($db) && $db->inTransaction()) {
        $db->rollBack();
    }
    http_response_code(500);
    echo json_encode([
        'received' => false,
        'error'    => 'Failed to process webhook: ' . $e->getMessage()
    ]);
}
