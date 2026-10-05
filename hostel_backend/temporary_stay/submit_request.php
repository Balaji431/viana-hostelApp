<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/api_config.php';
require_once __DIR__ . '/../send_notification.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

$input = json_decode(file_get_contents('php://input'), true);

if (!$input) {
    echo json_encode(["success" => false, "message" => "Invalid JSON payload"]);
    exit();
}

$full_name = trim($input['full_name'] ?? '');
$email = trim($input['email'] ?? '');
$phone = trim($input['phone'] ?? '');
$gender = trim($input['gender'] ?? 'Male');
$purpose = trim($input['institution_purpose'] ?? '');
$doc_type = trim($input['doc_type'] ?? '');
$doc_number = trim($input['doc_number'] ?? '');
$hostel_name = trim($input['hostel_name'] ?? '');
$room_type = trim($input['room_type'] ?? '');
$room_no = trim($input['room_no'] ?? '');
$room_code = trim($input['room_code'] ?? $room_no);
$room_id = trim($input['room_id'] ?? '');
$doc_file_path = trim($input['doc_file_path'] ?? '');
$from_date = trim($input['from_date'] ?? date('Y-m-d'));
$duration_type = 'days'; // Strictly restricted to days only
$duration_value = (int)($input['duration_value'] ?? 1);
$fcm_token = trim($input['fcm_token'] ?? '');

// Strict limit: Temporary stay is allowed for a maximum of 10 days only
if ($duration_value < 1 || $duration_value > 10) {
    echo json_encode([
        "success" => false,
        "message" => "Temporary stay is strictly restricted to a maximum of 10 days."
    ]);
    exit();
}

if (empty($full_name) || empty($email) || empty($phone) || empty($doc_type) || empty($doc_number) || empty($hostel_name) || empty($room_no)) {
    echo json_encode(["success" => false, "message" => "Please fill in all required fields including Government ID details."]);
    exit();
}

// 1. Check duplicate Document Number across existing active temporary requests
$cleanDocNo = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $doc_number));
if (!empty($cleanDocNo)) {
    $stmtDoc = $db->prepare("
        SELECT id, full_name, email 
        FROM temporary_stay_requests 
        WHERE REPLACE(REPLACE(UPPER(TRIM(doc_number)), ' ', ''), '-', '') = ? 
          AND LOWER(TRIM(email)) != LOWER(TRIM(?))
          AND status IN ('pending', 'approved', 'allocated')
        LIMIT 1
    ");
    $stmtDoc->execute([$cleanDocNo, $email]);
    $docConflict = $stmtDoc->fetch(PDO::FETCH_ASSOC);
    if ($docConflict) {
        echo json_encode([
            "success" => false, 
            "message" => "This government document number ($doc_number) already exists and is registered to another application. Please upload your own valid government ID."
        ]);
        exit();
    }
}

// 2. Check duplicate Phone Number across existing active temporary requests
$cleanPhone = preg_replace('/[^0-9]/', '', $phone);
if (!empty($cleanPhone) && strlen($cleanPhone) >= 10) {
    $stmtPhone = $db->prepare("
        SELECT id, full_name, email 
        FROM temporary_stay_requests 
        WHERE REPLACE(REPLACE(TRIM(phone), ' ', ''), '-', '') LIKE ? 
          AND LOWER(TRIM(email)) != LOWER(TRIM(?))
          AND status IN ('pending', 'approved', 'allocated')
        LIMIT 1
    ");
    $stmtPhone->execute(["%$cleanPhone%", $email]);
    $phoneConflict = $stmtPhone->fetch(PDO::FETCH_ASSOC);
    if ($phoneConflict) {
        echo json_encode([
            "success" => false, 
            "message" => "This phone number ($phone) already exists and is registered to another application. Please enter your own valid 10-digit mobile number."
        ]);
        exit();
    }
}

// Auto alter table columns if missing
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN room_code VARCHAR(191) NULL AFTER room_no;");
} catch (Exception $eCol1) {}
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN doc_file_path TEXT NULL AFTER doc_number;");
} catch (Exception $eCol2) {}
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN amount DECIMAL(10,2) NOT NULL DEFAULT 0.00 AFTER duration_value;");
} catch (Exception $eCol3) {}
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN annual_fee DECIMAL(10,2) NOT NULL DEFAULT 0.00 AFTER amount;");
} catch (Exception $eCol4) {}
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN payment_status VARCHAR(32) NOT NULL DEFAULT 'unpaid' AFTER status;");
} catch (Exception $eCol5) {}
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN payment_txn_id VARCHAR(128) NULL AFTER payment_status;");
} catch (Exception $eCol6) {}
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN warden_name VARCHAR(191) NULL AFTER fcm_token;");
} catch (Exception $eColW1) {}
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN warden_id VARCHAR(100) NULL AFTER warden_name;");
} catch (Exception $eColW2) {}
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN warden_bio_id VARCHAR(50) NULL AFTER warden_id;");
} catch (Exception $eColW3) {}
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN hold_expires_at DATETIME NULL AFTER warden_bio_id;");
} catch (Exception $eColW4) {}
try {
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN hold_status VARCHAR(32) DEFAULT 'none' AFTER hold_expires_at;");
} catch (Exception $eColW5) {}

