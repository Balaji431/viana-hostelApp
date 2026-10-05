<?php
/**
 * setup_room_not_allocated.php
 *
 * 1. Drops `matched_students` (if any exists).
 * 2. Creates `room_not_allocated` table.
 * 3. Truncates and populates `vstudy_payments` with ONLY the 4,464 records from booked-rooms/external.
 * 4. Populates `room_not_allocated` with the paid students from old_api (hostel-applications/paid) who do not have a booked room.
 */

set_time_limit(600);
ini_set('memory_limit', '512M');

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/api_config.php';

if (PHP_SAPI !== 'cli') {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, OPTIONS');
    header('Content-Type: application/json; charset=UTF-8');
    if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit(); }
    require_once __DIR__ . '/auth_helper.php';
    requireAuth(['super_admin', 'admin']);
}

function log_step($msg) {
    echo '[' . date('Y-m-d H:i:s') . '] ' . $msg . PHP_EOL;
}

function fetchAllFromApi(string $baseUrl): array {
    $page = 1;
    $limit = 100;
    $all = [];

    while (true) {
        $sep = (strpos($baseUrl, '?') !== false) ? '&' : '?';
        $url = "{$baseUrl}{$sep}page={$page}&limit={$limit}";

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 30,
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_HTTPHEADER     => [
                'x-client-id: '     . VSTUDY_CLIENT_ID,
                'x-client-secret: ' . VSTUDY_CLIENT_SECRET,
                'Accept: application/json',
            ],
        ]);

        $raw = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err = curl_error($ch);
        curl_close($ch);

        if ($err || $code !== 200) {
            log_step("  API error HTTP $code on page $page: $err");
            break;
        }

        $json = json_decode($raw, true);
        $batch = $json['data'] ?? (is_array($json) ? $json : []);

        if (empty($batch)) break;

        $all = array_merge($all, $batch);

        $totalPages = $json['pagination']['totalPages'] ?? null;
        $hasNext    = $json['pagination']['hasNext'] ?? null;

        if ($hasNext === false) break;
        if ($totalPages !== null && $page >= $totalPages) break;
        if (count($batch) < $limit) break;

        $page++;
        usleep(15000);
    }

    return $all;
}

