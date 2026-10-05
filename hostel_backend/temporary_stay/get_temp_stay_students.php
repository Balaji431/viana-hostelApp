<?php
/**
 * get_temp_stay_students.php
 * ─────────────────────────────────────────────────────────────────────────────
 * API: Temporary Stay Students
 *
 * Returns temporary stay guest records with powerful filters.
 * "Currently staying" = status=allocated + payment_status=paid + to_date >= today.
 *
 * GET Parameters (all optional):
 *   ?filter=active         active (default) / all / pending / approved / timed_out / rejected
 *   ?hostel=Kaveri Hostel  filter by hostel name
 *   ?gender=Male           filter by gender (Male / Female)
 *   ?warden=Manoj A        filter by warden name
 *   ?from=YYYY-MM-DD       filter by from_date (stay start)
 *   ?to=YYYY-MM-DD         filter by to_date (stay end)
 *   ?search=RAAMSUNDAR     search by name / email / phone
 *   ?page=1                pagination (default: 1)
 *   ?per_page=50           records per page (default: 50, max: 200)
 */

// Prevent caching — ensure real-time data
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Cache-Control: post-check=0, pre-check=0', false);
header('Pragma: no-cache');
header('Expires: 0');

// CORS and response headers
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept, X-User-Id, X-User-Username, X-User-Role, x-client-id, x-client-secret, X-Client-Id, X-Client-Secret');
header('Access-Control-Max-Age: 86400');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/api_config.php';
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/auth_helper.php';

// Helper to extract request headers case-insensitively
function getRequestHeader($name) {
    $serverKey = 'HTTP_' . strtoupper(str_replace('-', '_', $name));
    if (!empty($_SERVER[$serverKey])) {
        return trim($_SERVER[$serverKey]);
    }
    if (function_exists('getallheaders')) {
        $headers = getallheaders();
        if (is_array($headers)) {
            foreach ($headers as $k => $v) {
                if (strcasecmp($k, $name) === 0) {
                    return trim($v);
                }
            }
        }
    }
    if (function_exists('apache_request_headers')) {
        $headers = apache_request_headers();
        if (is_array($headers)) {
            foreach ($headers as $k => $v) {
                if (strcasecmp($k, $name) === 0) {
                    return trim($v);
                }
            }
        }
    }
    return '';
}

// Authentication: Check JWT Bearer token first
$token = getBearerToken();
$jwtUser = $token ? validateJWT($token) : null;
$validUserAuth = ($jwtUser && in_array(strtolower($jwtUser['role'] ?? ''), ['admin', 'super_admin', 'warden', 'developer', 'student']));

// Client credential verification (for external server-to-server calls)
$expectedClientId     = defined('VSTUDY_CLIENT_ID') ? VSTUDY_CLIENT_ID : '';
$expectedClientSecret = defined('VSTUDY_CLIENT_SECRET') ? VSTUDY_CLIENT_SECRET : '';

$incomingClientId     = getRequestHeader('x-client-id');
$incomingClientSecret = getRequestHeader('x-client-secret');

$validApiAuth = (!empty($incomingClientId) && !empty($incomingClientSecret) &&
              !empty($expectedClientId) && !empty($expectedClientSecret) &&
              hash_equals($expectedClientId, $incomingClientId) &&
              hash_equals($expectedClientSecret, $incomingClientSecret));

if (!$validUserAuth && !$validApiAuth) {
    http_response_code(401);
    echo json_encode([
        'success' => false,
        'message' => 'Unauthorized: Invalid or missing authentication credentials.'
    ], JSON_PRETTY_PRINT);
    exit();
}

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    http_response_code(503);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit();
}

