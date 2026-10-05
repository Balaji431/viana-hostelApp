<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json; charset=UTF-8");

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/api_config.php';
require_once __DIR__ . '/../utils/vstudy_sync_helper.php';
require_once __DIR__ . '/../utils/auth_helper.php';

$authUser = requireAuth(['admin', 'super_admin', 'warden', 'maintenance', 'it']);

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true) ?: array_merge($_GET, $_POST);

    $staff_username = !empty($authUser['username']) ? $authUser['username'] : trim($input['staff_username'] ?? '');
    $role = !empty($authUser['role']) ? strtolower(trim($authUser['role'])) : strtolower(trim($input['role'] ?? ''));
    $from_date = trim($input['from_date'] ?? '');
    $to_date = trim($input['to_date'] ?? '');
    $month = trim($input['month'] ?? date('Y-m'));
    $hostel = trim($input['hostel'] ?? 'All');
    $floor = trim($input['floor'] ?? 'All');

    // Pagination: default 100 per page, up to 1000
    $page = isset($input['page']) ? max(1, (int)$input['page']) : 1;
    $limit = isset($input['limit']) ? min(1000, max(1, (int)$input['limit'])) : 100;

    // If dates are not provided, default to current month
    if (empty($from_date) || empty($to_date)) {
        if (!empty($month) && preg_match('/^\d{4}-\d{2}$/', $month)) {
            $from_date = $month . '-01';
            $to_date = date('Y-m-t', strtotime($from_date));
        } else {
            $from_date = date('Y-m-01');
            $to_date = date('Y-m-t');
        }
    }

    // 1. Determine staff room allocation scope
    $is_restricted_staff = false;
    $assigned_pairs = [];

    if (!empty($staff_username) && !in_array($role, ['admin', 'superadmin', 'super_admin'])) {
        $mapStmt = $db->prepare("
            SELECT DISTINCT rgd.hostel_name, rgd.group_name, ms.floor_name as mapped_floor
            FROM rooms_groups_details rgd
            JOIN mapping_staff ms ON (TRIM(ms.username) = ? OR TRIM(ms.staff_bio_id) = ?)
            WHERE (
                LOWER(TRIM(ms.hostel_name)) = LOWER(TRIM(rgd.hostel_name))
                OR LOWER(TRIM(rgd.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(ms.hostel_name)), '%')
                OR LOWER(TRIM(ms.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(rgd.hostel_name)), '%')
            )
            AND (
                LOWER(TRIM(ms.floor_name)) = 'all'
                OR ms.floor_name IS NULL
                OR ms.floor_name = ''
                OR LOWER(TRIM(ms.floor_name)) = LOWER(TRIM(rgd.group_name))
                OR LOWER(TRIM(rgd.group_name)) LIKE CONCAT('%', LOWER(TRIM(ms.floor_name)), '%')
                OR LOWER(TRIM(ms.floor_name)) LIKE CONCAT('%', LOWER(TRIM(rgd.group_name)), '%')
            )
            AND rgd.hostel_name IS NOT NULL AND rgd.hostel_name != ''
            AND rgd.group_name IS NOT NULL AND rgd.group_name != ''
        ");
        $mapStmt->execute([$staff_username, $staff_username]);
        $pairs = $mapStmt->fetchAll(PDO::FETCH_ASSOC);

        if (!empty($pairs)) {
            $is_restricted_staff = true;
            $assigned_pairs = $pairs;
        }
    }

    // 2. Build WHERE clause matching allocated rooms
    $where = ["rgd.hostel_name IS NOT NULL AND rgd.hostel_name != ''"];
    $params = [];

    if (!empty($hostel) && strtolower($hostel) !== 'all') {
        $where[] = "rgd.hostel_name = ?";
        $params[] = $hostel;

        if (!empty($floor) && strtolower($floor) !== 'all') {
            $where[] = "(rgd.group_name = ? OR LOWER(rgd.group_name) LIKE ? OR LOWER(?) LIKE CONCAT('%', LOWER(rgd.group_name), '%'))";
            $params[] = $floor;
            $params[] = '%' . strtolower($floor) . '%';
            $params[] = $floor;
        }
    } elseif ($is_restricted_staff && !empty($assigned_pairs)) {
        if (!empty($floor) && strtolower($floor) !== 'all') {
            $where[] = "(rgd.group_name = ? OR LOWER(rgd.group_name) LIKE ? OR LOWER(?) LIKE CONCAT('%', LOWER(rgd.group_name), '%'))";
            $params[] = $floor;
            $params[] = '%' . strtolower($floor) . '%';
            $params[] = $floor;
        } else {
            $pairClauses = [];
            foreach ($assigned_pairs as $p) {
                $pairClauses[] = "(rgd.hostel_name = ? AND rgd.group_name = ?)";
                $params[] = $p['hostel_name'];
                $params[] = $p['group_name'];
            }
            if (!empty($pairClauses)) {
                $where[] = "(" . implode(" OR ", $pairClauses) . ")";
            }
        }
    }

    $whereSQL = implode(" AND ", $where);
    $dateFilter = "WHERE DATE(created_at) >= " . $db->quote($from_date) . " AND DATE(created_at) <= " . $db->quote($to_date);

    // 3. Query all rooms and their verified readings in the specified range
    $sql = "
        SELECT 
            rgd.hostel_name,
            rgd.group_name as floor_name,
            rgd.room_number,
            emr.id as reading_id,
            emr.meter_no,
            emr.units_consumed,
            emr.created_at as verified_at,
            emr.recorded_by,
            emr.inspector_name,
            CASE WHEN emr.id IS NOT NULL THEN 1 ELSE 0 END as is_verified
        FROM (
            SELECT MIN(s_no) as s_no, hostel_name, group_name, room_number
            FROM rooms_groups_details
            WHERE hostel_name IS NOT NULL AND hostel_name != ''
            GROUP BY hostel_name, group_name, room_number
        ) rgd
        LEFT JOIN (
            SELECT r1.room_no, r1.hostel_name, r1.id, r1.meter_no,
                   r1.units_consumed, r1.created_at, r1.recorded_by, r1.inspector_name
            FROM eb_meter_readings r1
            INNER JOIN (
                SELECT room_no, hostel_name, MAX(id) as max_id
                FROM eb_meter_readings
                $dateFilter
                GROUP BY room_no, hostel_name
            ) r2 ON r1.id = r2.max_id
        ) emr ON (emr.room_no = rgd.room_number)
        WHERE $whereSQL
        ORDER BY rgd.hostel_name ASC, rgd.room_number ASC
    ";

    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $rooms = $stmt->fetchAll(PDO::FETCH_ASSOC);

    if (empty($rooms)) {
        echo json_encode([
            "status" => "error",
            "message" => "No allocated rooms found for this user in the selected period"
        ]);
        exit();
    }

    $totalRooms = count($rooms);
    $unverifiedRooms = [];
    $allVerifiedReadings = [];

    foreach ($rooms as $r) {
        if (empty($r['is_verified']) || empty($r['reading_id'])) {
            $unverifiedRooms[] = $r['room_number'];
        } else {
            $allVerifiedReadings[] = [
                'roomNumber'    => $r['room_number'],
                'hostelName'    => $r['hostel_name'],
                'floorName'     => $r['floor_name'],
                'meterNo'       => !empty($r['meter_no']) ? $r['meter_no'] : 'MTR-' . $r['room_number'],
                'unitsConsumed' => (float)($r['units_consumed'] ?? 0),
                'readingDate'   => $r['verified_at'],
                'recordedBy'    => !empty($r['recorded_by']) ? $r['recorded_by'] : $staff_username,
                'inspectorName' => !empty($r['inspector_name']) ? $r['inspector_name'] : 'Maintenance Staff'
            ];
        }
    }

    // 4. Strict check: ALL allocated rooms must be verified before export is permitted!
    if (!empty($unverifiedRooms)) {
        $unverifiedCount = count($unverifiedRooms);
        echo json_encode([
            "status" => "error",
            "message" => "Cannot export: $unverifiedCount rooms are still pending meter verification. All allocated rooms must be verified before exporting to vStudy.",
            "unverified_count" => $unverifiedCount,
            "total_rooms" => $totalRooms,
            "sample_unverified" => array_slice($unverifiedRooms, 0, 5)
        ]);
        exit();
    }

    // 5. Pagination Calculation
    $totalVerifiedCount = count($allVerifiedReadings);
    $totalPages = max(1, (int)ceil($totalVerifiedCount / $limit));
    $offset = ($page - 1) * $limit;
    $pagedReadings = array_slice($allVerifiedReadings, $offset, $limit);

    // 6. Construct VStudy Payload
    $externalEventId = generateUuidV4();
    $vstudyUrl = defined('VSTUDY_EB_SYNC_API_URL') ? VSTUDY_EB_SYNC_API_URL : 'https://vstudy.saveetha.com/api/hostel-applications/external/eb-meter-readings';
    $clientId = defined('VSTUDY_CLIENT_ID') ? VSTUDY_CLIENT_ID : '';
    $clientSecret = defined('VSTUDY_CLIENT_SECRET') ? VSTUDY_CLIENT_SECRET : '';

    $payload = [
        'externalEventId' => $externalEventId,
        'eventType'       => 'electricity.meter_readings_export',
        'month'           => $month,
        'fromDate'        => $from_date,
        'toDate'          => $to_date,
        'staffUsername'   => $staff_username,
        'exportedAt'      => date('c'),
        'totalRooms'      => $totalVerifiedCount,
        'readings'        => $pagedReadings,
        'pagination'      => [
            'page'        => $page,
            'limit'       => $limit,
            'total'       => $totalVerifiedCount,
            'total_pages' => $totalPages
        ]
    ];

    $jsonPayload = json_encode($payload);
    $httpCode = 0;
    $vstudyResponse = null;
    $isSynced = false;

    // Send to vStudy external API
    if (!empty($clientId) && !empty($clientSecret)) {
        $ch = curl_init($vstudyUrl);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $jsonPayload);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'x-client-id: ' . $clientId,
            'x-client-secret: ' . $clientSecret
        ]);
        curl_setopt($ch, CURLOPT_TIMEOUT, 15);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        $res = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        $vstudyResponse = json_decode($res, true) ?: $res;
        $isSynced = ($httpCode === 200 || $httpCode === 201);
    }

    // 7. Log outbound sync to vstay_webhook_events table
    try {
        ensureVstayWebhookEventsTable($db);
        $stmtIns = $db->prepare("
            INSERT INTO vstay_webhook_events (
                event_id, event_type, entity_type, entity_id,
                roll_number, room_number, hostel_name, direction, status,
                occurred_at, payload, response
            ) VALUES (
                ?, 'electricity.meter_readings_export', 'HOSTEL_EB_READINGS', ?,
                ?, 'ALL_ROOMS', ?, 'OUTBOUND', ?,
                NOW(), ?, ?
            )
        ");
        $stmtIns->execute([
            $externalEventId,
            $month,
            $staff_username,
            $hostel !== 'All' ? $hostel : 'All Hostels',
            $isSynced ? 'PROCESSED' : 'SENT',
            $jsonPayload,
            json_encode(['http_code' => $httpCode, 'vstudy_response' => $vstudyResponse])
        ]);
    } catch (Exception $logErr) {
        error_log("Failed to log EB export to vstay_webhook_events: " . $logErr->getMessage());
    }

    // Return the JSON format requested by the user
    echo json_encode(array_merge([
        "status"          => "success",
        "message"         => "Successfully exported $totalVerifiedCount room meter readings to vStudy!",
    ], $payload, [
        "vstudy_http_code"=> $httpCode,
        "vstudy_response" => $vstudyResponse
    ]));

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "status" => "error",
        "message" => "Export failed: " . $e->getMessage()
    ]);
}
