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
$duration_type = trim($input['duration_type'] ?? 'days');
$duration_value = (int)($input['duration_value'] ?? 1);
$fcm_token = trim($input['fcm_token'] ?? '');

if (empty($full_name) || empty($email) || empty($phone) || empty($doc_type) || empty($doc_number) || empty($hostel_name) || empty($room_no)) {
    echo json_encode(["success" => false, "message" => "Please fill in all required fields including Government ID details."]);
    exit();
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
    $db->exec("ALTER TABLE temporary_stay_requests ADD COLUMN fcm_token TEXT NULL AFTER payment_txn_id;");
} catch (Exception $eCol7) {}

// Register/update user in users table for reliable FCM push notifications
try {
    $checkU = $db->prepare("SELECT id FROM users WHERE LOWER(email) = LOWER(?) LIMIT 1");
    $checkU->execute([$email]);
    $existingU = $checkU->fetch(PDO::FETCH_ASSOC);
    if ($existingU) {
        if (!empty($fcm_token)) {
            $db->prepare("UPDATE users SET fcm_token = ? WHERE id = ?")->execute([$fcm_token, $existingU['id']]);
        }
    } else {
        $tempUsername = 'TEMP_' . strtoupper(substr(md5($email), 0, 8));
        $dummyPass = password_hash('welcome123', PASSWORD_DEFAULT);
        $insU = $db->prepare("INSERT INTO users (username, password, full_name, email, role, Status, fcm_token) VALUES (?, ?, ?, ?, 'student', 'active', ?)");
        $insU->execute([$tempUsername, $dummyPass, $full_name, $email, $fcm_token]);
    }
} catch (Exception $eUser) {
    file_put_contents(__DIR__ . '/../user_insert_error.txt', "User insert error: " . $eUser->getMessage() . "\n", FILE_APPEND);
}

// Calculate Fee based on Annual Fee / 365 * days
function calculateStayFee($db, $roomType, $durationType, $durationValue) {
    $annualFee = 0;
    try {
        $stmt = $db->prepare("SELECT total_fee, hostel_fee FROM hostel_renew_fee WHERE LOWER(room_type) = LOWER(?) LIMIT 1");
        $stmt->execute([trim($roomType)]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row && !empty($row['total_fee']) && (float)$row['total_fee'] > 0) {
            $annualFee = (float)$row['total_fee'];
        } else if ($row && !empty($row['hostel_fee']) && (float)$row['hostel_fee'] > 0) {
            $annualFee = (float)$row['hostel_fee'];
        }
    } catch (Exception $e) {}

    if ($annualFee <= 0) {
        $rtLower = strtolower($roomType);
        if (strpos($rtLower, '2 in 1') !== false || strpos($rtLower, '2-in-1') !== false) {
            $annualFee = 90000;
        } else if (strpos($rtLower, '3 in 1') !== false || strpos($rtLower, '3-in-1') !== false) {
            $annualFee = 75000;
        } else if (strpos($rtLower, '4 in 1') !== false || strpos($rtLower, '4-in-1') !== false) {
            $annualFee = 60000;
        } else {
            $annualFee = 75000;
        }
    }

    $dailyRate = $annualFee / 365.0;
    $durationVal = max(1, (int)$durationValue);
    $totalDays = (strtolower($durationType) === 'months') ? ($durationVal * 30) : $durationVal;
    $totalAmount = round($dailyRate * $totalDays, 2);

    return [
        'annual_fee' => $annualFee,
        'daily_rate' => round($dailyRate, 2),
        'total_days' => $totalDays,
        'total_amount' => $totalAmount
    ];
}

$feeCalc = calculateStayFee($db, $room_type, $duration_type, $duration_value);
$calculated_amount = $feeCalc['total_amount'];
$annual_fee = $feeCalc['annual_fee'];

// Calculate to_date based on duration
$fromDateObj = new DateTime($from_date);
if ($duration_type === 'months') {
    $fromDateObj->modify("+$duration_value month");
} else {
    $fromDateObj->modify("+$duration_value day");
}
$to_date = $fromDateObj->format('Y-m-d');

$request_id = 'TEMP-' . strtoupper(substr(md5(uniqid(mt_rand(), true)), 0, 8));

try {
    $stmt = $db->prepare("INSERT INTO temporary_stay_requests 
        (request_id, full_name, email, phone, gender, institution_purpose, doc_type, doc_number, doc_file_path, hostel_name, room_type, room_no, room_code, room_id, from_date, to_date, duration_type, duration_value, amount, annual_fee, status, payment_status, fcm_token) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 'unpaid', ?)");
    
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
        $fcm_token
    ]);

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

    echo json_encode([
        "success" => true,
        "message" => "Temporary stay request submitted successfully!",
        "request_id" => $request_id,
        "status" => "pending",
        "data" => [
            "request_id" => $request_id,
            "full_name" => $full_name,
            "email" => $email,
            "hostel_name" => $hostel_name,
            "room_no" => $room_no,
            "from_date" => $from_date,
            "to_date" => $to_date
        ]
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Error submitting temporary stay request: " . $e->getMessage()
    ]);
}
?>
