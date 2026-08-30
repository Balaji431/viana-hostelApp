<?php
/**
 * sync_institution_from_bookings.php
 *
 * Syncs users.Institution from the VStudy booked-rooms/external API.
 *
 * The booked-rooms API returns per-booking:
 *   registerNumber  → maps to users.username
 *   institutionName → e.g. "SMC - Medicine", "SIMATS - Engineering"
 *
 * This is called:
 *   - As a standalone cron step (daily midnight)
 *   - From sync_room_master.php (Step 2C)
 *   - Directly via HTTP for a manual trigger
 *
 * Cron example (add after sync_room_master cron):
 *   5 0 * * * root /usr/local/bin/php /var/www/html/utils/sync_institution_from_bookings.php >> /var/log/cron_institution_sync.log 2>&1
 */

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/api_config.php';

// Only set headers when called via HTTP
if (PHP_SAPI !== 'cli') {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
    header('Content-Type: application/json; charset=UTF-8');
    if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit(); }
}

function log_inst($msg) {
    $line = '[' . date('Y-m-d H:i:s') . '] ' . $msg . PHP_EOL;
    echo $line;
}

/**
 * Normalize institution names from VStudy API to canonical form.
 * Mirrors the normalizeInstitution() function in get_hostels.php.
 */
function normalizeInstitutionSync(string $inst): string {
    $inst = trim($inst);
    if (stripos($inst, 'Engineering') !== false || stripos($inst, 'SSE') !== false
        || (stripos($inst, 'SIMATS') !== false && stripos($inst, 'Medicine') === false && stripos($inst, 'Dentist') === false)
        || stripos($inst, 'Thandalam') !== false) {
        return 'SIMATS - Engineering';
    }
    if (stripos($inst, 'Medicine') !== false || stripos($inst, 'SMC') !== false) {
        return 'SMC - Medicine';
    }
    if (stripos($inst, 'Dentist') !== false || stripos($inst, 'SDC') !== false) {
        return 'SDC - Dentistry';
    }
    if (stripos($inst, 'Law') !== false || stripos($inst, 'SSL') !== false) {
        return 'SSL - Law';
    }
    if (stripos($inst, 'Management') !== false || stripos($inst, 'SSM') !== false) {
        return 'SSM - Management';
    }
    if (stripos($inst, 'Physical') !== false || stripos($inst, 'SSPE') !== false) {
        return 'SSPE - Physical Education';
    }
    if (stripos($inst, 'Nursing') !== false || stripos($inst, 'SNC') !== false) {
        return 'SNC - Nursing';
    }
    if (stripos($inst, 'Basic') !== false || stripos($inst, 'SIBMS') !== false) {
        return 'SIBMS - Basic Sciences';
    }
    if (stripos($inst, 'Allied') !== false || stripos($inst, 'SCAHS') !== false) {
        return 'SCAHS - Allied Health';
    }
    if (stripos($inst, 'Design') !== false || stripos($inst, 'STUDIO') !== false) {
        return 'STUDIO - Design School';
    }
    if (stripos($inst, 'Liberal') !== false || stripos($inst, 'SCLAS') !== false) {
        return 'SCLAS - Liberal Arts';
    }
    return $inst;
}

/**
 * Fetch all pages from booked-rooms/external API.
 * Returns flat array of booking records.
 */
function fetchBookedRoomsAll(): array {
    $page  = 1;
    $limit = 100;
    $all   = [];

    while (true) {
        $url = "https://vstudy.saveetha.com/api/hostel-settings/booked-rooms/external?page={$page}&limit={$limit}";

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

        $raw  = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err  = curl_error($ch);
        curl_close($ch);

        if ($err || $code !== 200) {
            log_inst("  [booked-rooms] HTTP $code error for page $page: $err");
            break;
        }

        $json  = json_decode($raw, true);
        $batch = $json['data'] ?? (is_array($json) ? $json : []);

        if (empty($batch)) break;

        $all = array_merge($all, $batch);

        $totalPages = $json['pagination']['totalPages'] ?? null;
        $hasNext    = $json['pagination']['hasNext'] ?? null;

        if ($hasNext === false) break;
        if ($totalPages !== null && $page >= $totalPages) break;
        if (count($batch) < $limit) break;

        $page++;
        usleep(15000); // 15ms between pages for fast sync
    }

    return $all;
}

