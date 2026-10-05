<?php
// Set execution timeout to 10 minutes for full sync
set_time_limit(600);
ini_set('display_errors', 0);
error_reporting(E_ALL);

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/db_helper.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

ensureBiometricAuditTables($db);

$isCli = (php_sapi_name() === 'cli');

$limit = isset($_GET['limit']) ? (int)$_GET['limit'] : 100;
$offset = isset($_GET['offset']) ? (int)$_GET['offset'] : 0;
$all = isset($_GET['all']) || $isCli;

$sql = "
    SELECT u.id as user_id, u.username as register_no, u.full_name, u.email,
           COALESCE(p.hostel_name, u.HostelName) as hostel_name,
           COALESCE(p.room_allocation, u.RoomId) as room_allocation,
           u.biometric_id
    FROM users u
    LEFT JOIN profile p ON u.username COLLATE utf8mb4_general_ci = p.reg_no COLLATE utf8mb4_general_ci
    WHERE u.role = 'student' AND u.username IS NOT NULL AND u.username != ''
    ORDER BY u.id ASC
";

if (!$all) {
    $sql .= " LIMIT $limit OFFSET $offset";
}

$students = $db->query($sql)->fetchAll(PDO::FETCH_ASSOC);
$totalProcessed = 0;
$syncedCount = 0;
$notSyncedCount = 0;

$upsertSynced = $db->prepare("
    INSERT INTO biometric_synced_students 
        (user_id, register_no, full_name, email, hostel_name, room_allocation, records_found, last_attendance_date, last_checked_at, biometric_id, notes)
    VALUES 
        (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
        user_id = VALUES(user_id),
        full_name = VALUES(full_name),
        email = VALUES(email),
        hostel_name = VALUES(hostel_name),
        room_allocation = VALUES(room_allocation),
        records_found = VALUES(records_found),
        last_attendance_date = VALUES(last_attendance_date),
        last_checked_at = VALUES(last_checked_at),
        biometric_id = VALUES(biometric_id),
        notes = VALUES(notes),
        updated_at = NOW()
");

$upsertNotSynced = $db->prepare("
    INSERT INTO biometric_not_synced_students 
        (user_id, register_no, full_name, email, hostel_name, room_allocation, last_checked_at, biometric_id, notes)
    VALUES 
        (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
        user_id = VALUES(user_id),
        full_name = VALUES(full_name),
        email = VALUES(email),
        hostel_name = VALUES(hostel_name),
        room_allocation = VALUES(room_allocation),
        last_checked_at = VALUES(last_checked_at),
        biometric_id = VALUES(biometric_id),
        notes = VALUES(notes),
        updated_at = NOW()
");

$deleteSynced = $db->prepare("DELETE FROM biometric_synced_students WHERE register_no = ?");
$deleteNotSynced = $db->prepare("DELETE FROM biometric_not_synced_students WHERE register_no = ?");
$updateUserBioStmt = $db->prepare("UPDATE users SET biometric_id = ? WHERE id = ? AND (biometric_id IS NULL OR biometric_id = '')");

$mh = curl_multi_init();
$batchSize = 25;
$chunks = array_chunk($students, $batchSize);

foreach ($chunks as $chunk) {
    $curlHandles = [];
    foreach ($chunk as $idx => $s) {
        $regNo = trim($s['register_no']);
        $url = "https://stay.saveetha.com/attendance/vaigai_attendance.php?UserId=" . urlencode($regNo);
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_USERAGENT, 'VStay-IT-Audit/1.0');
        curl_multi_add_handle($mh, $ch);
        $curlHandles[$idx] = ['handle' => $ch, 'student' => $s];
    }

    $running = null;
    do {
        curl_multi_exec($mh, $running);
        curl_multi_select($mh);
    } while ($running > 0);

    $now = date('Y-m-d H:i:s');

    foreach ($curlHandles as $item) {
        $ch = $item['handle'];
        $s = $item['student'];
        $raw_response = curl_multi_getcontent($ch);
        $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_multi_remove_handle($mh, $ch);
        curl_close($ch);

        $is_synced = 0;
        $records_count = 0;
        $last_date = null;
        $api_message = '';

        if ($raw_response && $http_code === 200) {
            $api_data = json_decode($raw_response, true);
            $attendance_logs = null;
            if (isset($api_data['data']['attendance']) && is_array($api_data['data']['attendance'])) {
                $attendance_logs = $api_data['data']['attendance'];
            } elseif (isset($api_data['attendance']) && is_array($api_data['attendance'])) {
                $attendance_logs = $api_data['attendance'];
            }

            if (is_array($attendance_logs) && count($attendance_logs) > 0) {
                $is_synced = 1;
                $records_count = count($attendance_logs);
                foreach ($attendance_logs as $log) {
                    $d = $log['LogDate']['date'] ?? $log['LogDate'] ?? $log['date'] ?? null;
                    if ($d) {
                        $cleaned = explode('.', $d)[0];
                        if ($last_date === null || strtotime($cleaned) > strtotime($last_date)) {
                            $last_date = $cleaned;
                        }
                    }
                }
            } else {
                $api_message = $api_data['message'] ?? 'No records';
            }
        } else {
            $api_message = "HTTP $http_code";
        }

        if ($is_synced === 1) {
            $upsertSynced->execute([
                $s['user_id'],
                $s['register_no'],
                $s['full_name'],
                $s['email'],
                $s['hostel_name'],
                $s['room_allocation'],
                $records_count,
                $last_date,
                $now,
                $s['register_no'],
                $api_message
            ]);
            $deleteNotSynced->execute([$s['register_no']]);

            if (!empty($s['user_id'])) {
                try {
                    $updateUserBioStmt->execute([$s['register_no'], $s['user_id']]);
                } catch (Exception $eU) {}
            }
            $syncedCount++;
        } else {
            $upsertNotSynced->execute([
                $s['user_id'],
                $s['register_no'],
                $s['full_name'],
                $s['email'],
                $s['hostel_name'],
                $s['room_allocation'],
                $now,
                $s['biometric_id'],
                $api_message
            ]);
            $deleteSynced->execute([$s['register_no']]);
            $notSyncedCount++;
        }

        $totalProcessed++;
    }
}

curl_multi_close($mh);

$totalStudentsInDb = (int)$db->query("SELECT COUNT(*) FROM users WHERE role = 'student'")->fetchColumn();

echo json_encode([
    "success" => true,
    "processed_count" => $totalProcessed,
    "synced_count" => $syncedCount,
    "not_synced_count" => $notSyncedCount,
    "total_students" => $totalStudentsInDb,
    "has_more" => (!$all && ($offset + $limit < $totalStudentsInDb)),
    "next_offset" => $offset + $limit
]);
