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
    $api_url = "http://172.25.15.20:8084/hostel-project/api/vaigai-server.php?UserId=" . urlencode($biometric_id);
    
    // Attempt fetch with User-Agent
    $ctx = stream_context_create(['http' => ['timeout' => 15, 'header' => "User-Agent: BiometricBridge/1.0\r\n"]]);
    $raw = @file_get_contents($api_url, false, $ctx);
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
                if (isset($log['date']) && isset($log['time'])) {
                    $biometric_logs[] = [
                        "status" => "Biometric",
                        "log_time" => $log['date'] . " " . $log['time']
                    ];
                }
            }
        }
    }
}

// 🔥 STEP 2: Fetch Local Records
$query = "SELECT 'Manual' as status, log_time FROM attendance WHERE (student_id = (SELECT id FROM users WHERE id = :id OR username = :id) OR student_id = (SELECT username FROM users WHERE id = :id OR username = :id)) ORDER BY log_time DESC";
$stmt = $db->prepare($query);
$stmt->execute([':id' => $student_id]);
$manual_results = $stmt->fetchAll(PDO::FETCH_ASSOC);

// 🔥 STEP 3: Merge and Sort
$results = array_merge($biometric_logs, $manual_results);
usort($results, function($a, $b) {
    return strtotime($b['log_time']) - strtotime($a['log_time']);
});

echo json_encode(["status" => "success", "data" => $results]);
?>
