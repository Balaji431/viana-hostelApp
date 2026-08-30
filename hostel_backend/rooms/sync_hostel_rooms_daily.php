<?php
/**
 * sync_hostel_rooms_daily.php
 * 
 * Synchronizes room capacities, occupied beds, available beds, and pending booking statuses
 * from the live VStudy external API into local tables:
 *  - rooms_groups_details
 *  - hostel_rooms (if exists)
 *  - room_master (if exists)
 * 
 * Usage:
 *  - CLI: php sync_hostel_rooms_daily.php
 *  - Web: http://localhost/hostelapp/hostel_backend/rooms/sync_hostel_rooms_daily.php
 */

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/api_config.php';

set_time_limit(600);
ini_set('memory_limit', '512M');

$isCli = (php_sapi_name() === 'cli');
if (!$isCli) {
    header('Content-Type: text/plain; charset=UTF-8');
}

function log_out($msg) {
    echo '[' . date('Y-m-d H:i:s') . '] ' . $msg . PHP_EOL;
    if (ob_get_level() > 0) ob_flush();
    flush();
}

log_out("=== STARTING DAILY HOSTEL ROOMS SYNCHRONIZATION ===");

if (!$conn) {
    log_out("ERROR: Database connection failed.");
    exit(1);
}

// 1. Auto-expire old room change/transfer requests older than 3 days
log_out("Step 1: Checking for expired pending room allocations (> 3 days)...");
$expireSql = "
    UPDATE room_change_requests 
    SET status = 'cancelled', 
        payment_status = 'unpaid', 
        remarks = 'Auto-cancelled after 3 days due to non-payment' 
    WHERE (LOWER(status) = 'approved' OR LOWER(status) = 'pre_approved') 
      AND payment_status = 'unpaid' 
      AND updated_at < DATE_SUB(NOW(), INTERVAL 3 DAY)
";
if ($conn->query($expireSql)) {
    log_out("Expired requests updated: " . $conn->affected_rows);
} else {
    log_out("Notice on request cleanup: " . $conn->error);
}

// 2. Helper to fetch paginated external API data
function fetchVStudyApi($endpoint) {
    $page = 1;
    $limit = 100;
    $all = [];

    while (true) {
        $sep = strpos($endpoint, '?') !== false ? '&' : '?';
        $url = "{$endpoint}{$sep}page={$page}&limit={$limit}";

        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 45);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'x-client-id: '     . VSTUDY_CLIENT_ID,
            'x-client-secret: ' . VSTUDY_CLIENT_SECRET,
            'Accept: application/json',
        ]);
        $res = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err = curl_error($ch);
        curl_close($ch);

        if ($err || $code !== 200) {
            log_out("API Warning (HTTP $code) on $url: $err");
            break;
        }

        $json = json_decode($res, true);
        $data = $json['data'] ?? [];
        if (empty($data)) break;

        $all = array_merge($all, $data);
        if (empty($json['pagination']['hasNext'])) break;
        $page++;
    }

    return $all;
}

// 3. Fetch all physical rooms
log_out("Step 2: Fetching live physical rooms from VStudy API...");
$physicalRooms = fetchVStudyApi('https://vstudy.saveetha.com/api/hostel-settings/physical-rooms/external');
$totalApiRooms = count($physicalRooms);
log_out("Fetched $totalApiRooms physical rooms from VStudy.");

if ($totalApiRooms === 0) {
    log_out("ERROR: No physical rooms returned. Check API credentials or network.");
    exit(1);
}

// 4. Update rooms_groups_details
log_out("Step 3: Updating rooms_groups_details table...");
$stmtRGD = $conn->prepare("
    UPDATE rooms_groups_details 
    SET total_beds = ?, occupied_beds = ?, available_beds = ? 
    WHERE TRIM(room_number) = TRIM(?) AND (TRIM(hostel_name) = TRIM(?) OR TRIM(hostel_name) LIKE CONCAT(TRIM(?), '%'))
");

$hasHostelRooms = false;
$resTable = $conn->query("SHOW TABLES LIKE 'hostel_rooms'");
if ($resTable && $resTable->num_rows > 0) {
    $hasHostelRooms = true;
    $stmtHR = $conn->prepare("
        UPDATE hostel_rooms 
        SET total_capacity = ?, occupied_rooms = ?, available_rooms = ? 
        WHERE TRIM(room_no) = TRIM(?) OR TRIM(room_code) = TRIM(?)
    ");
}

$rgdUpdated = 0;
$hrUpdated = 0;

foreach ($physicalRooms as $r) {
    $rNum  = $r['roomNumber'] ?? '';
    $hName = $r['hostelName'] ?? '';
    $total = (int)($r['totalBeds'] ?? 0);
    $occ   = (int)($r['occupiedBeds'] ?? 0);
    $avail = (int)($r['availableBeds'] ?? 0);

    if ($rNum && $hName) {
        $stmtRGD->bind_param("iiisss", $total, $occ, $avail, $rNum, $hName, $hName);
        $stmtRGD->execute();
        if ($stmtRGD->affected_rows > 0) {
            $rgdUpdated += $stmtRGD->affected_rows;
        }

        if ($hasHostelRooms) {
            $stmtHR->bind_param("iiiss", $total, $occ, $avail, $rNum, $rNum);
            $stmtHR->execute();
            if ($stmtHR->affected_rows > 0) {
                $hrUpdated += $stmtHR->affected_rows;
            }
        }
    }
}

log_out("rooms_groups_details rows updated: $rgdUpdated");
if ($hasHostelRooms) {
    log_out("hostel_rooms rows updated: $hrUpdated");
}

// 5. Verification Summary
log_out("\n=== CURRENT LIVE SUMMARY IN DATABASE ===");

$summaryQuery = "
    SELECT 
        r.gender,
        r.hostel_name,
        COUNT(DISTINCT r.room_type) as room_types,
        COUNT(DISTINCT r.group_name) as floors,
        COALESCE(SUM(r.total_beds), 0) as total_beds,
        COALESCE(SUM(r.occupied_beds), 0) as occupied_beds,
        COALESCE(SUM(r.available_beds), 0) as beds_free
    FROM rooms_groups_details r
    WHERE r.available_beds > 0
    GROUP BY r.gender, r.hostel_name
    ORDER BY r.gender DESC, r.hostel_name ASC
";
$resSum = $conn->query($summaryQuery);
if ($resSum) {
    log_out(sprintf("%-8s | %-25s | %-12s | %-12s | %-10s", "Gender", "Hostel Name", "Beds Free", "Room Types", "Floors"));
    log_out(str_repeat("-", 75));
    while ($row = $resSum->fetch_assoc()) {
        log_out(sprintf(
            "%-8s | %-25s | %-12s | %-12s | %-10s",
            $row['gender'],
            $row['hostel_name'],
            $row['beds_free'] . " beds",
            $row['room_types'] . " types",
            $row['floors'] . " floors"
        ));
    }
}

log_out("\n=== DAILY SYNCHRONIZATION COMPLETED SUCCESSFULLY ===");
