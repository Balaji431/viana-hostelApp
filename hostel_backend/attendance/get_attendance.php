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
    $stmt = $db->prepare("SELECT username, biometric_id FROM users WHERE id = :id OR username = :id");
    $stmt->execute([':id' => $student_id]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    $biometric_id = (!empty($user['biometric_id'])) ? trim($user['biometric_id']) : (!empty($user['username']) ? trim($user['username']) : null);
    $biometric_success = false;
    $processed = [];
    $active_method = "none";
    $fetch_error = "";

    if ($biometric_id) {
        $college_api_url = "https://stay.saveetha.com/attendance/vaigai_attendance.php?UserId=" . urlencode($biometric_id);
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
                    if (isset($log['LogDate']['date'])) {
                        $datetime_str = $log['LogDate']['date'];
                        $parts = explode(' ', $datetime_str);
                        if (count($parts) >= 2) {
                            $date = $parts[0];
                            $time = explode('.', $parts[1])[0]; // Strip microseconds
                            $grouped[$date][] = $time;
                        }
                    }
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

    // Strictly biometric API logs only (no local DB merging or fallback)


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
