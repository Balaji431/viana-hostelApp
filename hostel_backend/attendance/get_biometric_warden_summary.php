<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/auth_helper.php';

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $date = isset($_GET['date']) ? trim($_GET['date']) : date('Y-m-d');
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
        $date = date('Y-m-d');
    }

    $warden_username = isset($_GET['warden_username']) ? trim($_GET['warden_username']) : '';

    if (empty($warden_username)) {
        $auth_header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
        if (empty($auth_header) && function_exists('apache_request_headers')) {
            $headers = apache_request_headers();
            $auth_header = $headers['Authorization'] ?? $headers['authorization'] ?? '';
        }
        if (preg_match('/Bearer\s+(.*)$/i', $auth_header, $matches)) {
            $payload = validateJWT($matches[1]);
            if ($payload) $warden_username = $payload['username'] ?? '';
        }
    }

    // 1. Resolve Warden Role and Identity
    $is_admin = false;
    $w_name = $warden_username;
    $w_bio = $warden_username;

    if (!empty($warden_username)) {
        $w_stmt = $db->prepare("
            SELECT id, username, full_name, role
            FROM users
            WHERE LOWER(TRIM(username)) = LOWER(TRIM(:w))
               OR LOWER(TRIM(full_name)) = LOWER(TRIM(:w))
            LIMIT 1
        ");
        $w_stmt->execute([':w' => $warden_username]);
        $w_user = $w_stmt->fetch(PDO::FETCH_ASSOC);

        if ($w_user) {
            $w_name = $w_user['full_name'];
            $w_bio = $w_user['username'];
            if (in_array(strtolower($w_user['role']), ['admin', 'superadmin', 'super_admin'])) {
                $is_admin = true;
            }
        }
        if (strtolower($warden_username) === 'admin') {
            $is_admin = true;
        }
    } else {
        $is_admin = true; // Default fallback to all if not restricted
    }

    // 2. Fetch Warden Assigned Students
    $students = [];

    if ($is_admin) {
        $stmt = $db->prepare("
            SELECT DISTINCT
                p.id as profile_id,
                p.full_name,
                p.reg_no as register_number,
                COALESCE(NULLIF(p.room_allocation, ''), u.RoomId, rgd.room_number) as room_no,
                COALESCE(NULLIF(rgd.hostel_name, ''), p.hostel_name, u.HostelName, 'Hostel') as hostel_name,
                COALESCE(NULLIF(rgd.group_name, ''), 'Default Floor') as floor_name,
                u.id as user_id,
                u.phone_number,
                COALESCE(u.ParentContact, '') as parent_phone
            FROM profile p
            LEFT JOIN users u ON (p.reg_no = u.username)
            LEFT JOIN rooms_groups_details rgd ON (
                p.room_allocation = rgd.room_number 
                OR u.RoomId = rgd.room_number
                OR REPLACE(REPLACE(TRIM(rgd.room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(COALESCE(NULLIF(p.room_allocation,''), u.RoomId)), ' ', ''), '-', '')
            )
            WHERE (p.room_allocation IS NOT NULL AND p.room_allocation != '')
               OR (u.RoomId IS NOT NULL AND u.RoomId != '')
            ORDER BY p.full_name ASC
        ");
        $stmt->execute();
        $students = $stmt->fetchAll(PDO::FETCH_ASSOC);
    } else {
        // Fetch mapped rooms for this warden
        $myRoomsStmt = $db->prepare("
            SELECT DISTINCT rgd.room_number, rgd.group_name as floor_name, rgd.hostel_name
            FROM rooms_groups_details rgd
            LEFT JOIN mapping_staff ms ON (
                (LOWER(ms.username) = LOWER(:w_bio) OR LOWER(ms.staff_bio_id) = LOWER(:w_bio) OR LOWER(ms.name) = LOWER(:w_name))
                AND (
                    LOWER(ms.hostel_name) = 'all'
                    OR LOWER(rgd.hostel_name) LIKE CONCAT('%', LOWER(ms.hostel_name), '%')
                    OR LOWER(ms.hostel_name) LIKE CONCAT('%', LOWER(rgd.hostel_name), '%')
                )
                AND (
                    LOWER(ms.floor_name) = 'all'
                    OR (
                        rgd.group_name IS NOT NULL AND rgd.group_name != ''
                        AND (
                            LOWER(rgd.group_name) LIKE CONCAT('%', LOWER(ms.floor_name), '%')
                            OR LOWER(ms.floor_name) LIKE CONCAT('%', LOWER(rgd.group_name), '%')
                        )
                    )
                )
            )
            WHERE (
                (LOWER(rgd.warden_name) = LOWER(:w_name) OR LOWER(rgd.warden_bio_id) = LOWER(:w_bio) OR LOWER(rgd.warden_user_id) = LOWER(:w_bio))
                OR ms.id IS NOT NULL
            )
            AND rgd.room_number IS NOT NULL AND rgd.room_number != ''
            ORDER BY rgd.room_number ASC
        ");
        $myRoomsStmt->execute([':w_bio' => $w_bio, ':w_name' => $w_name]);
        $my_rooms = $myRoomsStmt->fetchAll(PDO::FETCH_ASSOC);

        $room_numbers = [];
        foreach ($my_rooms as $r) {
            $room_numbers[] = $r['room_number'];
        }

        if (!empty($room_numbers)) {
            $in_clause = implode(',', array_fill(0, count($room_numbers), '?'));
            $sql = "
                SELECT DISTINCT
                    p.id as profile_id,
                    p.full_name,
                    p.reg_no as register_number,
                    COALESCE(NULLIF(p.room_allocation, ''), u.RoomId, rgd.room_number) as room_no,
                    COALESCE(NULLIF(rgd.hostel_name, ''), p.hostel_name, u.HostelName, 'Hostel') as hostel_name,
                    COALESCE(NULLIF(rgd.group_name, ''), 'Default Floor') as floor_name,
                    u.id as user_id,
                    u.phone_number,
                    COALESCE(u.ParentContact, '') as parent_phone
                FROM profile p
                LEFT JOIN users u ON (p.reg_no = u.username)
                LEFT JOIN rooms_groups_details rgd ON (
                    p.room_allocation = rgd.room_number 
                    OR u.RoomId = rgd.room_number
                    OR REPLACE(REPLACE(TRIM(rgd.room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(COALESCE(NULLIF(p.room_allocation,''), u.RoomId)), ' ', ''), '-', '')
                )
                WHERE (p.room_allocation IN ($in_clause) OR u.RoomId IN ($in_clause) OR rgd.room_number IN ($in_clause))
                ORDER BY p.full_name ASC
            ";
            $stmt = $db->prepare($sql);
            $params = array_merge($room_numbers, $room_numbers, $room_numbers);
            $stmt->execute($params);
            $students = $stmt->fetchAll(PDO::FETCH_ASSOC);
        }
    }

    // Deduplicate students by register_number
    $uniqueStudents = [];
    foreach ($students as $st) {
        $reg = trim($st['register_number'] ?? '');
        if (!empty($reg) && !isset($uniqueStudents[$reg])) {
            $uniqueStudents[$reg] = $st;
        }
    }
    $studentsList = array_values($uniqueStudents);

    // 3. Query Biometric Punches from biometric_punch_logs for this Date
    $bioPunchedMap = [];
    try {
        $bioStmt = $db->prepare("
            SELECT register_no, log_time, punch_type, source
            FROM biometric_punch_logs
            WHERE log_date = ?
            ORDER BY log_time ASC
        ");
        $bioStmt->execute([$date]);
        $bioRows = $bioStmt->fetchAll(PDO::FETCH_ASSOC);
        foreach ($bioRows as $b) {
            $reg = trim((string)$b['register_no']);
            if (!isset($bioPunchedMap[$reg])) {
                $bioPunchedMap[$reg] = $b;
            }
        }
    } catch (Exception $eBio) {}

    // Also query manual attendance table
    $punchedMap = [];
    try {
        $attStmt = $db->prepare("
            SELECT student_id, status, log_time, source, source_type
            FROM attendance
            WHERE DATE(log_time) = ?
            ORDER BY log_time DESC
        ");
        $attStmt->execute([$date]);
        $attendanceRows = $attStmt->fetchAll(PDO::FETCH_ASSOC);
        foreach ($attendanceRows as $att) {
            $sid = trim((string)$att['student_id']);
            if (!isset($punchedMap[$sid])) {
                $punchedMap[$sid] = $att;
            }
        }
    } catch (Exception $eAtt) {}

    // If a specific student search is requested or query is filtered, check live if missing
    $searchParam = trim($_GET['search'] ?? ($_GET['query'] ?? ''));
    if (!empty($searchParam)) {
        foreach ($studentsList as $st) {
            $r = trim($st['register_number'] ?? '');
            $n = trim($st['full_name'] ?? '');
            if ((stripos($r, $searchParam) !== false || stripos($n, $searchParam) !== false) && !isset($bioPunchedMap[$r])) {
                // Live fetch from external biometric API
                $apiUrl = "https://stay.saveetha.com/attendance/vaigai_attendance.php?UserId=" . urlencode($r);
                $ch = curl_init($apiUrl);
                curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
                curl_setopt($ch, CURLOPT_TIMEOUT, 4);
                curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
                $resp = curl_exec($ch);
                $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
                curl_close($ch);

                if ($code === 200 && !empty($resp)) {
                    $json = json_decode($resp, true);
                    $logs = $json['attendance'] ?? ($json['data']['attendance'] ?? []);
                    if (is_array($logs)) {
                        foreach ($logs as $l) {
                            $rawD = $l['LogDate']['date'] ?? $l['LogDate'] ?? $l['date'] ?? null;
                            if ($rawD) {
                                $cleaned = explode('.', $rawD)[0];
                                $parts = explode(' ', $cleaned);
                                if (count($parts) >= 2) {
                                    $dStr = $parts[0];
                                    $tType = strtolower($l['C1'] ?? 'in');
                                    // Process purely in-memory (No database persistence)
                                    if ($dStr === $date && !isset($bioPunchedMap[$r])) {
                                        $bioPunchedMap[$r] = [
                                            'register_no' => $r,
                                            'log_time'    => $cleaned,
                                            'punch_type'  => $tType,
                                            'source'      => 'biometric'
                                        ];
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 4. Query Parent Messages / Notifications for this Date
    $msgStmt = $db->prepare("
        SELECT id, request_id, receiver_id, message, timestamp, status
        FROM chat_messages
        WHERE (message_type = 'attendance_alert' OR receiver_id LIKE 'P_%')
          AND DATE(timestamp) = ?
        ORDER BY timestamp DESC
    ");
    $msgStmt->execute([$date]);
    $msgRows = $msgStmt->fetchAll(PDO::FETCH_ASSOC);

    // Map parent alerts by parent_id or student reg_no
    $parentMsgMap = [];
    foreach ($msgRows as $m) {
        $rec = trim((string)$m['receiver_id']);
        $req = trim((string)$m['request_id']);
        $parentMsgMap[$rec] = $m;
        $parentMsgMap[$req] = $m;
        // Also extract from JSON message if present
        if (!empty($m['message']) && str_starts_with(trim($m['message']), '{')) {
            $decoded = json_decode($m['message'], true);
            if (!empty($decoded['student_name'])) {
                $parentMsgMap[strtolower(trim($decoded['student_name']))] = $m;
            }
        }
    }

    // 5. Cross-check each student
    $punchedCount = 0;
    $missingCount = 0;
    $parentMsgCount = 0;

    $studentRecords = [];

    foreach ($studentsList as $st) {
        $regNo = trim($st['register_number'] ?? '');
        $userId = trim((string)($st['user_id'] ?? ''));
        $profId = trim((string)($st['profile_id'] ?? ''));
        $fullName = trim($st['full_name'] ?? '');

        $isPunched = false;
        $punchTime = null;
        $punchSource = null;

        // 1. Priority: Check biometric_punch_logs
        if (isset($bioPunchedMap[$regNo])) {
            $isPunched = true;
            $punchTime = date('h:i A', strtotime($bioPunchedMap[$regNo]['log_time']));
            $punchSource = 'biometric';
        }

        // 2. Secondary: Check manual attendance table
        if (!$isPunched) {
            $punchLog = null;
            if (isset($punchedMap[$regNo])) {
                $punchLog = $punchedMap[$regNo];
            } elseif (isset($punchedMap[$userId])) {
                $punchLog = $punchedMap[$userId];
            } elseif (isset($punchedMap[$profId])) {
                $punchLog = $punchedMap[$profId];
            }

            if ($punchLog) {
                $stLower = strtolower($punchLog['status'] ?? '');
                if ($stLower === 'present' || $punchLog['source_type'] === 'biometric' || $punchLog['source'] === 'biometric') {
                    $isPunched = true;
                    $punchTime = date('h:i A', strtotime($punchLog['log_time']));
                    $punchSource = $punchLog['source_type'] ?: $punchLog['source'] ?: 'manual';
                }
            }
        }

        // Check if parent message was reached/sent
        $parentId = "P_" . $regNo;
        $hasParentMsg = false;
        $parentMsgTime = null;
        $parentMsgStatus = null;

        if (isset($parentMsgMap[$parentId])) {
            $hasParentMsg = true;
            $parentMsgTime = date('h:i A', strtotime($parentMsgMap[$parentId]['timestamp']));
            $parentMsgStatus = $parentMsgMap[$parentId]['status'] ?? 'sent';
        } elseif (isset($parentMsgMap[strtolower($fullName)])) {
            $hasParentMsg = true;
            $parentMsgTime = date('h:i A', strtotime($parentMsgMap[strtolower($fullName)]['timestamp']));
            $parentMsgStatus = $parentMsgMap[strtolower($fullName)]['status'] ?? 'sent';
        }

        if ($isPunched) {
            $punchedCount++;
        } else {
            $missingCount++;
            if ($hasParentMsg) {
                $parentMsgCount++;
            }
        }

        $studentRecords[] = [
            "id" => $userId ?: $profId,
            "profile_id" => $profId,
            "name" => $fullName,
            "register_number" => $regNo,
            "room_no" => $st['room_no'] ?? 'N/A',
            "hostel_name" => $st['hostel_name'] ?? 'Hostel',
            "floor_name" => $st['floor_name'] ?? 'Floor',
            "is_punched" => $isPunched,
            "punch_time" => $punchTime,
            "punch_source" => $punchSource,
            "parent_msg_reached" => $hasParentMsg,
            "parent_msg_time" => $parentMsgTime,
            "parent_msg_status" => $parentMsgStatus ?: ($hasParentMsg ? 'delivered' : 'pending'),
            "parent_phone" => $st['parent_phone'] ?? $st['phone_number'] ?? '',
        ];
    }

    echo json_encode([
        "status" => "success",
        "date" => $date,
        "summary" => [
            "total_students" => count($studentsList),
            "fingerprint_punched" => $punchedCount,
            "fingerprint_missing" => $missingCount,
            "parent_msg_reached" => $parentMsgCount,
        ],
        "data" => $studentRecords,
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "status" => "error",
        "message" => $e->getMessage()
    ]);
}
