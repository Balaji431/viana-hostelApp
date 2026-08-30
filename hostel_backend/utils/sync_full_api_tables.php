<?php
/**
 * sync_full_api_tables.php
 *
 * Synchronizes exact live counts from both external VStudy APIs into local cache tables:
 * 1. new_api: Populated from https://vstudy.saveetha.com/api/hostel-settings/booked-rooms/external (~4,462 records)
 * 2. old_api: Populated from https://vstudy.saveetha.com/api/hostel-applications/paid (~3,584 records)
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
}

function log_tbl($msg) {
    $line = '[' . date('Y-m-d H:i:s') . '] ' . $msg . PHP_EOL;
    echo $line;
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
            log_tbl("  API error HTTP $code on page $page: $err");
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
        usleep(15000); // 15ms throttle
    }

    return $all;
}

try {
    $database = new Database();
    $db = $database->getConnection();
    if (!$db) throw new Exception("Database connection failed");

    log_tbl("=== sync_full_api_tables.php started ===");

    // -------------------------------------------------------------------------
    // PART 1: SYNC new_api (booked-rooms/external)
    // -------------------------------------------------------------------------
    log_tbl("Step 1: Fetching booked-rooms/external records...");
    $bookedRecords = fetchAllFromApi("https://vstudy.saveetha.com/api/hostel-settings/booked-rooms/external");
    $bookedCount = count($bookedRecords);
    log_tbl("  Fetched $bookedCount total records from booked-rooms API.");

    if (!empty($bookedRecords)) {
        log_tbl("  Truncating new_api table...");
        $db->exec("TRUNCATE TABLE new_api");

        log_tbl("  Inserting records into new_api...");
        $insertNewStmt = $db->prepare("
            INSERT INTO new_api (
                booking_id, register_number, student_name, email, phone, gender,
                booker_type, hostel_name, campus, room_number, room_type,
                monthly_fee, deduction_status, status, renewal_date, check_in,
                check_out, booked_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");

        $db->beginTransaction();
        $insertedNew = 0;
        foreach ($bookedRecords as $b) {
            $insertNewStmt->execute([
                $b['bookingId'] ?? $b['id'] ?? null,
                trim($b['registerNumber'] ?? ''),
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
                $b['checkIn'] ?? null,
                $b['checkOut'] ?? null,
                $b['bookedAt'] ?? null
            ]);
            $insertedNew++;
        }
        $db->commit();
        log_tbl("  Successfully inserted $insertedNew rows into new_api.");
    }

    // -------------------------------------------------------------------------
    // PART 2: SYNC old_api (hostel-applications/paid)
    // -------------------------------------------------------------------------
    log_tbl("Step 2: Fetching hostel-applications/paid records...");
    $paidRecords = fetchAllFromApi("https://vstudy.saveetha.com/api/hostel-applications/paid");
    $paidCount = count($paidRecords);
    log_tbl("  Fetched $paidCount total records from paid-applications API.");

    if (!empty($paidRecords)) {
        log_tbl("  Truncating old_api table...");
        $db->exec("TRUNCATE TABLE old_api");

        log_tbl("  Inserting records into old_api...");
        $insertOldStmt = $db->prepare("
            INSERT INTO old_api (
                application_id, receipt_number, roll_number, student_name, email,
                phone, hostel_name, campus, room_type, occupancy, gender,
                room_rent, food_fee, caution_deposit, total_fee, paid_at, applied_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");

        $db->beginTransaction();
        $insertedOld = 0;
        foreach ($paidRecords as $p) {
            $student = $p['student'] ?? [];
            $hostel  = $p['hostel'] ?? [];
            $room    = $p['room'] ?? [];
            $fees    = $p['fees'] ?? [];

            $insertOldStmt->execute([
                $p['applicationId'] ?? $p['id'] ?? null,
                $p['receiptNumber'] ?? null,
                trim($student['rollNumber'] ?? $student['registerNumber'] ?? ''),
                trim($student['name'] ?? ''),
                trim($student['email'] ?? ''),
                trim($student['phone'] ?? ''),
                trim($hostel['name'] ?? ''),
                trim($hostel['campus'] ?? ''),
                trim($room['roomType'] ?? ''),
                $room['occupancy'] ?? null,
                trim($room['gender'] ?? ''),
                (float)($fees['roomRent'] ?? 0),
                (float)($fees['food'] ?? 0),
                (float)($fees['cautionDeposit'] ?? 0),
                (float)($fees['total'] ?? 0),
                $p['paidAt'] ?? null,
                $p['appliedAt'] ?? null
            ]);
            $insertedOld++;
        }
        $db->commit();
        log_tbl("  Successfully inserted $insertedOld rows into old_api.");
    }

    $finalNewCount = (int)$db->query("SELECT COUNT(*) FROM new_api")->fetchColumn();
    $finalOldCount = (int)$db->query("SELECT COUNT(*) FROM old_api")->fetchColumn();

    log_tbl("=== Completed successfully! ===");
    log_tbl("Final new_api count: $finalNewCount");
    log_tbl("Final old_api count: $finalOldCount");

    echo json_encode([
        'status' => 'success',
        'new_api_count' => $finalNewCount,
        'old_api_count' => $finalOldCount,
        'ran_at' => date('Y-m-d H:i:s')
    ], JSON_PRETTY_PRINT);

} catch (Exception $e) {
    if (isset($db) && $db->inTransaction()) {
        $db->rollBack();
    }
    log_tbl("FATAL ERROR: " . $e->getMessage());
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