try {
    // ── Parameters ─────────────────────────────────────────────────────────────
    $filter  = trim($_GET['filter']   ?? 'active');
    $hostel  = trim($_GET['hostel']   ?? '');
    $gender  = trim($_GET['gender']   ?? '');
    $warden  = trim($_GET['warden']   ?? '');
    $from    = trim($_GET['from']     ?? '');
    $to      = trim($_GET['to']       ?? '');
    $search  = trim($_GET['search']   ?? '');
    $page    = max(1, (int)($_GET['page'] ?? 1));
    $perPage = 10; // Fixed 10 records per page as requested
    $offset  = ($page - 1) * $perPage;

    // ── WHERE builder ──────────────────────────────────────────────────────────
    $where  = [];
    $params = [];

    // Filter mode
    switch ($filter) {
        case 'active':
            // Currently inside the hostel right now
            $where[] = "tsr.status = 'allocated'";
            $where[] = "tsr.payment_status = 'paid'";
            $where[] = "tsr.to_date >= CURDATE()";
            break;
        case 'pending':
            $where[] = "tsr.status = 'pending'";
            break;
        case 'approved':
            $where[] = "tsr.status = 'approved'";
            $where[] = "tsr.payment_status = 'unpaid'";
            break;
        case 'timed_out':
            $where[] = "tsr.status = 'timed_out'";
            break;
        case 'rejected':
            $where[] = "tsr.status = 'rejected'";
            break;
        case 'completed':
            // Stayed and left
            $where[] = "tsr.status = 'allocated'";
            $where[] = "tsr.payment_status = 'paid'";
            $where[] = "tsr.to_date < CURDATE()";
            break;
        case 'all':
        default:
            // No status filter
            break;
    }

    if (!empty($hostel)) {
        $where[]             = "tsr.hostel_name LIKE :hostel";
        $params[':hostel']   = '%' . $hostel . '%';
    }
    if (!empty($gender) && in_array($gender, ['Male','Female'])) {
        $where[]             = "tsr.gender = :gender";
        $params[':gender']   = $gender;
    }
    if (!empty($warden)) {
        $where[]             = "tsr.warden_name LIKE :warden";
        $params[':warden']   = '%' . $warden . '%';
    }
    if (!empty($from) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $from)) {
        $where[]             = "tsr.from_date >= :from";
        $params[':from']     = $from;
    }
    if (!empty($to) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $to)) {
        $where[]             = "tsr.to_date <= :to";
        $params[':to']       = $to;
    }
    if (!empty($search)) {
        $where[]             = "(tsr.full_name LIKE :search OR tsr.email LIKE :search2 OR tsr.phone LIKE :search3)";
        $params[':search']   = '%' . $search . '%';
        $params[':search2']  = '%' . $search . '%';
        $params[':search3']  = '%' . $search . '%';
    }

    $whereSQL = !empty($where) ? 'WHERE ' . implode(' AND ', $where) : '';

    // ── Count ──────────────────────────────────────────────────────────────────
    $cnt = $db->prepare("SELECT COUNT(*) FROM temporary_stay_requests tsr $whereSQL");
    $cnt->execute($params);
    $totalRecords = (int)$cnt->fetchColumn();
    $totalPages   = (int)ceil($totalRecords / $perPage);

    // ── Main query ─────────────────────────────────────────────────────────────
    $stmt = $db->prepare("
        SELECT
            tsr.id,
            tsr.request_id,
            tsr.full_name,
            tsr.email,
            tsr.phone,
            tsr.gender,
            tsr.institution_purpose,
            tsr.doc_type,
            tsr.doc_number,
            tsr.hostel_name,
            tsr.room_type,
            tsr.room_no,
            tsr.from_date,
            tsr.to_date,
            tsr.duration_type,
            tsr.duration_value,
            DATEDIFF(tsr.to_date, CURDATE())  AS days_remaining,
            DATEDIFF(tsr.to_date, tsr.from_date) AS total_stay_days,
            tsr.amount,
            tsr.annual_fee,
            tsr.status,
            tsr.payment_status,
            tsr.payment_txn_id,
            tsr.warden_name,
            tsr.hold_expires_at,
            tsr.hold_status,
            tsr.admin_notes,
            tsr.created_at,
            tsr.updated_at
        FROM temporary_stay_requests tsr
        $whereSQL
        ORDER BY 
            CASE tsr.status
                WHEN 'allocated' THEN 1
                WHEN 'approved'  THEN 2
                WHEN 'pending'   THEN 3
                WHEN 'timed_out' THEN 4
                WHEN 'rejected'  THEN 5
                ELSE 6
            END ASC,
            tsr.to_date ASC
        LIMIT :limit OFFSET :offset
    ");
    foreach ($params as $k => $v) $stmt->bindValue($k, $v);
    $stmt->bindValue(':limit',  $perPage, PDO::PARAM_INT);
    $stmt->bindValue(':offset', $offset,  PDO::PARAM_INT);
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // ── Overall stats (no filter applied — full picture) ───────────────────────
    $overallStats = $db->query("
        SELECT
            COUNT(*) AS total_ever,
            SUM(CASE WHEN status='allocated' AND payment_status='paid' AND to_date >= CURDATE() THEN 1 ELSE 0 END) AS currently_staying,
            SUM(CASE WHEN status='allocated' AND payment_status='paid' AND to_date < CURDATE() THEN 1 ELSE 0 END)  AS completed,
            SUM(CASE WHEN status='approved'  AND payment_status='unpaid' THEN 1 ELSE 0 END)                        AS awaiting_payment,
            SUM(CASE WHEN status='pending'   THEN 1 ELSE 0 END)                                                    AS pending_approval,
            SUM(CASE WHEN status='timed_out' THEN 1 ELSE 0 END)                                                    AS timed_out,
            SUM(CASE WHEN status='rejected'  THEN 1 ELSE 0 END)                                                    AS rejected,
            SUM(CASE WHEN payment_status='paid' THEN amount ELSE 0 END)                                             AS total_revenue
        FROM temporary_stay_requests
    ")->fetch(PDO::FETCH_ASSOC);

    // ── Format rows ────────────────────────────────────────────────────────────
    $formatted = array_map(fn($r) => [
        'id'                 => (int)$r['id'],
        'request_id'         => $r['request_id'],
        'full_name'          => $r['full_name'],
        'email'              => $r['email'],
        'phone'              => $r['phone'],
        'gender'             => $r['gender'],
        'purpose'            => $r['institution_purpose'],
        'doc_type'           => $r['doc_type'],
        'doc_number'         => $r['doc_number'],
        'hostel_name'        => $r['hostel_name'],
        'room_type'          => $r['room_type'],
        'room_no'            => $r['room_no'],
        'from_date'          => $r['from_date'],
        'to_date'            => $r['to_date'],
        'duration_type'      => $r['duration_type'],
        'duration_value'     => (int)$r['duration_value'],
        'total_stay_days'    => (int)$r['total_stay_days'],
        'days_remaining'     => max(0, (int)$r['days_remaining']),
        'amount'             => (float)$r['amount'],
        'annual_fee'         => (float)$r['annual_fee'],
        'status'             => $r['status'],
        'payment_status'     => $r['payment_status'],
        'payment_txn_id'     => $r['payment_txn_id'] ?? '',
        'warden_name'        => $r['warden_name'] ?? '',
        'hold_expires_at'    => $r['hold_expires_at'] ?? '',
        'hold_status'        => $r['hold_status'] ?? '',
        'admin_notes'        => $r['admin_notes'] ?? '',
        'created_at'         => $r['created_at'],
        'updated_at'         => $r['updated_at'],
    ], $rows);

    echo json_encode([
        'success'        => true,
        'generated_at'   => date('Y-m-d H:i:s'),
        'filters_applied'=> compact('filter', 'hostel', 'gender', 'warden', 'from', 'to', 'search'),
        'overall_stats'  => [
            'total_requests'    => (int)$overallStats['total_ever'],
            'currently_staying' => (int)$overallStats['currently_staying'],
            'completed'         => (int)$overallStats['completed'],
            'awaiting_payment'  => (int)$overallStats['awaiting_payment'],
            'pending_approval'  => (int)$overallStats['pending_approval'],
            'timed_out'         => (int)$overallStats['timed_out'],
            'rejected'          => (int)$overallStats['rejected'],
            'total_revenue'     => (float)$overallStats['total_revenue'],
        ],
        'students'       => $formatted,
        'pagination'     => [
            'page'          => $page,
            'per_page'      => $perPage,
            'total_records' => $totalRecords,
            'total_pages'   => $totalPages,
        ],
    ], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => $e->getMessage()]);
}