try {
    $database = new Database();
    $db = $database->getConnection();
    if (!$db) throw new Exception('Database connection failed');

    log_inst('=== sync_institution_from_bookings.php started ===');

    // -----------------------------------------------------------------------
    // STEP 1: Fetch all booking records from VStudy
    // -----------------------------------------------------------------------
    log_inst('Step 1: Fetching booked-rooms from VStudy API...');
    $bookings = fetchBookedRoomsAll();
    log_inst('  Received ' . count($bookings) . ' booking records.');

    if (empty($bookings)) {
        log_inst('  No bookings returned — aborting institution sync.');
        echo json_encode(['status' => 'success', 'updated' => 0, 'message' => 'No bookings from API']);
        exit;
    }

    // -----------------------------------------------------------------------
    // STEP 2: Build a map of registerNumber -> normalized institutionName
    // Only include ACTIVE bookings with both fields present.
    // If a user has multiple bookings (rare), last one wins — usually same institution.
    // -----------------------------------------------------------------------
    log_inst('Step 2: Building registerNumber → institutionName map...');
    $regToInstitution = []; // [ 'REG001' => 'SMC - Medicine', ... ]

    foreach ($bookings as $booking) {
        $regNo   = trim($booking['registerNumber'] ?? '');
        $instRaw = trim($booking['institutionName'] ?? '');
        $status  = strtoupper(trim($booking['status'] ?? 'ACTIVE'));

        if (empty($regNo) || empty($instRaw)) continue;
        // Include ACTIVE and INACTIVE bookings — institution doesn't change with status
        $normalized = normalizeInstitutionSync($instRaw);
        $regToInstitution[$regNo] = $normalized;
    }

    log_inst('  Built map for ' . count($regToInstitution) . ' unique register numbers.');

    // -----------------------------------------------------------------------
    // STEP 3: Update users.Institution where it is missing or empty
    // We NEVER overwrite an existing institution — the API is the source of
    // truth only for gaps. If Institution is already set, we leave it.
    // To force a full overwrite, change the WHERE to remove the null check.
    // -----------------------------------------------------------------------
    log_inst('Step 3: Updating users.Institution from booked-rooms API (overwrites NULL, empty, and partial/bad values)...');

    // Known bad/partial values that must be overwritten with the real full institution name
    $badValues = "(
        Institution IS NULL
        OR TRIM(Institution) = ''
        OR TRIM(Institution) = '0'
        OR LOWER(TRIM(Institution)) = 'simats'
        OR LOWER(TRIM(Institution)) = 'smc'
        OR LOWER(TRIM(Institution)) = 'sdc'
        OR LOWER(TRIM(Institution)) = 'ssl'
        OR LOWER(TRIM(Institution)) = 'ssm'
        OR LOWER(TRIM(Institution)) = 'snc'
        OR LOWER(TRIM(Institution)) = 'sse'
        OR LOWER(TRIM(Institution)) = 'main'
        OR LOWER(TRIM(Institution)) = 'warden'
        OR LOWER(TRIM(Institution)) = 'admin'
        OR LOWER(TRIM(Institution)) = 'staff'
        OR LOWER(TRIM(Institution)) = 'saveetha'
        OR (Institution NOT LIKE '% - %' AND Institution NOT LIKE '%Engineering%'
            AND Institution NOT LIKE '%Medicine%' AND Institution NOT LIKE '%Dentist%'
            AND Institution NOT LIKE '%Law%' AND Institution NOT LIKE '%Nursing%'
            AND Institution NOT LIKE '%Sciences%' AND Institution NOT LIKE '%Allied%'
            AND Institution NOT LIKE '%Management%' AND Institution NOT LIKE '%Design%'
            AND Institution NOT LIKE '%Physical%' AND Institution NOT LIKE '%Pharmacy%'
            AND Institution NOT LIKE '%Therapy%' AND Institution NOT LIKE '%Liberal%')
    )";

    $updateStmt = $db->prepare("
        UPDATE users
        SET Institution = ?
        WHERE (username = ? OR biometric_id = ?)
          AND $badValues
    ");

    $updatedCount  = 0;
    $skippedCount  = 0;
    $notFoundCount = 0;

    foreach ($regToInstitution as $regNo => $institution) {
        $updateStmt->execute([$institution, $regNo, $regNo]);
        $rows = $updateStmt->rowCount();
        if ($rows > 0) {
            $updatedCount++;
        } else {
            // Check if user exists at all
            $chk = $db->prepare("SELECT id FROM users WHERE username = ? OR biometric_id = ? LIMIT 1");
            $chk->execute([$regNo, $regNo]);
            if ($chk->rowCount() > 0) {
                $skippedCount++; // User exists, Institution already populated — skip
            } else {
                $notFoundCount++; // Register number not in our users table — external-only booking
            }
        }
    }

    log_inst("  Updated: $updatedCount | Skipped (already set): $skippedCount | Not in users table: $notFoundCount");

    // -----------------------------------------------------------------------
    // STEP 4: Also sync from profile.institution → users.Institution as fallback
    // (Covers students registered locally but not in booked-rooms API yet)
    // -----------------------------------------------------------------------
    log_inst('Step 4: Syncing users.Institution from profile.institution (fallback)...');

    $fallbackRows = $db->exec("
        UPDATE users u
        JOIN profile p ON TRIM(u.username) = TRIM(p.reg_no)
        SET u.Institution = p.institution
        WHERE (u.Institution IS NULL OR TRIM(u.Institution) = '' OR TRIM(u.Institution) = '0')
          AND p.institution IS NOT NULL AND TRIM(p.institution) != ''
    ");

    log_inst("  Fallback: synced $fallbackRows users from profile table.");

    // -----------------------------------------------------------------------
    // STEP 5: Reverse — sync users.Institution → profile.institution gaps
    // -----------------------------------------------------------------------
    log_inst('Step 5: Syncing profile.institution from users.Institution (reverse fill)...');

    $reverseRows = $db->exec("
        UPDATE profile p
        JOIN users u ON TRIM(p.reg_no) = TRIM(u.username)
        SET p.institution = u.Institution
        WHERE (p.institution IS NULL OR TRIM(p.institution) = '')
          AND u.Institution IS NOT NULL AND TRIM(u.Institution) != ''
    ");

    log_inst("  Reverse: synced $reverseRows profile rows from users table.");

    log_inst('=== sync_institution_from_bookings.php completed successfully ===');

    $result = [
        'status'           => 'success',
        'bookings_fetched' => count($bookings),
        'unique_reg_nos'   => count($regToInstitution),
        'users_updated'    => $updatedCount,
        'users_skipped'    => $skippedCount,
        'not_in_users'     => $notFoundCount,
        'profile_fallback' => (int)$fallbackRows,
        'profile_reverse'  => (int)$reverseRows,
        'ran_at'           => date('Y-m-d H:i:s'),
    ];
    echo json_encode($result, JSON_PRETTY_PRINT);

} catch (Exception $e) {
    log_inst('FATAL ERROR: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