// Find the designated Warden for this hostel & room
$warden_name = null;
$warden_id = null;
$warden_bio_id = null;
try {
    $stmtW = $db->prepare("SELECT warden_name, warden_user_id, warden_bio_id 
                           FROM rooms_groups_details 
                           WHERE (LOWER(TRIM(hostel_name)) = LOWER(TRIM(?)) OR REPLACE(LOWER(hostel_name), ' ', '') = REPLACE(LOWER(?), ' ', '')) 
                             AND (room_number = ? OR room_number = ? OR REPLACE(REPLACE(room_number, ' ', ''), '-', '') = REPLACE(REPLACE(?, ' ', ''), '-', '')) 
                           LIMIT 1");
    $stmtW->execute([$hostel_name, $hostel_name, $room_no, $room_code, $room_no]);
    $wRow = $stmtW->fetch(PDO::FETCH_ASSOC);
    if ($wRow && !empty($wRow['warden_name'])) {
        $warden_name = $wRow['warden_name'];
        $warden_id = $wRow['warden_user_id'];
        $warden_bio_id = $wRow['warden_bio_id'];
    }
} catch (Exception $eW) {}

if (empty($warden_name)) {
    try {
        $cleanHostel = preg_replace('/[^a-zA-Z0-9]/', '', $hostel_name);
        $stmtM = $db->prepare("SELECT name, username, staff_bio_id 
                               FROM mapping_staff 
                               WHERE LOWER(role) LIKE '%warden%' 
                                 AND (LOWER(hostel_name) LIKE LOWER(?) OR LOWER(?) LIKE LOWER(CONCAT('%', hostel_name, '%')) OR REPLACE(hostel_name, ' ', '') LIKE ?) 
                               LIMIT 1");
        $stmtM->execute(["%$hostel_name%", $hostel_name, "%$cleanHostel%"]);
        $mRow = $stmtM->fetch(PDO::FETCH_ASSOC);
        if ($mRow && !empty($mRow['name'])) {
            $warden_name = $mRow['name'];
            $warden_id = $mRow['username'];
            $warden_bio_id = $mRow['staff_bio_id'];
        }
    } catch (Exception $eM) {}
}

// Calculate Fee based on VStudy Pricing API or (Annual Fee / 365 rounded up to next 50) * 3
function calculateStayFee($db, $roomType, $durationType, $durationValue, $roomNo = '') {
    $apiPerDay = 0;
    try {
        $pricingApiUrl = defined('VSTUDY_PRICING_API_URL') ? VSTUDY_PRICING_API_URL : 'https://xp7w1bhk-3000.inc1.devtunnels.ms/api/hostel-applications/external/pricing';
        $clientId = defined('VSTUDY_CLIENT_ID') ? VSTUDY_CLIENT_ID : '';
        $clientSecret = defined('VSTUDY_CLIENT_SECRET') ? VSTUDY_CLIENT_SECRET : '';
        $ch = curl_init($pricingApiUrl);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode(['roomType' => trim($roomType)]));
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'x-client-id: ' . $clientId,
            'x-client-secret: ' . $clientSecret
        ]);
        curl_setopt($ch, CURLOPT_TIMEOUT, 3);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        $pRes = curl_exec($ch);
        $pCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($pCode === 200 && !empty($pRes)) {
            $pJson = json_decode($pRes, true);
            if (!empty($pJson['data']['shortStay']['perDay']) && (int)$pJson['data']['shortStay']['perDay'] > 0) {
                $apiPerDay = (int)$pJson['data']['shortStay']['perDay'];
            }
        }
    } catch (Exception $eP) {}

    $annualFee = 0;
    try {
        if (!empty($roomNo)) {
            $stmtR = $db->prepare("SELECT amount FROM rooms_groups_details WHERE room_number = ? AND amount > 0 LIMIT 1");
            $stmtR->execute([$roomNo]);
            $rRow = $stmtR->fetch(PDO::FETCH_ASSOC);
            if ($rRow && !empty($rRow['amount']) && (float)$rRow['amount'] > 0) {
                $annualFee = (float)$rRow['amount'];
            }
        }
        if ($annualFee <= 0) {
            $stmt = $db->prepare("SELECT total_fee, hostel_fee FROM hostel_renew_fee WHERE LOWER(room_type) = LOWER(?) LIMIT 1");
            $stmt->execute([trim($roomType)]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if ($row && !empty($row['total_fee']) && (float)$row['total_fee'] > 0) {
                $annualFee = (float)$row['total_fee'];
            } else if ($row && !empty($row['hostel_fee']) && (float)$row['hostel_fee'] > 0) {
                $annualFee = (float)$row['hostel_fee'];
            }
        }
    } catch (Exception $e) {}

    if ($annualFee <= 0) {
        $rtLower = strtolower($roomType);
        if (strpos($rtLower, 'single') !== false && strpos($rtLower, 'ac') !== false) {
            $annualFee = 150000;
        } else if (strpos($rtLower, 'single') !== false) {
            $annualFee = 55000;
        } else if (strpos($rtLower, 'super deluxe') !== false && (strpos($rtLower, '4 in 1') !== false || strpos($rtLower, '4-in-1') !== false)) {
            $annualFee = 95000;
        } else if (strpos($rtLower, 'super deluxe') !== false && (strpos($rtLower, '3 in 1') !== false || strpos($rtLower, '3-in-1') !== false)) {
            $annualFee = 110000;
        } else if (strpos($rtLower, '2 in 1') !== false || strpos($rtLower, 'double') !== false) {
            $annualFee = (strpos($rtLower, 'ac') !== false) ? 100000 : 55000;
        } else if (strpos($rtLower, '3 in 1') !== false || strpos($rtLower, 'triple') !== false) {
            $annualFee = (strpos($rtLower, 'ac') !== false) ? 80000 : 55000;
        } else if (strpos($rtLower, '4 in 1') !== false) {
            $annualFee = (strpos($rtLower, 'ac') !== false) ? 70000 : 50000;
        } else if (strpos($rtLower, 'dorm') !== false) {
            $annualFee = 36500;
        } else {
            $annualFee = 75000;
        }
    }

    if ($apiPerDay > 0) {
        $roundedDailyRate = (float)$apiPerDay;
    } else {
        $roundedDailyRate = (float)(ceil(($annualFee / 365.0) / 50.0) * 50.0 * 3);
        if ($roundedDailyRate < 50) $roundedDailyRate = 50.0;
    }

    $durationVal = max(1, (int)$durationValue);
    $totalDays = (strtolower($durationType) === 'months') ? ($durationVal * 30) : $durationVal;
    $totalAmount = $roundedDailyRate * $totalDays;

    return [
        'annual_fee' => $annualFee,
        'daily_rate' => (float)$roundedDailyRate,
        'total_days' => $totalDays,
        'total_amount' => (float)$totalAmount
    ];
}

