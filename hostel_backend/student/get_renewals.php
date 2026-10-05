<?php
/**
 * get_renewals.php
 * ─────────────────────────────────────────────────────────────────────────────
 * API: Hostel Renewal Records
 *
 * Every time a student pays via the "Renew Stay" wallet button,
 * renew_hostel_wallet.php auto-inserts a record into renewal_requests (status=approved).
 * This API reads from that same table — so ALL future renewals appear here instantly.
 *
 * GET Parameters (all optional):
 *   ?from=YYYY-MM-DD        Filter from date         (default: 30 days ago)
 *   ?to=YYYY-MM-DD          Filter to date           (default: today)
 *   ?status=approved        approved / pending / rejected / all (default: all)
 *   ?reg_no=112501004       Filter by student reg no
 *   ?page=1                 Pagination page          (default: 1)
 *   ?per_page=50            Records per page         (default: 50, max: 200)
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
    $from    = trim($_GET['from']     ?? '');
    $to      = trim($_GET['to']       ?? '');
    $status  = trim($_GET['status']   ?? 'all');
    $regNo   = trim($_GET['reg_no']   ?? '');
    $page    = max(1, (int)($_GET['page'] ?? 1));

    // Dynamic limit: if 'limit' (or 'per_page') is passed (e.g. ?limit=300), use it.
    // If omitted, default to 10 records per page.
    if (isset($_GET['limit']) && is_numeric($_GET['limit'])) {
        $perPage = max(1, (int)$_GET['limit']);
    } elseif (isset($_GET['per_page']) && is_numeric($_GET['per_page'])) {
        $perPage = max(1, (int)$_GET['per_page']);
    } else {
        $perPage = 10;
    }

    $offset  = ($page - 1) * $perPage;

    // ── WHERE builder ──────────────────────────────────────────────────────────
    $where  = [];
    $params = [];

    if (!empty($from) && !empty($to)) {
        if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $from) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $to)) {
            $where[] = "DATE(rr.requested_at) BETWEEN :from AND :to";
            $params[':from'] = $from;
            $params[':to']   = $to;
        }
    } elseif (!empty($from) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $from)) {
        $where[] = "DATE(rr.requested_at) >= :from";
        $params[':from'] = $from;
    } elseif (!empty($to) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $to)) {
        $where[] = "DATE(rr.requested_at) <= :to";
        $params[':to'] = $to;
    }

    if ($status !== 'all' && in_array($status, ['approved','pending','rejected'])) {
        $where[]           = "rr.status = :status";
        $params[':status'] = $status;
    }
    if (!empty($regNo)) {
        $where[]            = "rr.student_reg_no = :reg_no";
        $params[':reg_no']  = $regNo;
    }

    $whereSQL = !empty($where) ? ('WHERE ' . implode(' AND ', $where)) : '';

    // ── Count ──────────────────────────────────────────────────────────────────
    $cnt = $db->prepare("SELECT COUNT(*) FROM renewal_requests rr $whereSQL");
    $cnt->execute($params);
    $totalRecords = (int)$cnt->fetchColumn();
    $totalPages   = (int)ceil($totalRecords / $perPage);

    // ── Main query ─────────────────────────────────────────────────────────────
    $stmt = $db->prepare("
        SELECT
            rr.id,
            rr.student_id,
            rr.student_name,
            rr.student_reg_no,
            rr.room_number,
            rr.reason,
            rr.status,
            rr.requested_at,
            rr.processed_by_name,
            rr.processed_at,
            rr.remarks,
            p.amount        AS renewal_amount,
            p.payment_id    AS payment_ref,
            p.payment_type,
            p.paid_at,
            pr.hostel_name,
            pr.valid_from,
            pr.valid_to,
            pr.renewal_date,
            pr.remaining_days,
            pr.personal_phone AS phone,
            u.email,
            u.Gender         AS gender,
            u.Institution,
            u.Campus,
            u.HostelName     AS hostel
        FROM renewal_requests rr
        LEFT JOIN payment p
            ON p.registerNumber COLLATE utf8mb4_general_ci = rr.student_reg_no COLLATE utf8mb4_general_ci
            AND p.payment_type LIKE '%Renewal%'
            AND ABS(TIMESTAMPDIFF(MINUTE, p.paid_at, rr.requested_at)) < 5
        LEFT JOIN profile pr ON pr.reg_no COLLATE utf8mb4_general_ci = rr.student_reg_no COLLATE utf8mb4_general_ci
        LEFT JOIN users u    ON u.username COLLATE utf8mb4_general_ci = rr.student_reg_no COLLATE utf8mb4_general_ci
        $whereSQL
        ORDER BY rr.id DESC
        LIMIT :limit OFFSET :offset
    ");
    foreach ($params as $k => $v) $stmt->bindValue($k, $v);
    $stmt->bindValue(':limit',  $perPage, PDO::PARAM_INT);
    $stmt->bindValue(':offset', $offset,  PDO::PARAM_INT);
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // ── Summary stats ──────────────────────────────────────────────────────────
    $sStmt = $db->prepare("
        SELECT
            COUNT(*)                                                   AS total,
            SUM(CASE WHEN rr.status='approved' THEN 1 ELSE 0 END)     AS approved,
            SUM(CASE WHEN rr.status='pending'  THEN 1 ELSE 0 END)     AS pending,
            SUM(CASE WHEN rr.status='rejected' THEN 1 ELSE 0 END)     AS rejected,
            SUM(COALESCE(p.amount, 0))                                 AS total_collected
        FROM renewal_requests rr
        LEFT JOIN payment p
            ON p.registerNumber COLLATE utf8mb4_general_ci = rr.student_reg_no COLLATE utf8mb4_general_ci
            AND p.payment_type LIKE '%Renewal%'
            AND ABS(TIMESTAMPDIFF(MINUTE, p.paid_at, rr.requested_at)) < 5
        $whereSQL
    ");
    $sStmt->execute($params);
    $stats = $sStmt->fetch(PDO::FETCH_ASSOC);

    // ── Format ────────────────────────────────────────────────────────────────
    $formatted = array_map(function($r) {
        $amount = $r['renewal_amount'] !== null ? (float)$r['renewal_amount'] : null;
        $ref = $r['payment_ref'] ?? '';
        $remarks = $r['remarks'] ?? '';

        // Fallback: extract amount from remarks if payment table didn't supply it
        if ($amount === null && !empty($remarks)) {
            if (preg_match('/Paid [^\d]*([\d,]+(\.\d+)?)/i', $remarks, $m)) {
                $amount = (float)str_replace(',', '', $m[1]);
            }
        }

        // Fallback: extract ref ID from remarks
        if (empty($ref) && !empty($remarks)) {
            if (preg_match('/Ref:\s*([A-Za-z0-9_\-]+)/i', $remarks, $m)) {
                $ref = $m[1];
            }
        }

        return [
            'id'               => (int)$r['id'],
            'student_id'       => (int)$r['student_id'],
            'student_name'     => $r['student_name'],
            'reg_no'           => $r['student_reg_no'],
            'email'            => $r['email'] ?? '',
            'phone'            => $r['phone'] ?? '',
            'gender'           => $r['gender'] ?? '',
            'institution'      => $r['Institution'] ?? '',
            'campus'           => $r['Campus'] ?? '',
            'hostel'           => $r['hostel'] ?? $r['hostel_name'] ?? '',
            'room_number'      => $r['room_number'],
            'reason'           => $r['reason'],
            'status'           => $r['status'],
            'renewal_amount'   => $amount,
            'payment_ref'      => $ref,
            'payment_type'     => $r['payment_type'] ?? 'Hostel Renewal',
            'valid_from'       => $r['valid_from'] ?? '',
            'valid_to'         => $r['valid_to'] ?? '',
            'renewal_date'     => $r['renewal_date'] ?? '',
            'days_remaining'   => (int)($r['remaining_days'] ?? 0),
            'requested_at'     => $r['requested_at'],
            'paid_at'          => $r['paid_at'] ?? '',
            'processed_by'     => $r['processed_by_name'] ?? 'System',
            'remarks'          => $remarks,
        ];
    }, $rows);

    echo json_encode([
        'success'      => true,
        'generated_at' => date('Y-m-d H:i:s'),
        'filters'      => compact('from', 'to', 'status', 'regNo'),
        'summary'      => [
            'total_renewals'    => (int)$stats['total'],
            'approved'          => (int)$stats['approved'],
            'pending'           => (int)$stats['pending'],
            'rejected'          => (int)$stats['rejected'],
            'total_collected'   => (float)($stats['total_collected'] ?? 0),
        ],
        'renewals'     => $formatted,
        'pagination'   => [
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