try {
    $database = new Database();
    $db = $database->getConnection();
    if (!$db) throw new Exception("Database connection failed");

    log_step("=== setup_room_not_allocated.php started ===");

    // Step 1: Drop matched_students if exists
    $db->exec("DROP TABLE IF EXISTS matched_students");
    log_step("Step 1: Dropped matched_students table (if existed).");

    // Step 2: Create room_not_allocated table
    $db->exec("
        CREATE TABLE IF NOT EXISTS `room_not_allocated` (
            `id` int NOT NULL AUTO_INCREMENT,
            `application_id` varchar(255) DEFAULT NULL,
            `receipt_number` varchar(255) DEFAULT NULL,
            `roll_number` varchar(100) NOT NULL,
            `student_name` varchar(255) DEFAULT NULL,
            `email` varchar(255) DEFAULT NULL,
            `phone` varchar(100) DEFAULT NULL,
            `hostel_name` varchar(255) DEFAULT NULL,
            `campus` varchar(255) DEFAULT NULL,
            `room_type` varchar(255) DEFAULT NULL,
            `occupancy` varchar(50) DEFAULT NULL,
            `gender` varchar(50) DEFAULT NULL,
            `room_rent` decimal(10,2) DEFAULT '0.00',
            `food_fee` decimal(10,2) DEFAULT '0.00',
            `caution_deposit` decimal(10,2) DEFAULT '0.00',
            `total_fee` decimal(10,2) DEFAULT '0.00',
            `paid_at` varchar(100) DEFAULT NULL,
            `applied_at` varchar(100) DEFAULT NULL,
            `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `roll_number` (`roll_number`),
            KEY `application_id` (`application_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ");
    log_step("Step 2: Created room_not_allocated table.");

    // Step 3: Fetch all 4,464 records from booked-rooms/external
    log_step("Step 3: Fetching records from booked-rooms/external API...");
    $bookedRecords = fetchAllFromApi("https://vstudy.saveetha.com/api/hostel-settings/booked-rooms/external");
    log_step("  Fetched " . count($bookedRecords) . " records from booked-rooms API.");

    // Step 4: Truncate and populate vstudy_payments with ONLY booked-rooms
    log_step("Step 4: Rebuilding vstudy_payments with ONLY booked-rooms records...");
    $db->exec("TRUNCATE TABLE vstudy_payments");

    $insertVpStmt = $db->prepare("
        INSERT INTO vstudy_payments (
            booking_id, roll_number, student_name, email, phone, gender,
            booker_type, hostel_name, campus, room_number, room_type,
            paid_amount, application_status, payment_status, renewal_date,
            paid_date
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            booking_id = VALUES(booking_id),
            student_name = VALUES(student_name),
            email = VALUES(email),
            phone = VALUES(phone),
            gender = VALUES(gender),
            booker_type = VALUES(booker_type),
            hostel_name = VALUES(hostel_name),
            campus = VALUES(campus),
            room_number = VALUES(room_number),
            room_type = VALUES(room_type),
            paid_amount = VALUES(paid_amount),
            application_status = VALUES(application_status),
            payment_status = VALUES(payment_status),
            renewal_date = VALUES(renewal_date),
            paid_date = VALUES(paid_date)
    ");

    $db->beginTransaction();
    $vpInserted = 0;
    $bookedRollNumbers = [];

    foreach ($bookedRecords as $b) {
        $reg = trim($b['registerNumber'] ?? '');
        if ($reg !== '') {
            $bookedRollNumbers[$reg] = true;
        }

        $insertVpStmt->execute([
            $b['bookingId'] ?? $b['id'] ?? null,
            $reg,
            trim($b['name'] ?? $b['student_name'] ?? ''),
            trim($b['email'] ?? ''),
            trim($b['phone'] ?? ''),
            trim($b['gender'] ?? ''),
            trim($b['bookerType'] ?? ''),
            trim($b['hostelName'] ?? ''),
            trim($b['campus'] ?? ''),
            trim($b['roomNumber'] ?? ''),
            trim($b['roomType'] ?? ''),
            (float)($b['monthlyFee'] ?? 0),
            $b['deductionStatus'] ?? null,
            trim($b['status'] ?? ''),
            $b['renewalDate'] ?? null,
            $b['checkIn'] ?? null
        ]);
        $vpInserted++;
    }
    $db->commit();
    log_step("  Inserted $vpInserted records into vstudy_payments.");

    // Step 5: Populate room_not_allocated from old_api (students who have NO booked room)
    log_step("Step 5: Populating room_not_allocated from old_api for students without a booked room...");
    $db->exec("TRUNCATE TABLE room_not_allocated");

    $insertNotAllocStmt = $db->prepare("
        INSERT INTO room_not_allocated (
            application_id, receipt_number, roll_number, student_name, email,
            phone, hostel_name, campus, room_type, occupancy, gender,
            room_rent, food_fee, caution_deposit, total_fee, paid_at, applied_at
        )
        SELECT 
            o.application_id, o.receipt_number, o.roll_number, o.student_name, o.email,
            o.phone, o.hostel_name, o.campus, o.room_type, o.occupancy, o.gender,
            o.room_rent, o.food_fee, o.caution_deposit, o.total_fee, o.paid_at, o.applied_at
        FROM old_api o
        LEFT JOIN vstudy_payments vp ON TRIM(o.roll_number) = TRIM(vp.roll_number)
        WHERE (vp.room_number IS NULL OR TRIM(vp.room_number) = '')
          AND o.roll_number IS NOT NULL AND TRIM(o.roll_number) != ''
        ON DUPLICATE KEY UPDATE
            student_name = VALUES(student_name),
            email = VALUES(email),
            hostel_name = VALUES(hostel_name),
            total_fee = VALUES(total_fee)
    ");

    $notAllocInserted = $insertNotAllocStmt->execute();
    $finalNotAllocCount = (int)$db->query("SELECT COUNT(*) FROM room_not_allocated")->fetchColumn();
    log_step("  Inserted $finalNotAllocCount unallocated paid students into room_not_allocated.");

    $finalVpCount = (int)$db->query("SELECT COUNT(*) FROM vstudy_payments")->fetchColumn();
    $finalOldCount = (int)$db->query("SELECT COUNT(*) FROM old_api")->fetchColumn();

    log_step("=== Completed successfully! ===");
    log_step("vstudy_payments (Booked Rooms): $finalVpCount");
    log_step("room_not_allocated (Paid but no room): $finalNotAllocCount");
    log_step("old_api (All Paid Apps): $finalOldCount");

    echo json_encode([
        'status' => 'success',
        'vstudy_payments_count' => $finalVpCount,
        'room_not_allocated_count' => $finalNotAllocCount,
        'old_api_count' => $finalOldCount,
        'ran_at' => date('Y-m-d H:i:s')
    ], JSON_PRETTY_PRINT);

} catch (Exception $e) {
    if (isset($db) && $db->inTransaction()) {
        $db->rollBack();
    }
    log_step("FATAL ERROR: " . $e->getMessage());
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
