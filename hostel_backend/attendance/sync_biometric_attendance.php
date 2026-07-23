<?php
// Set execution timeout to 10 minutes
set_time_limit(600);
ini_set('display_errors', 1);
error_reporting(E_ALL);

require_once __DIR__ . '/../config/database.php';

// Try standard connection first
$database = new Database();
$db = $database->getConnection();

if (!$db) {
    // Fallback to local XAMPP MySQL ports if docker/standard configuration is not running
    try {
        $db = new PDO('mysql:host=127.0.0.1;port=3306;dbname=stay_simats', 'root', '');
    } catch (Exception $e) {
        try {
            $db = new PDO('mysql:host=127.0.0.1;port=3306;dbname=stay_simats', 'root', 'vstay2026');
        } catch (Exception $e2) {
            die("Database connection failed. Standard config failed, local 3306 (empty password) failed, and local 3306 (vstay2026) failed.\n");
        }
    }
}

echo "Database connection successful!\n";

// 1. Fetch all users who have a biometric_id
$stmt = $db->query("SELECT id, username, biometric_id FROM users WHERE biometric_id IS NOT NULL AND biometric_id != ''");
$users = $stmt->fetchAll(PDO::FETCH_ASSOC);

echo "Found " . count($users) . " users with biometric_id configured.\n";

foreach ($users as $user) {
    $student_id = $user['id'];
    $biometric_id = trim($user['biometric_id']);
    echo "Processing User ID: {$student_id}, Username: {$user['username']}, Biometric ID: {$biometric_id}...\n";
    
    $api_url = "https://stay.saveetha.com/attendance/vaigai_attendance.php?UserId=" . urlencode($biometric_id);
    
    $ctx = stream_context_create(['http' => ['timeout' => 15, 'header' => "User-Agent: BiometricBridge/1.0\r\n"]]);
    $raw_response = @file_get_contents($api_url, false, $ctx);
    
    if (!$raw_response) {
        echo "  [ERROR] Failed to fetch data from API for Biometric ID {$biometric_id}\n";
        continue;
    }
    
    $api_data = json_decode($raw_response, true);
    $attendance_logs = null;
    if (isset($api_data['data']['attendance'])) {
        $attendance_logs = $api_data['data']['attendance'];
    } else if (isset($api_data['attendance'])) {
        $attendance_logs = $api_data['attendance'];
    }
    
    if (!is_array($attendance_logs)) {
        echo "  [WARNING] No attendance logs found or invalid response for Biometric ID {$biometric_id}\n";
        continue;
    }
    
    $inserted_count = 0;
    $skipped_count = 0;
    
    foreach ($attendance_logs as $log) {
        if (isset($log['LogDate']['date'])) {
            $datetime_str = $log['LogDate']['date'];
            // Clean datetime (remove microseconds)
            $parts = explode('.', $datetime_str);
            $log_time = $parts[0];
            
            // Determine direction/status
            $status = 'PRESENT';
            if (isset($log['C1'])) {
                $status = strtoupper(trim($log['C1'])); // 'IN' or 'OUT'
            }
            
            // Check if log already exists in local database
            $check_stmt = $db->prepare("SELECT COUNT(*) FROM attendance WHERE student_id = :student_id AND log_time = :log_time");
            $check_stmt->execute([
                ':student_id' => $student_id,
                ':log_time' => $log_time
            ]);
            $exists = $check_stmt->fetchColumn();
            
            if (!$exists) {
                $insert_stmt = $db->prepare("INSERT INTO attendance (student_id, log_time, status, source, source_type) VALUES (:student_id, :log_time, :status, 'biometric', 'biometric')");
                $insert_stmt->execute([
                    ':student_id' => $student_id,
                    ':log_time' => $log_time,
                    ':status' => $status
                ]);
                $inserted_count++;
            } else {
                $skipped_count++;
            }
        }
    }
    echo "  -> Logs processed: Inserted={$inserted_count}, Skipped (older or existing)={$skipped_count}\n";
}
echo "\nSync completed successfully!\n";
?>
