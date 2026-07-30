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

$student_id = isset($_GET['student_id']) ? $_GET['student_id'] : die();

// 🔥 STEP 1: Check for Biometric ID
$stmtBiom = $db->prepare("SELECT biometric_id FROM users WHERE id = :id OR username = :id");
$stmtBiom->execute([':id' => $student_id]);
$user = $stmtBiom->fetch(PDO::FETCH_ASSOC);
$biometric_id = (!empty($user['biometric_id'])) ? trim($user['biometric_id']) : null;

$biometric_logs = [];

if ($biometric_id) {
    $api_url = "https://stay.saveetha.com/attendance/vaigai_attendance.php?UserId=" . urlencode($biometric_id);
    $raw = false;

    // PRIMARY: cURL (works even when allow_url_fopen is disabled)
    if (function_exists('curl_init')) {
        $ch = curl_init($api_url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 15,
            CURLOPT_CONNECTTIMEOUT => 7,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_HTTPHEADER     => [
                "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            ]
        ]);
        $raw = curl_exec($ch);
        if (curl_errno($ch)) $raw = false;
        curl_close($ch);
    }

    // FALLBACK: file_get_contents (if cURL unavailable)
    if ($raw === false && ini_get('allow_url_fopen')) {
        $ctx = stream_context_create(['http' => ['timeout' => 15, 'header' => "User-Agent: BiometricBridge/1.0\r\n"]]);
        $raw = @file_get_contents($api_url, false, $ctx);
    }

    if ($raw) {
        $api_data = json_decode($raw, true);
        $attendance_logs = null;
        if (isset($api_data['data']['attendance'])) {
            $attendance_logs = $api_data['data']['attendance'];
        } else if (isset($api_data['attendance'])) {
            $attendance_logs = $api_data['attendance'];
        }

        if (is_array($attendance_logs)) {
            foreach ($attendance_logs as $log) {
                if (isset($log['LogDate']['date'])) {
                    $datetime_str = $log['LogDate']['date'];
                    $parts = explode('.', $datetime_str); // Strip microseconds
                    $biometric_logs[] = [
                        "status"   => "Biometric",
                        "log_time" => $parts[0]
                    ];
                }
            }
        }
    }
}

// Return strictly biometric machine API logs only
$results = $biometric_logs;
usort($results, function($a, $b) {
    return strtotime($b['log_time']) - strtotime($a['log_time']);
});

echo json_encode(["status" => "success", "data" => $results]);
?>
