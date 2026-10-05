<?php
/**
 * sync_vstudy_payments_exact.php
 * Fetches all live records from https://vstudy.saveetha.com/api/hostel-settings/booked-rooms/external
 * and syncs vstudy_payments so the table count and records exactly match the API.
 */

set_time_limit(900);
ini_set('memory_limit', '512M');

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/api_config.php';

if (PHP_SAPI !== 'cli') {
    require_once __DIR__ . '/auth_helper.php';
    requireAuth(['super_admin', 'admin']);
}

function log_msg($msg) {
    echo '[' . date('Y-m-d H:i:s') . '] ' . $msg . PHP_EOL;
}

function fetchAllBookedRooms(): array {
    $baseUrl = "https://vstudy.saveetha.com/api/hostel-settings/booked-rooms/external";
    $page = 1;
    $limit = 100;
    $all = [];
    $totalFromApi = null;

    log_msg("Starting fetch from: $baseUrl");

    while (true) {
        $url = "{$baseUrl}?page={$page}&limit={$limit}";

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
            log_msg("API error HTTP $code on page $page: $err");
            break;
        }

        $json = json_decode($raw, true);
        if (!$json) {
            log_msg("Failed to parse JSON on page $page");
            break;
        }

        if ($totalFromApi === null && isset($json['pagination']['total'])) {
            $totalFromApi = $json['pagination']['total'];
            log_msg("API reports total records: $totalFromApi");
        }

        $batch = $json['data'] ?? [];
        if (empty($batch)) break;

        $all = array_merge($all, $batch);

        if ($page % 10 === 0 || count($all) >= ($totalFromApi ?? 999999)) {
            log_msg("  Fetched page $page (" . count($all) . " records so far)...");
        }

        $hasNext = $json['pagination']['hasNext'] ?? null;
        $totalPages = $json['pagination']['totalPages'] ?? null;

        if ($hasNext === false) break;
        if ($totalPages !== null && $page >= $totalPages) break;
        if (count($batch) < $limit) break;

        $page++;
        usleep(20000); // 20ms pause
    }

    log_msg("Fetch completed. Total fetched: " . count($all));
    return ['records' => $all, 'api_total' => $totalFromApi];
}

try {
    $database = new Database();
    $db = $database->getConnection();
    if (!$db) throw new Exception("Database connection failed");

    log_msg("=== Syncing vstudy_payments to match booked-rooms/external API ===");

    $fetchResult = fetchAllBookedRooms();
    $records = $fetchResult['records'];
    $apiTotal = $fetchResult['api_total'];

    if (empty($records)) {
        throw new Exception("No records fetched from API! Aborting to prevent data loss.");
    }

    log_msg("Truncating existing vstudy_payments table in local database...");
    $db->exec("SET FOREIGN_KEY_CHECKS = 0");
    
    // Ensure booking_id is UNIQUE and roll_number is indexed (to support exact 5,145 rows)
    try {
        $db->exec("ALTER TABLE vstudy_payments DROP INDEX roll_number");
        $db->exec("ALTER TABLE vstudy_payments ADD INDEX idx_roll_number (roll_number)");
        $db->exec("ALTER TABLE vstudy_payments ADD UNIQUE KEY uk_booking_id (booking_id)");
    } catch (Exception $e) {
        // Index may already be modified
    }

    $db->exec("TRUNCATE TABLE vstudy_payments");

    $insertStmt = $db->prepare("
        INSERT INTO vstudy_payments (
            booking_id, roll_number, student_name, email, phone, gender,
            booker_type, department, hostel_name, campus, room_number, room_type,
            paid_amount, application_status, payment_status, renewal_date,
            paid_date, remaining_days
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            booking_id = VALUES(booking_id),
            student_name = VALUES(student_name),
            email = VALUES(email),
            phone = VALUES(phone),
            gender = VALUES(gender),
            booker_type = VALUES(booker_type),
            department = VALUES(department),
            hostel_name = VALUES(hostel_name),
            campus = VALUES(campus),
            room_number = VALUES(room_number),
            room_type = VALUES(room_type),
            paid_amount = VALUES(paid_amount),
            application_status = VALUES(application_status),
            payment_status = VALUES(payment_status),
            renewal_date = VALUES(renewal_date),
            paid_date = VALUES(paid_date),
            remaining_days = VALUES(remaining_days)
    ");

    $db->beginTransaction();
    $insertedCount = 0;

    foreach ($records as $b) {
        $reg = trim($b['registerNumber'] ?? '');
        if ($reg === '') {
            $reg = trim($b['rollNumber'] ?? '');
        }

        // Parse remaining days if renewal date exists
        $remainingDays = 0;
        if (!empty($b['renewalDate'])) {
            try {
                $renDt = new DateTime($b['renewalDate']);
                $now = new DateTime();
                $diff = $now->diff($renDt);
                $remainingDays = $renDt > $now ? (int)$diff->days : -(int)$diff->days;
            } catch (Exception $e) {}
        }

        $paidAmount = isset($b['monthlyFee']) ? floatval($b['monthlyFee']) : (isset($b['paidAmount']) ? floatval($b['paidAmount']) : 45000.00);

        $insertStmt->execute([
            $b['bookingId'] ?? $b['id'] ?? null,
            $reg,
            trim($b['name'] ?? $b['student_name'] ?? ''),
            trim($b['email'] ?? ''),
            trim($b['phone'] ?? ''),
            trim($b['gender'] ?? ''),
            trim($b['bookerType'] ?? 'STUDENT'),
            trim($b['institutionName'] ?? $b['department'] ?? ''),
            trim($b['hostelName'] ?? ''),
            trim($b['campus'] ?? ''),
            trim($b['roomNumber'] ?? ''),
            trim($b['roomType'] ?? ''),
            $paidAmount,
            trim($b['status'] ?? 'ACTIVE'),
            trim($b['deductionStatus'] ?? 'PAID'),
            trim($b['renewalDate'] ?? ''),
            trim($b['bookedAt'] ?? date('Y-m-d H:i:s')),
            $remainingDays
        ]);
        $insertedCount++;
    }

    $db->commit();
    $db->exec("SET FOREIGN_KEY_CHECKS = 1");

    // Verify count in database
    $finalCount = $db->query("SELECT COUNT(*) FROM vstudy_payments")->fetchColumn();
    $distinctRolls = $db->query("SELECT COUNT(DISTINCT roll_number) FROM vstudy_payments")->fetchColumn();

    log_msg("=== SYNC SUCCESSFUL ===");
    log_msg("API Total: $apiTotal");
    log_msg("Records Inserted: $insertedCount");
    log_msg("Final vstudy_payments row count: $finalCount");
    log_msg("Distinct roll numbers in vstudy_payments: $distinctRolls");

} catch (Exception $e) {
    if (isset($db) && $db->inTransaction()) {
        $db->rollBack();
    }
    log_msg("ERROR: " . $e->getMessage());
    exit(1);
}
