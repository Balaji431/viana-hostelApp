<?php
/**
 * get_paid_hostel_type.php
 *
 * Returns paid hostel details for a given student roll number.
 * 
 * Flow:
 *   1. Derive the roll number from the request (GET ?register_no=...).
 *   2. Look up vstudy_payments locally (fast path).
 *   3. If not found locally, query the external VStudy API using proper credentials.
 *   4. If found externally, upsert the record into vstudy_payments and return.
 *   5. Return structured HTTP responses: 200 / 404 / 503 / 500.
 *
 * Response codes:
 *   200 — paid hostel details found (local or external)
 *   404 — no paid hostel application found for this roll number
 *   503 — external payment service temporarily unavailable
 *   500 — unexpected server/database error
 */

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header('Content-Type: application/json; charset=UTF-8');

$request_method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($request_method === 'OPTIONS') {
    http_response_code(200);
    exit();
}

// ── helper ──────────────────────────────────────────────────────────────────

function normalizeRoll(string $raw): string
{
    return trim((string) $raw);   // trim whitespace; keep leading zeros
}

function buildPayload(array $row): array
{
    $hPref    = $row['hostel_preference'] ?? '';
    $gender   = $row['gender'] ?? '';
    $hType    = (stripos($hPref, 'girls') !== false || stripos($gender, 'female') !== false) ? 'Girls' : 'Boys';
    $facility = (stripos($hPref, 'non ac') !== false || stripos($hPref, 'non-ac') !== false) ? 'Non AC' : 'AC';
    $amount   = (float)($row['paid_amount'] ?? 0.0);

    return [
        'register_no'           => $row['roll_number'],
        'student_name'          => $row['student_name'] ?? '',
        'fee_paid'              => strtolower($row['payment_status'] ?? '') === 'paid',
        'paid_amount'           => $amount,
        'hostel_type'           => $hType,
        'hostel_name'           => $row['hostel_name'] ?? $hType,
        'room_type'             => $hPref,
        'facility'              => $facility,
        'gender'                => $gender,
        'institution'           => $row['campus'] ?? 'Saveetha School of Engineering',
        'academic_year'         => $row['academic_year'] ?? '',
        'campus'                => $row['campus'] ?? '',
        'hostel_preference'     => $hPref,
        'payment_status'        => $row['payment_status'] ?? '',
        'application_status'    => $row['application_status'] ?? 'Application Verified',
        'paid_date'             => $row['paid_date'] ?? '',
        'transaction_reference' => $row['transaction_reference'] ?? '',
    ];
}

// ── input validation ─────────────────────────────────────────────────────────

$raw_reg = $_GET['register_no'] ?? '';
if ($raw_reg === '') {
    http_response_code(400);
    echo json_encode(['success' => false, 'http_status' => 400, 'message' => 'Registration number is required.']);
    exit();
}

$register_no = normalizeRoll($raw_reg);

// ── backend logging ──────────────────────────────────────────────────────────

$log_prefix = "[get_paid_hostel_type] roll=$register_no";
error_log("$log_prefix — request started");

// ── database connection ───────────────────────────────────────────────────────

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/api_config.php';

try {
    $db   = new Database();
    $conn = $db->getConnection();
    if (!$conn) throw new \RuntimeException('DB connection failed');
} catch (\Throwable $ex) {
    error_log("$log_prefix — DB error: " . $ex->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'http_status' => 500, 'message' => 'Database connection failed.']);
    exit();
}

// ── 1. Local lookup ───────────────────────────────────────────────────────────

try {
    $stmt = $conn->prepare(
        "SELECT * FROM vstudy_payments WHERE TRIM(roll_number) = TRIM(:reg) LIMIT 1"
    );
    $stmt->execute([':reg' => $register_no]);
    $localRow = $stmt->fetch(PDO::FETCH_ASSOC);

    if ($localRow) {
        error_log("$log_prefix — found in vstudy_payments (local DB)");
        http_response_code(200);
        echo json_encode(['success' => true, 'source' => 'local', 'data' => buildPayload($localRow)]);
        exit();
    }
    error_log("$log_prefix — not found locally; querying external API");
} catch (\Throwable $ex) {
    error_log("$log_prefix — local DB query error: " . $ex->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'http_status' => 500, 'message' => 'Server error checking local payment data.']);
    exit();
}

// ── 2. External VStudy API lookup ─────────────────────────────────────────────
//
// The external API is paginated (default 20 records/page, 700+ total).
// Rather than pulling all pages, we pass the roll number as a query filter
// if the API supports it. If not, we scan page by page until found or exhausted.
//
// Known external record structure:
//   { applicationId, receiptNumber,
//     student: { id, name, email, rollNumber },
//     hostel: { name, campus },
//     room: { roomType, occupancy, gender },
//     fees: { roomRent, food, cautionDeposit, total },
//     paidAt, appliedAt }
// ─────────────────────────────────────────────────────────────────────────────

$found_external   = null;
$ext_error        = null;
$ext_http_code    = 0;

function callExternalPage(string $baseUrl, int $page, string $clientId, string $secret): array
{
    $url = $baseUrl . '?page=' . $page . '&limit=100';
    $ch  = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 15,
        CURLOPT_SSL_VERIFYPEER => false,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_IPRESOLVE      => CURL_IPRESOLVE_V4,
        CURLOPT_HTTPHEADER     => [
            'x-client-id: '     . $clientId,
            'x-client-secret: ' . $secret,
            'Accept: application/json',
        ],
    ]);
    $body     = curl_exec($ch);
    $httpCode = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlErr  = curl_error($ch);
    curl_close($ch);

    return ['body' => $body, 'http_code' => $httpCode, 'curl_error' => $curlErr];
}

