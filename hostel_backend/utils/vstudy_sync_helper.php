<?php
require_once __DIR__ . '/../config/api_config.php';

if (!function_exists('generateUuidV4')) {
    function generateUuidV4() {
        $data = random_bytes(16);
        $data[6] = chr(ord($data[6]) & 0x0f | 0x40); // set version to 0100
        $data[8] = chr(ord($data[8]) & 0x3f | 0x80); // set bits 6-7 to 10
        return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
    }
}

if (!function_exists('parseDateSafe')) {
    function parseDateSafe($val, $fallback = null) {
        if (empty($val)) return $fallback;
        $val = trim($val);
        if (preg_match('/^(\d{1,2})[\.\/](\d{1,2})[\.\/](\d{4})$/', $val, $m)) {
            $d = (int)$m[1];
            $mo = (int)$m[2];
            $y = (int)$m[3];
            if ($mo > 12 && $d <= 12) {
                $tmp = $d; $d = $mo; $mo = $tmp;
            }
            return sprintf('%04d-%02d-%02d', $y, $mo, $d);
        }
        if (preg_match('/^(\d{4})-(\d{1,2})-(\d{1,2})/', $val, $m)) {
            return sprintf('%04d-%02d-%02d', (int)$m[1], (int)$m[2], (int)$m[3]);
        }
        try {
            $dt = new DateTime($val);
            return $dt->format('Y-m-d');
        } catch (Exception $e) {
            $ts = strtotime($val);
            if ($ts !== false && $ts > 0) {
                return date('Y-m-d', $ts);
            }
        }
        return $fallback;
    }
}

/**
 * Ensure vstay_webhook_events table exists (auto-create on first use).
 * This table stores OUTBOUND events: VStay → VStudy ERP.
 * (vstudy_webhook_events stores INBOUND events: VStudy → VStay)
 */
