<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';



include_once '../config/database.php';

$database = new Database();
$db = $database->getConnection();

$student_id = isset($_GET['student_id']) ? intval($_GET['student_id']) : null;

if (!$student_id) {
    echo json_encode(["status" => false, "message" => "Student ID is required"]);
    exit();
}

try {
    // =========================================================
    // STEP 1: Try biometric API if biometric_id is configured
    // =========================================================
    $stmt = $db->prepare("SELECT biometric_id FROM users WHERE id = :id OR username = :id");
    $stmt->execute([':id' => $student_id]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    $biometric_id = (!empty($user['biometric_id'])) ? trim($user['biometric_id']) : null;
    $biometric_success = false;
    $processed = [];
    $active_method = "none";
    $fetch_error = "";

    if ($biometric_id) {
        $college_api_url = "http://172.25.15.20:8084/hostel-project/api/vaigai-server.php?UserId=" . urlencode($biometric_id);
        $raw_response = false;

        // Try cURL
        if (function_exists('curl_init')) {
            $ch = curl_init($college_api_url);
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT        => 15,
                CURLOPT_CONNECTTIMEOUT => 7,
                CURLOPT_FOLLOWLOCATION => true,
                CURLOPT_HTTPHEADER     => [
                    "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                ]
            ]);
            $raw_response = curl_exec($ch);
            if (curl_errno($ch)) $fetch_error = "cURL Error: " . curl_error($ch);
            curl_close($ch);
            if ($raw_response !== false) $active_method = "curl";
        }

        // Fallback: file_get_contents
        if ($raw_response === false && ini_get('allow_url_fopen')) {
            $ctx = stream_context_create(['http' => ['timeout' => 15, 'header' => "User-Agent: BiometricBridge/1.0\r\n"]]);
            $raw_response = @file_get_contents($college_api_url, false, $ctx);
            if ($raw_response !== false) {
                $active_method = "fopen";
                $fetch_error = ""; 
            } else if (empty($fetch_error)) {
                $fetch_error = "fopen failed";
            }
        }

        if ($raw_response) {
            $api_data = json_decode($raw_response, true);
            $attendance_logs = null;
            if (isset($api_data['data']['attendance'])) {
                $attendance_logs = $api_data['data']['attendance'];
            } else if (isset($api_data['attendance'])) {
                $attendance_logs = $api_data['attendance'];
            }

            if (is_array($attendance_logs)) {
                $grouped = [];
                foreach ($attendance_logs as $log) {
                    $date = $log['date'] ?? null;
                    $time = $log['time'] ?? null;
                    if ($date && $time) $grouped[$date][] = $time;
                }

                foreach ($grouped as $date => $times) {
                    sort($times);
                    $processed[] = [
                        'date'     => $date,
                        'in_time'  => $times[0],
                        'out_time' => count($times) >= 2 ? end($times) : null,
                        'status'   => count($times) >= 2 ? 'present' : 'half_day',
                        'source'   => 'biometric',
                        'method'   => $active_method
                    ];
                }
                $biometric_success = true;
            } else {
                $fetch_error = "Unexpected response format";
            }
        }
    }

    // =========================================================
    // STEP 2: Always merge manual/warden attendance from DB
    //         Manual records override biometric for that date
    // =========================================================
    $manualStmt = $db->prepare(
        "SELECT 
            DATE(log_time)   AS att_date,
            MIN(log_time)    AS in_time,
            MAX(log_time)    AS out_time,
            COUNT(*)         AS scan_count,
            MAX(source)      AS source,
            MAX(CASE WHEN source = 'warden' THEN status END) AS warden_status
         FROM attendance a
         WHERE (student_id = (SELECT id FROM users WHERE id = :id OR username = :id)
            OR student_id = (SELECT username FROM users WHERE id = :id OR username = :id))
         GROUP BY DATE(log_time)
         ORDER BY att_date DESC"
    );
    $manualStmt->execute([':id' => $student_id]);
    $manualRows = $manualStmt->fetchAll(PDO::FETCH_ASSOC);

    $biometricDateMap = [];
    foreach ($processed as $item) {
        $biometricDateMap[$item['date']] = true;
    }

    foreach ($manualRows as $row) {
        $date = $row['att_date'];
        if ($row['source'] === 'warden' && $row['warden_status']) {
            $status = $row['warden_status'];
        } else {
            $count  = intval($row['scan_count']);
            $status = $count >= 2 ? 'present' : ($count === 1 ? 'half_day' : 'absent');
        }

        $in_time  = $row['in_time']  ? date('H:i:s', strtotime($row['in_time']))  : null;
        $out_time = $row['out_time'] && $row['out_time'] !== $row['in_time']
                    ? date('H:i:s', strtotime($row['out_time']))
                    : null;

        if (isset($biometricDateMap[$date])) {
            foreach ($processed as &$item) {
                if ($item['date'] === $date) {
                    $item['status']   = $status;
                    $item['in_time']  = $in_time ?? $item['in_time'];
                    $item['out_time'] = $out_time ?? $item['out_time'];
                    $item['source']   = 'manual_override';
                    break;
                }
            }
            unset($item);
        } else {
            $processed[] = [
                'date'     => $date,
                'in_time'  => $in_time,
                'out_time' => $out_time,
                'status'   => $status,
                'source'   => $row['source'] ?? 'manual',
            ];
        }
    }

    usort($processed, function ($a, $b) {
        return strcmp($b['date'], $a['date']);
    });

    echo json_encode([
        "status"           => true,
        "message"          => "Success",
        "biometric_active" => $biometric_success,
        "biometric_error"  => $fetch_error,
        "total"            => count($processed),
        "data"             => $processed,
    ]);

} catch (PDOException $e) {
    echo json_encode(["status" => false, "message" => "Database error: " . $e->getMessage()]);
}
?>