$feeCalc = calculateStayFee($db, $room_type, $duration_type, $duration_value, $room_no);
$calculated_amount = $feeCalc['total_amount'];
$annual_fee = $feeCalc['annual_fee'];

// Calculate to_date based on duration (strictly in days, max 10 days)
$fromDateObj = new DateTime($from_date);
$fromDateObj->modify("+$duration_value day");
$to_date = $fromDateObj->format('Y-m-d');

$request_id = 'TEMP-' . strtoupper(substr(md5(uniqid(mt_rand(), true)), 0, 8));

try {
    $stmt = $db->prepare("INSERT INTO temporary_stay_requests 
        (request_id, full_name, email, phone, gender, institution_purpose, doc_type, doc_number, doc_file_path, hostel_name, room_type, room_no, room_code, room_id, from_date, to_date, duration_type, duration_value, amount, annual_fee, status, payment_status, fcm_token, warden_name, warden_id, warden_bio_id) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 'unpaid', ?, ?, ?, ?)");
    
    $stmt->execute([
        $request_id,
        $full_name,
        $email,
        $phone,
        $gender,
        $purpose,
        $doc_type,
        $doc_number,
        $doc_file_path,
        $hostel_name,
        $room_type,
        $room_no,
        $room_code,
        $room_id,
        $from_date,
        $to_date,
        $duration_type,
        $duration_value,
        $calculated_amount,
        $annual_fee,
        $fcm_token,
        $warden_name,
        $warden_id,
        $warden_bio_id
    ]);

    // Register or update guest user in users and profile tables for immediate Google Sign-In & FCM
    try {
        $genderType = (stripos($gender, 'female') !== false || stripos($hostel_name, 'girls') !== false) ? 'Girls' : 'Boys';
        $dummyPass = password_hash('welcome123', PASSWORD_BCRYPT);
        
        $checkU = $db->prepare("SELECT id, username FROM users WHERE LOWER(email) = LOWER(?) LIMIT 1");
        $checkU->execute([$email]);
        $existingU = $checkU->fetch(PDO::FETCH_ASSOC);

        if ($existingU) {
            $updU = $db->prepare("UPDATE users SET full_name = ?, phone_number = ?, HostelName = ?, HostelType = ?, RoomType = ?, RoomId = ?, Status = 'active' WHERE id = ?");
            $updU->execute([$full_name, $phone, $hostel_name, $genderType, $room_type, $room_no, $existingU['id']]);
            if (!empty($fcm_token)) {
                $db->prepare("UPDATE users SET fcm_token = ? WHERE id = ?")->execute([$fcm_token, $existingU['id']]);
            }
            
            $updP = $db->prepare("INSERT INTO profile (user_id, reg_no, full_name, email, personal_phone, hostel_name, room_allocation, valid_from, valid_to, profile_pic) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'profile.png') ON DUPLICATE KEY UPDATE full_name = VALUES(full_name), personal_phone = VALUES(personal_phone), hostel_name = VALUES(hostel_name), room_allocation = VALUES(room_allocation), valid_from = VALUES(valid_from), valid_to = VALUES(valid_to)");
            $updP->execute([$existingU['id'], $existingU['username'], $full_name, $email, $phone, $hostel_name, $room_no, $from_date, $to_date]);
        } else {
            $insU = $db->prepare("INSERT INTO users (
                username, password, full_name, email, role, phone_number, HostelName, HostelType, RoomType, RoomId, Status, is_active, Gender, Academic, IsBiometric, fcm_token
            ) VALUES (
                :username, :password, :full_name, :email, 'guest', :phone, :hostel_name, :hostel_type, :room_type, :room_id, 'active', 1, :gender, 'Temporary Stay', 'No', :fcm_token
            )");
            $insU->execute([
                ':username' => $request_id,
                ':password' => $dummyPass,
                ':full_name' => $full_name,
                ':email' => $email,
                ':phone' => $phone,
                ':hostel_name' => $hostel_name,
                ':hostel_type' => $genderType,
                ':room_type' => $room_type,
                ':room_id' => $room_no,
                ':gender' => $gender,
                ':fcm_token' => $fcm_token
            ]);
            $newUid = $db->lastInsertId();

            $insP = $db->prepare("INSERT INTO profile (
                user_id, reg_no, full_name, email, personal_phone, hostel_name, room_allocation, valid_from, valid_to, profile_pic
            ) VALUES (
                :user_id, :reg_no, :full_name, :email, :phone, :hostel_name, :room_no, :valid_from, :valid_to, 'profile.png'
            )");
            $insP->execute([
                ':user_id' => $newUid,
                ':reg_no' => $request_id,
                ':full_name' => $full_name,
                ':email' => $email,
                ':phone' => $phone,
                ':hostel_name' => $hostel_name,
                ':room_no' => $room_no,
                ':valid_from' => $from_date,
                ':valid_to' => $to_date
            ]);
        }
    } catch (Exception $eUser) {
        file_put_contents(__DIR__ . '/../user_insert_error.txt', "User insert error: " . $eUser->getMessage() . "\n", FILE_APPEND);
    }

    // Send Push Notifications to Admin / Staff / Warden users
    try {
        $adminStmt = $db->prepare("SELECT DISTINCT fcm_token FROM users WHERE role IN ('admin', 'warden', 'staff') AND fcm_token IS NOT NULL AND fcm_token != ''");
        $adminStmt->execute();
        $adminTokens = $adminStmt->fetchAll(PDO::FETCH_COLUMN);

        $notifTitle = "New Temporary Stay Request 🏨";
        $notifBody = "Applicant $full_name requested Room $room_no ($hostel_name) for $duration_value $duration_type starting $from_date.";

        foreach ($adminTokens as $token) {
            sendFCM($token, $notifTitle, $notifBody, $request_id, $email, $full_name, $notifBody, 'temporary_stay', 'admin');
        }
    } catch (Exception $eNotif) {
        // Log notification error silently without blocking response
        file_put_contents(__DIR__ . '/../fcm_debug.txt', "Temporary Stay push error: " . $eNotif->getMessage() . "\n", FILE_APPEND);
    }

    // Construct complete user_data payload for auto-login into HomeScreen
    $effectiveUid = $existingU['id'] ?? $newUid ?? 1;
    $tsrRecord = [
        "id" => (int)($db->lastInsertId() ?: 1),
        "request_id" => $request_id,
        "full_name" => $full_name,
        "email" => $email,
        "phone" => $phone,
        "gender" => $gender,
        "institution_purpose" => $purpose,
        "doc_type" => $doc_type,
        "doc_number" => $doc_number,
        "doc_file_path" => $doc_file_path,
        "hostel_name" => $hostel_name,
        "room_type" => $room_type,
        "room_no" => $room_no,
        "room_code" => $room_code,
        "room_id" => (int)$room_id,
        "from_date" => $from_date,
        "to_date" => $to_date,
        "duration_type" => $duration_type,
        "duration_value" => (int)$duration_value,
        "amount" => (float)$calculated_amount,
        "annual_fee" => (float)$annual_fee,
        "status" => "pending",
        "payment_status" => "unpaid",
        "warden_name" => $warden_name ?: "Manoj A",
        "warden_id" => $warden_id ?: "20018",
        "warden_bio_id" => $warden_bio_id ?: "20018",
        "created_at" => date('Y-m-d H:i:s')
    ];

    $nowDay = strtotime(date('Y-m-d'));
    $toDay = strtotime($to_date);
    $calcDays = (int)(($toDay - $nowDay) / 86400);
    $remDays = $calcDays > 0 ? $calcDays : (int)$duration_value;

    $userData = [
        "id" => (int)$effectiveUid,
        "username" => $request_id,
        "full_name" => $full_name,
        "register_no" => $request_id,
        "phone" => $phone,
        "email" => $email,
        "dob" => "2000-01-01",
        "address" => "Temporary Stay Resident",
        "role" => "guest",
        "institution" => "Saveetha Institute of Medical and Technical Sciences",
        "hostel_name" => $hostel_name,
        "room_allocation" => $room_no,
        "profile_pic" => "profile.png",
        "valid_from" => $from_date,
        "valid_to" => $to_date,
        "conduct" => "Good",
        "conduct_remarks" => "",
        "biometric_id" => "N/A",
        "warden" => $warden_name ?: "Manoj A",
        "group_name" => "",
        "floor_name" => "",
        "room_no" => $room_no,
        "room_code" => $room_code,
        "block" => "N/A",
        "wing" => "N/A",
        "room_type" => $room_type,
        "room_facility" => "Standard",
        "room_bath_attached" => "No",
        "room_amount" => (float)$calculated_amount,
        "room_food" => 0,
        "room_caution" => 0,
        "total_fee" => (float)$calculated_amount,
        "renew_amount" => (float)$calculated_amount,
        "check_in_date" => $from_date,
        "renewal_date" => $to_date,
        "remaining_days" => $remDays,
        "hostel_type" => (stripos($gender, 'female') !== false || stripos($hostel_name, 'girls') !== false) ? 'Girls' : 'Boys',
        "temporary_stay_request" => $tsrRecord,
        "token" => "TEMP_TOKEN_" . md5($request_id)
    ];

    echo json_encode([
        "success" => true,
        "message" => "Temporary stay request submitted successfully!",
        "request_id" => $request_id,
        "status" => "pending",
        "user_data" => $userData,
        "data" => $tsrRecord
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Error submitting temporary stay request: " . $e->getMessage()
    ]);
}
?>