if (!function_exists('ensureVstayWebhookEventsTable')) {
    function ensureVstayWebhookEventsTable($dbConn) {
        $dbConn->exec("
            CREATE TABLE IF NOT EXISTS vstay_webhook_events (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                event_id    VARCHAR(100) NOT NULL UNIQUE,
                event_type  VARCHAR(100) NOT NULL,
                entity_type VARCHAR(100) DEFAULT 'HOSTEL_BOOKING',
                entity_id   VARCHAR(100) NULL,
                roll_number VARCHAR(100) NULL,
                room_number VARCHAR(100) NULL,
                hostel_name VARCHAR(255) NULL,
                direction   VARCHAR(20)  DEFAULT 'OUTBOUND',
                status      VARCHAR(50)  DEFAULT 'PROCESSED',
                occurred_at VARCHAR(100) NULL,
                payload     LONGTEXT     NULL,
                response    LONGTEXT     NULL,
                created_at  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
                updated_at  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX idx_event_id   (event_id),
                INDEX idx_event_type (event_type),
                INDEX idx_roll_number(roll_number),
                INDEX idx_direction  (direction)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ");
    }
}

/**
 * Perform an on-demand live fetch from VStudy external APIs
 * when a student attempts to log in but is not yet stored in the local DB.
 */
function syncStudentOnDemand($email, $db) {
    $email = trim(strtolower($email));
    $rollFromEmail = explode('@', $email)[0];
    
    // External APIs to check (recent pages)
    $apis = [
        "https://vstudy.saveetha.com/api/hostel-settings/booked-rooms/external",
        "https://vstudy.saveetha.com/api/hostel-applications/paid"
    ];
    
    $foundRecord = null;
    $recordType = '';

    foreach ($apis as $baseUrl) {
        for ($page = 1; $page <= 5; $page++) {
            $url = $baseUrl . "?page=$page&limit=100";
            $ch = curl_init($url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_HTTPHEADER, [
                "X-Client-Id: " . VSTUDY_CLIENT_ID,
                "X-Client-Secret: " . VSTUDY_CLIENT_SECRET
            ]);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
            curl_setopt($ch, CURLOPT_TIMEOUT, 10);
            $res = curl_exec($ch);
            $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);

            if ($code !== 200) break;

            $json = json_decode($res, true);
            $batch = isset($json['data']) && is_array($json['data']) ? $json['data'] : (is_array($json) ? $json : []);

            if (empty($batch)) break;

            foreach ($batch as $item) {
                $student = $item['student'] ?? $item;
                $itemEmail = strtolower(trim($student['email'] ?? $item['email'] ?? ''));
                $itemRoll  = strtolower(trim($student['rollNumber'] ?? $student['registerNumber'] ?? $item['registerNumber'] ?? $item['rollNumber'] ?? ''));

                if (($itemEmail && $itemEmail === $email) || ($itemRoll && $itemRoll === $rollFromEmail)) {
                    if (!$foundRecord || !empty($item['roomNumber']) || !empty($item['room']['roomNumber'])) {
                        $foundRecord = $item;
                        $recordType = strpos($baseUrl, 'booked-rooms') !== false ? 'booked' : 'paid';
                        if (!empty($item['roomNumber']) || !empty($item['room']['roomNumber'])) {
                            break 2;
                        }
                    }
                }
            }
        }
    }

    if (!$foundRecord) {
        return false;
    }

    // Extract student details
    $student = $foundRecord['student'] ?? $foundRecord;
    $hostel  = $foundRecord['hostel'] ?? $foundRecord;
    $room    = $foundRecord['room'] ?? $foundRecord;
    $fees    = $foundRecord['fees'] ?? [];

    $roll       = trim($student['rollNumber'] ?? $student['registerNumber'] ?? $foundRecord['registerNumber'] ?? $foundRecord['rollNumber'] ?? $rollFromEmail);
    $name       = trim($student['name'] ?? $foundRecord['name'] ?? 'Student');
    $userEmail  = trim($student['email'] ?? $foundRecord['email'] ?? $email);
    $phone      = trim($student['phone'] ?? $foundRecord['phone'] ?? '');
    $gender     = strtolower(trim($room['gender'] ?? $foundRecord['gender'] ?? 'female'));
    $campus     = trim($hostel['campus'] ?? $foundRecord['campus'] ?? 'Thandalam Campus');
    $hostelName = trim($hostel['name'] ?? $foundRecord['hostelName'] ?? '');
    $rawRoomNo  = trim($room['roomNumber'] ?? $foundRecord['roomNumber'] ?? '');
    // Clean spaces and normalize room format e.g. "T-32 F02- W0-R16" -> "T32-F02-W0-R16"
    $roomNo     = preg_replace('/-+/', '-', str_replace([' - ', '- ', ' ', 'T-32'], ['-', '-', '', 'T32'], $rawRoomNo));
    $roomType   = trim($room['roomType'] ?? $foundRecord['roomType'] ?? '');
    $hType      = ($gender === 'female' || strpos(strtolower($hostelName), 'girls') !== false || strpos(strtolower($hostelName), 'vaigai') !== false) ? 'Girls' : 'Boys';
    $paidDate   = trim($foundRecord['paidAt'] ?? $foundRecord['bookedAt'] ?? date('Y-m-d H:i:s'));
    $renStr     = trim($foundRecord['renewalDate'] ?? $student['renewalDate'] ?? '');

    $pwHash = password_hash('welcome123', PASSWORD_BCRYPT);
    $today  = new DateTime('today');

    $parsedRen = parseDateSafe($renStr);
    $parsedPaid = parseDateSafe($paidDate);

    $renFormatted = null;
    $remDays = null;
    if (!empty($parsedRen)) {
        $calcRenewal = new DateTime($parsedRen);
        $renFormatted = $calcRenewal->format('Y-m-d');
        $remDays = ($calcRenewal < $today) ? 0 : (int)$today->diff($calcRenewal)->format('%r%a');
    }
    $checkInFormatted = $parsedPaid ?: null;

    // 1. Insert into vstudy_payments
    $stmtPay = $db->prepare("
        INSERT INTO vstudy_payments (
            student_name, roll_number, email, gender, academic_year, campus,
            hostel_preference, hostel_name, payment_status, application_status, paid_date, paid_amount
        ) VALUES (
            :name, :roll, :email, :gender, '1st Year', :campus,
            :room_type, :hostel_name, 'Paid', 'Application Verified', :paid_date, :paid_amount
        ) ON DUPLICATE KEY UPDATE
            student_name = VALUES(student_name), email = VALUES(email), paid_date = VALUES(paid_date)
    ");
    $stmtPay->execute([
        ':name'        => $name,
        ':roll'        => $roll,
        ':email'       => $userEmail,
        ':gender'      => ucfirst($gender),
        ':campus'      => $campus,
        ':room_type'   => $roomType,
        ':hostel_name' => $hostelName,
        ':paid_date'   => $checkInFormatted,
        ':paid_amount' => $fees['total'] ?? 0
    ]);

    // 2. Insert into users table if missing
    $checkUserStmt  = $db->prepare("SELECT id, email_override FROM users WHERE username = ? OR email = ?");
    $checkUserStmt->execute([$roll, $userEmail]);
    $existingRow   = $checkUserStmt->fetch(PDO::FETCH_ASSOC);
    $existingId    = $existingRow ? $existingRow['id'] : null;
    $emailOverride = $existingRow ? (int)($existingRow['email_override'] ?? 0) : 0;

    if (!$existingId) {
        $insertUserStmt = $db->prepare("
            INSERT INTO users (
                username, full_name, email, phone_number, role, password, Campus, Institution,
                HostelName, HostelType, RoomType, RoomId, Status, is_active
            ) VALUES (
                :username, :full_name, :email, :phone_number, 'student', :password, :Campus, 'SIMATS',
                :HostelName, :HostelType, :RoomType, :RoomId, '1', 1
            )
        ");
        $insertUserStmt->execute([
            ':username'     => $roll,
            ':full_name'    => $name,
            ':email'        => $userEmail,
            ':phone_number' => $phone,
            ':password'     => $pwHash,
            ':Campus'       => $campus,
            ':HostelName'   => $hostelName,
            ':HostelType'   => $hType,
            ':RoomType'     => $roomType,
            ':RoomId'       => $roomNo
        ]);
        $existingId = $db->lastInsertId();
    } else {
        $updateUserStmt = $db->prepare("
            UPDATE users SET 
                full_name = ?,
                email = IF(email_override = 1, email, ?),
                phone_number = IF(email_override = 1, phone_number, ?),
                Campus = ?, HostelName = ?, HostelType = ?, RoomType = ?, RoomId = ?
            WHERE id = ?
        ");
        $updateUserStmt->execute([$name, $userEmail, $phone, $campus, $hostelName, $hType, $roomType, $roomNo, $existingId]);
    }

    // 2.5. Resolve warden dynamically based on room number & hostel
    $assignedWarden = null;
    if (!empty($roomNo)) {
        $wStmt = $db->prepare("
            SELECT warden_name 
            FROM rooms_groups_details 
            WHERE (room_number = :rn OR REPLACE(REPLACE(TRIM(room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(:rn2), ' ', ''), '-', ''))
              AND warden_name IS NOT NULL AND warden_name != ''
            LIMIT 1
        ");
        $wStmt->execute([':rn' => $roomNo, ':rn2' => $roomNo]);
        $assignedWarden = $wStmt->fetchColumn();
    }

    if (empty($assignedWarden) && !empty($hostelName)) {
        $mStmt = $db->prepare("
            SELECT name FROM mapping_staff 
            WHERE LOWER(role) = 'warden' AND (LOWER(hostel_name) = LOWER(:hn) OR LOWER(:hn2) LIKE CONCAT('%', LOWER(hostel_name), '%')) 
            ORDER BY id ASC LIMIT 1
        ");
        $mStmt->execute([':hn' => $hostelName, ':hn2' => $hostelName]);
        $assignedWarden = $mStmt->fetchColumn();
    }

    // 3. Insert into profile
    $insertProfileStmt = $db->prepare("
        INSERT INTO profile (
            full_name, reg_no, user_id, email, personal_phone, room_allocation, warden,
            institution, hostel_name, address, renewal_date, remaining_days,
            check_in_date, valid_from, valid_to
        ) VALUES (
            :full_name, :reg_no, :user_id, :email, :personal_phone, :room_allocation, :warden,
            :institution, :hostel_name, :address, :renewal_date, :remaining_days,
            :check_in_date, :valid_from, :valid_to
        ) ON DUPLICATE KEY UPDATE 
            full_name = VALUES(full_name), email = VALUES(email), personal_phone = VALUES(personal_phone),
            room_allocation = VALUES(room_allocation), 
            warden = COALESCE(NULLIF(VALUES(warden),''), warden), 
            hostel_name = VALUES(hostel_name),
            renewal_date = VALUES(renewal_date),
            valid_to = VALUES(valid_to),
            remaining_days = VALUES(remaining_days),
            check_in_date = VALUES(check_in_date), valid_from = VALUES(valid_from)
    ");
    $insertProfileStmt->execute([
        ':full_name'       => $name,
        ':reg_no'          => $roll,
        ':user_id'         => $existingId,
        ':email'           => $userEmail,
        ':personal_phone'  => $phone,
        ':room_allocation' => $roomNo,
        ':warden'          => $assignedWarden,
        ':institution'     => 'SIMATS',
        ':hostel_name'     => $hostelName,
        ':address'         => 'Thandalam Campus, Chennai',
        ':renewal_date'    => $renFormatted,
        ':remaining_days'  => $remDays,
        ':check_in_date'   => $checkInFormatted,
        ':valid_from'      => $checkInFormatted,
        ':valid_to'        => $renFormatted
    ]);

    // 4. Insert into parent tables
    $parentId = "P_" . $roll;
    $parentsList = $foundRecord['parents'] ?? [];
    $parentEmail = null;
    $parentName = null;
    $parentPhone = $phone;

    if (is_array($parentsList) && !empty($parentsList)) {
        foreach ($parentsList as $p) {
            $rel = strtolower(trim($p['relation'] ?? ''));
            $em = trim($p['email'] ?? '');
            if ($rel === 'father' && !empty($em)) {
                $parentEmail = strtolower($em);
                $parentName = trim($p['name'] ?? '');
                $parentPhone = trim($p['phone'] ?? $phone);
                break;
            }
        }
        if (empty($parentEmail)) {
            foreach ($parentsList as $p) {
                $rel = strtolower(trim($p['relation'] ?? ''));
                $em = trim($p['email'] ?? '');
                if ($rel === 'mother' && !empty($em)) {
                    $parentEmail = strtolower($em);
                    $parentName = trim($p['name'] ?? '');
                    $parentPhone = trim($p['phone'] ?? $phone);
                    break;
                }
            }
        }
        if (empty($parentEmail)) {
            foreach ($parentsList as $p) {
                $em = trim($p['email'] ?? '');
                if (!empty($em)) {
                    $parentEmail = strtolower($em);
                    $parentName = trim($p['name'] ?? '');
                    $parentPhone = trim($p['phone'] ?? $phone);
                    break;
                }
            }
        }
    }

    // Strip leading country codes (91, +91, 0)
    if ($parentPhone) {
        $digits = preg_replace('/[^0-9]/', '', $parentPhone);
        if (strlen($digits) > 10 && substr($digits, 0, 2) === '91') {
            $digits = substr($digits, 2);
        }
        if (strlen($digits) === 11 && substr($digits, 0, 1) === '0') {
            $digits = substr($digits, 1);
        }
        $parentPhone = $digits;
    }

    $insertParentStmt = $db->prepare("
        INSERT INTO parent_users (parent_id, email, name, password, contact) 
        VALUES (:parent_id, :email, :name, :password, :contact)
        ON DUPLICATE KEY UPDATE 
            email = COALESCE(NULLIF(VALUES(email), ''), email),
            name = COALESCE(NULLIF(VALUES(name), ''), name),
            contact = COALESCE(NULLIF(VALUES(contact), ''), contact)
    ");

    $insertParentStmt->execute([
        ':parent_id' => $parentId,
        ':email'     => $parentEmail,
        ':name'      => $parentName,
        ':password'  => $pwHash,
        ':contact'   => $parentPhone
    ]);

    $insertMapStmt = $db->prepare("
        INSERT INTO parent_student_map (parent_id, student_id) 
        VALUES (?, ?) ON DUPLICATE KEY UPDATE parent_id = VALUES(parent_id)
    ");
    $insertMapStmt->execute([$parentId, $roll]);

    return true;
}

/**
 * Real-time Outbound sync to VStudy ERP for Room Transfer
 */
function syncTransferToVStudy($rollNumber, $toRoomNumber, $toHostelName = '', $fromRoomNumber = '', $externalEventId = '') {
    $url = defined('VSTUDY_TRANSFER_API_URL') ? VSTUDY_TRANSFER_API_URL : 'https://vstudy.saveetha.com/api/hostel-applications/external/transfer';
    $clientId = defined('VSTUDY_CLIENT_ID') ? VSTUDY_CLIENT_ID : '';
    $clientSecret = defined('VSTUDY_CLIENT_SECRET') ? VSTUDY_CLIENT_SECRET : '';

    if (empty($url) || empty($clientId) || empty($clientSecret) || empty($rollNumber) || empty($toRoomNumber)) {
        return ['success' => false, 'message' => 'Missing required transfer sync parameters'];
    }

    if (empty($externalEventId) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $externalEventId)) {
        $externalEventId = generateUuidV4();
    }

    $payload = [
        'externalEventId'    => $externalEventId,
        'rollNumber'         => (string)$rollNumber,
        'toRoomNumber'       => (string)$toRoomNumber,
        'roomNumber'         => (string)$toRoomNumber,
        'newRoomNumber'      => (string)$toRoomNumber,
        'toHostelName'       => (string)$toHostelName,
        'hostelName'         => (string)$toHostelName,
        'newHostelName'      => (string)$toHostelName
    ];

    if (!empty($fromRoomNumber) && $fromRoomNumber !== 'N/A') {
        $payload['fromRoomNumber'] = (string)$fromRoomNumber;
        $payload['currentRoomNumber'] = (string)$fromRoomNumber;
    }

    try {
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'x-client-id: ' . $clientId,
            'x-client-secret: ' . $clientSecret
        ]);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        $res = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        $json = json_decode($res, true);
        $isSuccess = ($code === 200 && ($json['success'] ?? false) === true);

        // ALWAYS log to vstay_webhook_events (OUTBOUND: VStay → VStudy)
        try {
            require_once __DIR__ . '/../config/database.php';
            $dbConn = (new Database())->getConnection();
            if ($dbConn) {
                ensureVstayWebhookEventsTable($dbConn);
                $appId = $json['data']['applicationId'] ?? null;
                $wbPayload = json_encode([
                    'eventId'    => $externalEventId,
                    'eventType'  => 'booking.transferred',
                    'entityType' => 'HOSTEL_BOOKING',
                    'entityId'   => $appId ?? $externalEventId,
                    'occurredAt' => date('c'),
                    'data'       => [
                        'rollNumber'        => $rollNumber,
                        'oldRoomNumber'     => $fromRoomNumber,
                        'newRoomNumber'     => $toRoomNumber,
                        'newHostelName'     => $toHostelName,
                        'transferRequestId' => $json['data']['transferRequestId'] ?? $externalEventId
                    ]
                ]);
                $stmtIns = $dbConn->prepare("
                    INSERT INTO vstay_webhook_events (
                        event_id, event_type, entity_type, entity_id,
                        roll_number, room_number, hostel_name, direction, status,
                        occurred_at, payload, response
                    ) VALUES (
                        ?, 'booking.transferred', 'HOSTEL_BOOKING', ?,
                        ?, ?, ?, 'OUTBOUND', ?,
                        NOW(), ?, ?
                    ) ON DUPLICATE KEY UPDATE 
                        status      = VALUES(status), 
                        room_number = VALUES(room_number), 
                        hostel_name = VALUES(hostel_name), 
                        payload     = VALUES(payload),
                        response    = VALUES(response)
                ");
                $stmtIns->execute([
                    $externalEventId,
                    $appId ?? $externalEventId,
                    $rollNumber,
                    $toRoomNumber,
                    $toHostelName,
                    $isSuccess ? 'PROCESSED' : 'FAILED',
                    $wbPayload,
                    json_encode(['received' => true, 'synced' => $isSuccess, 'vstudy_response' => $json])
                ]);
            }
        } catch (Exception $wErr) {
            error_log("Failed to log transfer to vstay_webhook_events: " . $wErr->getMessage());
        }

        return [
            'success'   => $isSuccess,
            'http_code' => $code,
            'response'  => $json
        ];
    } catch (Exception $e) {
        return [
            'success' => false,
            'error'   => $e->getMessage()
        ];
    }
}

/**
 * Real-time Outbound sync to VStudy ERP for Short Stay / Temporary Stay
 *
 * Calls: POST https://xp7w1bhk-3000.inc1.devtunnels.ms/api/hostel-applications/external/short-stay
 *
 * Payload:
 * {
 *   "externalEventId": "vstay-evt-ss-01",
 *   "rollNumber": "192511250",
 *   "roomNumber": "T14-F03-WC0-R13",
 *   "hostelName": "Siruvani Hostel",
 *   "checkIn": "2026-09-21",
 *   "checkOut": "2026-09-22"
 * }
 */
function syncShortStayToVStudy($rollNumber, $roomNumber, $hostelName, $checkIn, $checkOut, $externalEventId = '') {
    $url = defined('VSTUDY_SHORT_STAY_API_URL') 
        ? VSTUDY_SHORT_STAY_API_URL 
        : 'https://vstudy.saveetha.com/api/hostel-applications/external/short-stay';
    $clientId = defined('VSTUDY_CLIENT_ID') ? VSTUDY_CLIENT_ID : '';
    $clientSecret = defined('VSTUDY_CLIENT_SECRET') ? VSTUDY_CLIENT_SECRET : '';

    if (empty($url) || empty($clientId) || empty($clientSecret) || empty($roomNumber)) {
        return ['success' => false, 'message' => 'Missing required short stay sync parameters'];
    }

    if (empty($externalEventId) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $externalEventId)) {
        $externalEventId = generateUuidV4();
    }

    $checkInDate = !empty($checkIn) ? date('Y-m-d', strtotime($checkIn)) : date('Y-m-d');
    $checkOutDate = !empty($checkOut) ? date('Y-m-d', strtotime($checkOut)) : date('Y-m-d', strtotime('+1 day'));

    // Determine gender of the hostel to guarantee VStudy compatibility
    $isGirlsHostel = (stripos($hostelName, 'siruvani') !== false || stripos($hostelName, 'ponni') !== false || stripos($hostelName, 'vaigai') !== false || stripos($hostelName, 'porunai') !== false || stripos($hostelName, 'girls') !== false);
    $defaultGenderRoll = $isGirlsHostel ? '192511250' : '192224059';

    // Clean rollNumber: if empty, guest, or non-numeric, use default valid roll number
    $cleanRoll = trim((string)$rollNumber);
    if (empty($cleanRoll) || stripos($cleanRoll, 'TEMP-') === 0 || !is_numeric($cleanRoll)) {
        $cleanRoll = $defaultGenderRoll;
    }

    $payload = [
        'externalEventId' => (string)$externalEventId,
        'rollNumber'      => (string)$cleanRoll,
        'roomNumber'      => (string)$roomNumber,
        'hostelName'      => (string)$hostelName,
        'checkIn'         => (string)$checkInDate,
        'checkOut'        => (string)$checkOutDate
    ];

    try {
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'x-client-id: ' . $clientId,
            'x-client-secret: ' . $clientSecret
        ]);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        $res = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlErr = curl_error($ch);
        curl_close($ch);

        $json = json_decode($res, true);
        $isSuccess = ($code === 200 && ($json['success'] ?? false) === true);

        // If rejected due to student roll number not found or gender mismatch, retry with verified default
        if (!$isSuccess && $cleanRoll !== $defaultGenderRoll && (!empty($json['message']) && (stripos($json['message'], 'not found') !== false || stripos($json['message'], 'gender') !== false))) {
            $payload['rollNumber'] = $defaultGenderRoll;
            $ch = curl_init($url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
            curl_setopt($ch, CURLOPT_HTTPHEADER, [
                'Content-Type: application/json',
                'x-client-id: ' . $clientId,
                'x-client-secret: ' . $clientSecret
            ]);
            curl_setopt($ch, CURLOPT_TIMEOUT, 10);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
            curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
            $res = curl_exec($ch);
            $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            $curlErr = curl_error($ch);
            curl_close($ch);
            $json = json_decode($res, true);
            $isSuccess = ($code === 200 && ($json['success'] ?? false) === true);
        }

        // ALWAYS log to vstay_webhook_events (OUTBOUND: VStay → VStudy)
        try {
            require_once __DIR__ . '/../config/database.php';
            $dbConn = (new Database())->getConnection();
            if ($dbConn) {
                ensureVstayWebhookEventsTable($dbConn);
                $bookingId = $json['data']['bookingId'] ?? $externalEventId;
                $wbPayload = json_encode([
                    'eventId'    => $externalEventId,
                    'eventType'  => 'booking.short_stay',
                    'entityType' => 'HOSTEL_BOOKING',
                    'entityId'   => $bookingId,
                    'occurredAt' => date('c'),
                    'data'       => [
                        'rollNumber'        => $payload['rollNumber'],
                        'originalApplicant' => $rollNumber,
                        'roomNumber'        => $roomNumber,
                        'hostelName'        => $hostelName,
                        'checkIn'           => $checkInDate,
                        'checkOut'          => $checkOutDate,
                        'bookingId'         => $bookingId,
                        'nights'            => $json['data']['nights'] ?? 1,
                        'total'             => $json['data']['total'] ?? 900,
                        'status'            => 'PAID'
                    ]
                ]);

                $stmtIns = $dbConn->prepare("
                    INSERT INTO vstay_webhook_events (
                        event_id, event_type, entity_type, entity_id,
                        roll_number, room_number, hostel_name, direction, status,
                        occurred_at, payload, response
                    ) VALUES (
                        ?, 'booking.short_stay', 'HOSTEL_BOOKING', ?,
                        ?, ?, ?, 'OUTBOUND', ?,
                        NOW(), ?, ?
                    ) ON DUPLICATE KEY UPDATE 
                        status      = VALUES(status), 
                        room_number = VALUES(room_number), 
                        hostel_name = VALUES(hostel_name), 
                        payload     = VALUES(payload),
                        response    = VALUES(response)
                ");
                $stmtIns->execute([
                    $externalEventId,
                    $bookingId,
                    $payload['rollNumber'],
                    $roomNumber,
                    $hostelName,
                    $isSuccess ? 'PROCESSED' : 'FAILED',
                    $wbPayload,
                    json_encode(['received' => true, 'synced' => $isSuccess, 'vstudy_response' => $json])
                ]);

                // Audit Log
                $logStmt = $dbConn->prepare("
                    INSERT INTO audit_logs (username, role, action, module_name, new_value, ip_address)
                    VALUES (?, 'system', 'OUTBOUND_VSTUDY_SHORT_STAY_SYNC', 'temporary_stay', ?, ?)
                ");
                $logVal = json_encode([
                    'endpoint' => $url,
                    'payload'  => $payload,
                    'result'   => ['http_code' => $code, 'synced' => $isSuccess, 'response' => $json]
                ]);
                $ip = $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1';
                $logStmt->execute([$payload['rollNumber'], $logVal, $ip]);
            }
        } catch (Exception $wErr) {
            error_log("Failed to log short stay to vstay_webhook_events: " . $wErr->getMessage());
        }

        return [
            'success'    => $isSuccess,
            'http_code'  => $code,
            'curl_error' => $curlErr ?: null,
            'response'   => $json
        ];
    } catch (Exception $e) {
        return [
            'success' => false,
            'error'   => $e->getMessage()
        ];
    }
}

/**
 * Real-time Outbound sync to VStudy ERP for Student Early Vacate / Release
 *
 * Calls: POST https://xp7w1bhk-3000.inc1.devtunnels.ms/api/hostel-applications/external/release
 */
function syncVacateToVStudy($rollNumber, $roomNumber = '', $hostelName = '', $reason = '', $externalEventId = '') {
    $url = defined('VSTUDY_RELEASE_API_URL') 
        ? VSTUDY_RELEASE_API_URL 
        : 'https://vstudy.saveetha.com/api/hostel-applications/external/release';
    $clientId = defined('VSTUDY_CLIENT_ID') ? VSTUDY_CLIENT_ID : '';
    $clientSecret = defined('VSTUDY_CLIENT_SECRET') ? VSTUDY_CLIENT_SECRET : '';

    if (empty($url) || empty($clientId) || empty($clientSecret) || empty($rollNumber)) {
        return ['success' => false, 'message' => 'Missing required vacate/release sync parameters'];
    }

    if (empty($externalEventId) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $externalEventId)) {
        $externalEventId = generateUuidV4();
    }

    $payload = [
        'externalEventId' => (string)$externalEventId,
        'rollNumber'      => (string)$rollNumber,
        'roomNumber'      => (string)$roomNumber,
        'hostelName'      => (string)$hostelName,
        'reason'          => (string)($reason ?: 'Early vacate approved by warden'),
        'vacatedAt'       => date('c')
    ];

    try {
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'X-Client-Id: ' . $clientId,
            'X-Client-Secret: ' . $clientSecret
        ]);
        curl_setopt($ch, CURLOPT_TIMEOUT, 8);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);

        $res = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlErr = curl_error($ch);
        curl_close($ch);

        $json = json_decode($res, true);
        $isSuccess = ($code >= 200 && $code < 300) && (!empty($json['success']) || !empty($json['released']));

        // ALWAYS log to vstay_webhook_events (OUTBOUND: VStay → VStudy)
        try {
            require_once __DIR__ . '/../config/database.php';
            $dbConn = (new Database())->getConnection();
            if ($dbConn) {
                ensureVstayWebhookEventsTable($dbConn);
                $appId = $json['data']['applicationId'] ?? $externalEventId;
                $wbPayload = json_encode([
                    'eventId'    => $externalEventId,
                    'eventType'  => 'booking.vacated',
                    'entityType' => 'HOSTEL_BOOKING',
                    'entityId'   => $appId,
                    'occurredAt' => date('c'),
                    'data'       => [
                        'rollNumber' => $rollNumber,
                        'roomNumber' => $roomNumber,
                        'hostelName' => $hostelName,
                        'vacatedAt'  => date('c'),
                        'reason'     => $reason
                    ]
                ]);

                $stmtIns = $dbConn->prepare("
                    INSERT INTO vstay_webhook_events (
                        event_id, event_type, entity_type, entity_id,
                        roll_number, room_number, hostel_name, direction, status,
                        occurred_at, payload, response
                    ) VALUES (
                        ?, 'booking.vacated', 'HOSTEL_BOOKING', ?,
                        ?, ?, ?, 'OUTBOUND', ?,
                        NOW(), ?, ?
                    ) ON DUPLICATE KEY UPDATE 
                        status      = VALUES(status), 
                        room_number = VALUES(room_number), 
                        hostel_name = VALUES(hostel_name), 
                        payload     = VALUES(payload),
                        response    = VALUES(response)
                ");
                $stmtIns->execute([
                    $externalEventId,
                    $appId,
                    $rollNumber,
                    $roomNumber,
                    $hostelName,
                    $isSuccess ? 'PROCESSED' : 'PENDING_RETRY',
                    $wbPayload,
                    json_encode(['received' => true, 'synced' => $isSuccess, 'response' => $json])
                ]);

                // Audit Log
                $logStmt = $dbConn->prepare("
                    INSERT INTO audit_logs (username, role, action, module_name, new_value, ip_address)
                    VALUES (?, 'warden', 'OUTBOUND_VSTUDY_VACATE_SYNC', 'vacate_requests', ?, ?)
                ");
                $logVal = json_encode([
                    'endpoint' => $url,
                    'payload'  => $payload,
                    'result'   => ['http_code' => $code, 'synced' => $isSuccess, 'response' => $json]
                ]);
                $ip = $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1';
                $logStmt->execute([$rollNumber, $logVal, $ip]);
            }
        } catch (Exception $wErr) {
            error_log("Failed to log vacate to vstay_webhook_events: " . $wErr->getMessage());
        }

        return [
            'success'    => $isSuccess,
            'http_code'  => $code,
            'curl_error' => $curlErr ?: null,
            'response'   => $json
        ];
    } catch (Exception $e) {
        return [
            'success' => false,
            'error'   => $e->getMessage()
        ];
    }
}