// Try page 1 first to get pagination info, then scan if needed
$page       = 1;
$maxPages   = 50; // safety cap; 50 × 100 = 5000 students
$searching  = true;

while ($searching && $page <= $maxPages) {
    $result     = callExternalPage(VSTUDY_PAYMENT_API_URL, $page, VSTUDY_CLIENT_ID, VSTUDY_CLIENT_SECRET);
    $ext_http_code = $result['http_code'];

    if ($result['curl_error'] || $result['http_code'] !== 200) {
        $ext_error = $result['curl_error']
            ? "cURL error: {$result['curl_error']}"
            : "External API HTTP {$result['http_code']}";
        error_log("$log_prefix — external API failed (page $page): $ext_error");
        break;
    }

    $decoded = json_decode($result['body'], true);
    if (!is_array($decoded)) {
        $ext_error = "External API returned invalid JSON (page $page)";
        error_log("$log_prefix — $ext_error");
        break;
    }

    $records    = $decoded['data'] ?? $decoded;
    $pagination = $decoded['pagination'] ?? [];

    if (!is_array($records) || count($records) === 0) {
        // No more data
        $searching = false;
        break;
    }

    foreach ($records as $item) {
        $apiRoll = normalizeRoll((string)(
            $item['student']['rollNumber'] ??
            $item['roll_number'] ??
            $item['reg_no'] ??
            ''
        ));

        if (strcasecmp($apiRoll, $register_no) === 0) {
            $found_external = $item;
            $searching      = false;
            break;
        }
    }

    // Determine if more pages exist
    $totalPages = (int)($pagination['totalPages'] ?? 1);
    $hasNext    = (bool)($pagination['hasNext'] ?? ($page < $totalPages));

    if (!$hasNext || $page >= $totalPages) {
        $searching = false;
    }

    $page++;
}

// ── 3. Process external result ────────────────────────────────────────────────

if ($found_external === null) {
    if ($ext_error !== null) {
        // External API unavailable
        error_log("$log_prefix — external API unavailable: $ext_error");
        http_response_code(503);
        echo json_encode([
            'success'     => false,
            'http_status' => 503,
            'message'     => 'Payment service temporarily unavailable. Please try again later.',
        ]);
        exit();
    }

    // Not found anywhere
    error_log("$log_prefix — not found in external API either → 404");
    http_response_code(404);
    echo json_encode([
        'success'     => false,
        'http_status' => 404,
        'message'     => 'No paid hostel application found for this roll number.',
    ]);
    exit();
}

// ── 4. Map external record → vstudy_payments row ─────────────────────────────

error_log("$log_prefix — found in external API; upserting to vstudy_payments");

$hostelPref  = $found_external['room']['roomType'] ?? '';
$genderApi   = $found_external['room']['gender'] ?? 'Female';
$hostelName  = $found_external['hostel']['name'] ?? '';
$campus      = $found_external['hostel']['campus'] ?? '';
$studentName = $found_external['student']['name'] ?? '';
$totalFees   = (float)($found_external['fees']['total'] ?? 0.0);
$receiptNo   = $found_external['receiptNumber'] ?? '';
$paidAt      = !empty($found_external['paidAt'])
    ? date('Y-m-d H:i:s', strtotime($found_external['paidAt']))
    : date('Y-m-d H:i:s');

try {
    // Upsert so that repeated calls are idempotent
    $upsert = $conn->prepare("
        INSERT INTO vstudy_payments
            (student_name, roll_number, gender, campus, hostel_preference, hostel_name,
             payment_status, application_status, paid_date, transaction_reference, paid_amount)
        VALUES
            (:student_name, :roll, :gender, :campus, :hostel_pref, :hostel_name,
             'Paid', 'Application Verified', :paid_date, :receipt, :amount)
        ON DUPLICATE KEY UPDATE
            student_name        = VALUES(student_name),
            gender              = VALUES(gender),
            campus              = VALUES(campus),
            hostel_preference   = VALUES(hostel_preference),
            hostel_name         = VALUES(hostel_name),
            payment_status      = VALUES(payment_status),
            application_status  = VALUES(application_status),
            paid_date           = VALUES(paid_date),
            transaction_reference = VALUES(transaction_reference),
            paid_amount         = VALUES(paid_amount),
            updated_at          = CURRENT_TIMESTAMP
    ");
    $upsert->execute([
        ':student_name' => $studentName,
        ':roll'         => $register_no,
        ':gender'       => $genderApi,
        ':campus'       => $campus,
        ':hostel_pref'  => $hostelPref,
        ':hostel_name'  => $hostelName,
        ':paid_date'    => $paidAt,
        ':receipt'      => $receiptNo,
        ':amount'       => $totalFees,
    ]);
    error_log("$log_prefix — upsert OK");
} catch (\Throwable $ex) {
    // Upsert failure is non-fatal: still return the data we got from the API
    error_log("$log_prefix — upsert failed (non-fatal): " . $ex->getMessage());
}

// Build a synthetic row matching the buildPayload() shape
$syntheticRow = [
    'student_name'          => $studentName,
    'roll_number'           => $register_no,
    'gender'                => $genderApi,
    'academic_year'         => '',
    'campus'                => $campus,
    'hostel_preference'     => $hostelPref,
    'hostel_name'           => $hostelName,
    'payment_status'        => 'Paid',
    'application_status'    => 'Application Verified',
    'paid_date'             => $paidAt,
    'transaction_reference' => $receiptNo,
    'paid_amount'           => $totalFees,
];

error_log("$log_prefix — returning 200 (source: external)");
http_response_code(200);
echo json_encode([
    'success' => true,
    'source'  => 'external',
    'data'    => buildPayload($syntheticRow),
]);
exit();
