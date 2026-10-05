<?php
/**
 * get_room_changes.php
 * ─────────────────────────────────────────────────────────────────────────────
 * API: Finalized Hostel Room Change Records
 *
 * Exclusively returns students whose room change is FULLY COMPLETED / APPROVED & PAID:
 *  1. Upgraded with fee: Student has paid the upgrade fee (status = completed, payment_status = paid).
 *  2. Same room type / no fee: Approved by warden directly (status = approved, payment_status = paid).
 *
 * Pending requests, unpaid requests awaiting 3-day payment, and rejected requests
 * are strictly EXCLUDED from this API.
 *
 * Headers required:
 *   x-client-id: client_51e2de18e4a27a525e2fd17a
 *   x-client-secret: <VSTUDY_CLIENT_SECRET>
 *
 * GET Parameters (all optional):
 *   ?from=YYYY-MM-DD        Filter from date         (default: all)
 *   ?to=YYYY-MM-DD          Filter to date           (default: all)
 *   ?reg_no=1501260065      Filter by student reg no
 *   ?page=1                 Pagination page          (default: 1)
 *   ?per_page=10            Records per page         (default: 10, max: 100)
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
    // ── Maintenance: Auto-expire any unpaid requests after 3 days ──────────────
    $db->exec("
        UPDATE room_change_requests 
        SET status = 'cancelled', payment_status = 'unpaid', remarks = 'Auto-cancelled after 3 days due to non-payment' 
        WHERE (LOWER(status) = 'approved' OR LOWER(status) = 'pre_approved') 
          AND payment_status = 'unpaid' 
          AND (
              (reserved_until IS NOT NULL AND reserved_until < NOW())
              OR updated_at < DATE_SUB(NOW(), INTERVAL 3 DAY)
          )
    ");

    // ── Parameters ─────────────────────────────────────────────────────────────
    $from          = trim($_GET['from']           ?? '');
    $to            = trim($_GET['to']             ?? '');
    $regNo         = trim($_GET['reg_no']         ?? '');
    $page          = max(1, (int)($_GET['page'] ?? 1));
    $perPage       = max(1, min(100, (int)($_GET['per_page'] ?? 10)));
    $offset        = ($page - 1) * $perPage;

    // ── WHERE builder (STRICT: ONLY COMPLETED & APPROVED+PAID ROOM CHANGES) ─────
    $where  = [
        "rcr.payment_status = 'paid'",
        "LOWER(rcr.status) IN ('approved', 'completed')"
    ];
    $params = [];

    if (!empty($from) && !empty($to)) {
        if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $from) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $to)) {
            $where[] = "DATE(rcr.updated_at) BETWEEN :from AND :to";
            $params[':from'] = $from;
            $params[':to']   = $to;
        }
    } elseif (!empty($from) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $from)) {
        $where[] = "DATE(rcr.updated_at) >= :from";
        $params[':from'] = $from;
    } elseif (!empty($to) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $to)) {
        $where[] = "DATE(rcr.updated_at) <= :to";
        $params[':to'] = $to;
    }

    if (!empty($regNo)) {
        $where[]            = "rcr.student_reg_no = :reg_no";
        $params[':reg_no']  = $regNo;
    }

    $whereSQL = 'WHERE ' . implode(' AND ', $where);

    // ── Count ──────────────────────────────────────────────────────────────────
    $cnt = $db->prepare("SELECT COUNT(*) FROM room_change_requests rcr $whereSQL");
    $cnt->execute($params);
    $totalRecords = (int)$cnt->fetchColumn();
    $totalPages   = (int)ceil($totalRecords / $perPage);

    // ── Main query ─────────────────────────────────────────────────────────────
    $stmt = $db->prepare("
        SELECT
            rcr.id,
            rcr.request_id,
            rcr.student_id,
            rcr.student_name,
            rcr.student_reg_no,
            rcr.current_room,
            rcr.requested_room,
            rcr.requested_room_type,
            rcr.reason,
            rcr.status,
            rcr.payment_status,
            rcr.amount_to_pay,
            rcr.processed_by,
            rcr.processed_by_name,
            rcr.remarks,
            rcr.created_at,
            rcr.updated_at,
            u.email,
            u.Gender            AS gender,
            u.Institution       AS institution,
            u.Campus            AS campus,
            COALESCE(pr.hostel_name, u.HostelName) AS hostel,
            COALESCE(pr.personal_phone, u.phone_number) AS phone,
            COALESCE(pr.room_allocation, u.RoomId)      AS active_allocated_room
        FROM room_change_requests rcr
        LEFT JOIN users u 
            ON (u.username COLLATE utf8mb4_general_ci = rcr.student_reg_no COLLATE utf8mb4_general_ci OR u.id = rcr.student_id)
        LEFT JOIN profile pr 
            ON (pr.reg_no COLLATE utf8mb4_general_ci = rcr.student_reg_no COLLATE utf8mb4_general_ci OR pr.user_id = u.id)
        $whereSQL
        ORDER BY rcr.updated_at DESC, rcr.id DESC
        LIMIT :limit OFFSET :offset
    ");

    foreach ($params as $k => $v) {
        $stmt->bindValue($k, $v);
    }
    $stmt->bindValue(':limit',  $perPage, PDO::PARAM_INT);
    $stmt->bindValue(':offset', $offset,  PDO::PARAM_INT);
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // ── Summary stats ──────────────────────────────────────────────────────────
    $sStmt = $db->prepare("
        SELECT
            COUNT(*)                                                               AS total_completed,
            SUM(CASE WHEN COALESCE(rcr.amount_to_pay, 0) > 0 THEN 1 ELSE 0 END)   AS paid_upgrade_count,
            SUM(CASE WHEN COALESCE(rcr.amount_to_pay, 0) = 0 THEN 1 ELSE 0 END)   AS zero_fee_approved_count,
            SUM(COALESCE(rcr.amount_to_pay, 0))                                    AS total_collected
        FROM room_change_requests rcr
        $whereSQL
    ");
    $sStmt->execute($params);
    $stats = $sStmt->fetch(PDO::FETCH_ASSOC);

    // ── Format response ────────────────────────────────────────────────────────
    $formatted = array_map(function($r) {
        $amount = $r['amount_to_pay'] !== null ? (float)$r['amount_to_pay'] : 0.00;

        return [
            'id'                     => (int)$r['id'],
            'request_id'             => $r['request_id'],
            'student_id'             => (int)$r['student_id'],
            'student_name'           => $r['student_name'],
            'reg_no'                 => $r['student_reg_no'],
            'email'                  => $r['email'] ?? '',
            'phone'                  => $r['phone'] ?? '',
            'gender'                 => $r['gender'] ?? '',
            'institution'            => $r['institution'] ?? '',
            'campus'                 => $r['campus'] ?? '',
            'hostel'                 => $r['hostel'] ?? '',
            'previous_room'          => $r['current_room'],
            'new_allocated_room'     => $r['requested_room'],
            'new_room_type'          => $r['requested_room_type'],
            'home_screen_active_room'=> $r['active_allocated_room'] ?? $r['requested_room'],
            'reason'                 => $r['reason'],
            'status'                 => $r['status'],
            'payment_status'         => $r['payment_status'],
            'amount_paid'            => $amount,
            'processed_by'           => $r['processed_by'] ? (int)$r['processed_by'] : null,
            'processed_by_name'      => $r['processed_by_name'] ?? '',
            'remarks'                => $r['remarks'] ?? '',
            'requested_at'           => $r['created_at'],
            'completed_at'           => $r['updated_at'],
        ];
    }, $rows);

    echo json_encode([
        'success'      => true,
        'generated_at' => date('Y-m-d H:i:s'),
        'filters'      => [
            'from'  => $from,
            'to'    => $to,
            'regNo' => $regNo,
        ],
        'summary'      => [
            'total_completed_room_changes' => (int)($stats['total_completed'] ?? 0),
            'paid_upgrades'                => (int)($stats['paid_upgrade_count'] ?? 0),
            'zero_fee_approvals'           => (int)($stats['zero_fee_approved_count'] ?? 0),
            'total_fee_collected'          => (float)($stats['total_collected'] ?? 0),
        ],
        'completed_room_changes' => $formatted,
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
