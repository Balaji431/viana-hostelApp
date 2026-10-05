<?php
/**
 * trigger_biometric_cutoff_alerts.php
 *
 * Checks biometric punches against the 5:50 PM cutoff deadline.
 * If a student has not placed their fingerprint punch before 5:50 PM on that date,
 * automatically sends a push notification and in-app chat alert to their parents.
 */

set_time_limit(300);
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../send_parent_notification.php';
require_once __DIR__ . '/../send_notification.php';

try {
    $database = new Database();
    $db = $database->getConnection();

    if (!$db) {
        echo json_encode(["status" => "error", "message" => "Database connection failed"]);
        exit();
    }

    $date = trim($_GET['date'] ?? ($_POST['date'] ?? date('Y-m-d')));
    $cutoffTime = trim($_GET['cutoff_time'] ?? ($_POST['cutoff_time'] ?? '18:00:00'));
    $force = isset($_GET['force']) || isset($_POST['force']);
    $wardenUsername = trim($_GET['warden_username'] ?? ($_POST['warden_username'] ?? ''));
    $targetRegNo = trim($_GET['reg_no'] ?? ($_POST['reg_no'] ?? ''));

    // If running for today without force, verify that current time is past 6:00 PM (18:00)
    $today = date('Y-m-d');
    $currentTime = date('H:i:s');
    if ($date === $today && !$force && $currentTime < $cutoffTime) {
        echo json_encode([
            "status" => "skipped",
            "message" => "Cutoff time is 6:00 PM. Current time is $currentTime. Alerts will trigger after 6:00 PM.",
            "current_time" => $currentTime,
            "cutoff_time" => $cutoffTime,
            "date" => $date
        ]);
        exit();
    }

    // 1. Fetch relevant students
    $students = [];
    if (!empty($targetRegNo)) {
        $stmt = $db->prepare("
            SELECT u.id as user_id, u.username as register_number, u.full_name,
                   COALESCE(p.hostel_name, u.HostelName) as hostel_name,
                   COALESCE(p.room_allocation, u.RoomId) as room_no,
                   u.ParentContact, u.ParentName, p.warden
            FROM users u
            LEFT JOIN profile p ON u.username = p.reg_no
            WHERE u.username = ? OR u.id = ?
            LIMIT 1
        ");
        $stmt->execute([$targetRegNo, $targetRegNo]);
        $students = $stmt->fetchAll(PDO::FETCH_ASSOC);
    } elseif (!empty($wardenUsername) && strtolower($wardenUsername) !== 'admin') {
        // Students assigned to this warden
        $stmt = $db->prepare("
            SELECT DISTINCT u.id as user_id, u.username as register_number, u.full_name,
                   COALESCE(p.hostel_name, u.HostelName) as hostel_name,
                   COALESCE(p.room_allocation, u.RoomId) as room_no,
                   u.ParentContact, u.ParentName, p.warden
            FROM users u
            JOIN profile p ON u.username = p.reg_no
            LEFT JOIN rooms_groups_details rgd ON p.room_allocation = rgd.room_number
            WHERE (
                LOWER(TRIM(p.warden)) = LOWER(TRIM(:w))
                OR LOWER(TRIM(rgd.warden_name)) = LOWER(TRIM(:w2))
                OR LOWER(TRIM(rgd.warden_bio_id)) = LOWER(TRIM(:w3))
            )
            AND u.role = 'student' AND (p.room_allocation IS NOT NULL AND p.room_allocation != '')
            ORDER BY u.full_name ASC
        ");
        $stmt->execute([':w' => $wardenUsername, ':w2' => $wardenUsername, ':w3' => $wardenUsername]);
        $students = $stmt->fetchAll(PDO::FETCH_ASSOC);
    } else {
        // All active students with room allocations
        $stmt = $db->query("
            SELECT u.id as user_id, u.username as register_number, u.full_name,
                   COALESCE(p.hostel_name, u.HostelName) as hostel_name,
                   COALESCE(p.room_allocation, u.RoomId) as room_no,
                   u.ParentContact, u.ParentName, p.warden
            FROM users u
            JOIN profile p ON u.username = p.reg_no
            WHERE u.role = 'student' 
              AND (p.room_allocation IS NOT NULL AND p.room_allocation != '')
            ORDER BY u.full_name ASC
        ");
        $students = $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    if (empty($students)) {
        echo json_encode([
            "status" => "success",
            "message" => "No students found to evaluate",
            "date" => $date,
            "cutoff_time" => $cutoffTime,
            "total_students" => 0,
            "alerts_sent" => 0
        ]);
        exit();
    }

    // 2. Query punches on this date on or before cutoff time
    $punchedRegs = [];
    try {
        $bioStmt = $db->prepare("
            SELECT DISTINCT register_no
            FROM biometric_punch_logs
            WHERE log_date = ? AND TIME(log_time) <= ?
        ");
        $bioStmt->execute([$date, $cutoffTime]);
        $punchedRegs = $bioStmt->fetchAll(PDO::FETCH_COLUMN);
    } catch (Exception $eBio) {}

    $punchedRegMap = array_flip($punchedRegs);

    // Also check manual attendance
    $attStmt = $db->prepare("
        SELECT DISTINCT student_id
        FROM attendance
        WHERE DATE(log_time) = ? AND TIME(log_time) <= ? AND status IN ('present', 'in', 'halfday')
    ");
    $attStmt->execute([$date, $cutoffTime]);
    $manualPunched = $attStmt->fetchAll(PDO::FETCH_COLUMN);
    $manualPunchedMap = array_flip($manualPunched);

    // 3. Process each student
    $totalStudents = count($students);
    $punchedCount = 0;
    $missingCount = 0;
    $alertsSent = 0;
    $alreadyAlerted = 0;
    $results = [];

    // Check existing alerts sent today to avoid double sending
    $existingAlertsStmt = $db->prepare("
        SELECT receiver_id
        FROM chat_messages
        WHERE message_type = 'attendance_alert' AND DATE(timestamp) = ?
    ");
    $existingAlertsStmt->execute([$date]);
    $alertedParents = array_flip($existingAlertsStmt->fetchAll(PDO::FETCH_COLUMN));

    foreach ($students as $st) {
        $regNo = trim($st['register_number'] ?? '');
        $userId = trim((string)($st['user_id'] ?? ''));
        $name = trim($st['full_name'] ?? '');
        $parentId = "P_" . $regNo;

        // Check if student has punched before cutoff time
        $hasPunched = isset($punchedRegMap[$regNo]) || isset($manualPunchedMap[$regNo]) || isset($manualPunchedMap[$userId]);

        if ($hasPunched) {
            $punchedCount++;
            continue;
        }

        // Student did NOT punch before cutoff (5:50 PM) -> ABSENT
        $missingCount++;

        // Check if parent was already alerted today
        if (isset($alertedParents[$parentId])) {
            $alreadyAlerted++;
            $results[] = [
                "register_no" => $regNo,
                "name" => $name,
                "status" => "absent",
                "alert_status" => "already_alerted_today"
            ];
            continue;
        }

        // Send parent notification & push notification
        $alertMessage = "Dear Parent, your child $name ($regNo) has not placed their fingerprint punch before 6:00 PM today ($date) and is marked ABSENT.";
        
        $notifRes = sendAttendanceNotificationToParents(
            $userId ?: $regNo,
            $name,
            'ABSENT',
            $date
        );

        // Also ensure chat_messages has the explicit 6:00 PM cutoff detail
        try {
            $absentData = [
                "title" => "Biometric Attendance Alert ⚠️",
                "student_name" => $name,
                "register_no" => $regNo,
                "status" => "ABSENT",
                "cutoff_time" => "6:00 PM",
                "date" => $date,
                "message" => $alertMessage
            ];
            $jsonPayload = json_encode($absentData);

            $reqId = $notifRes['request_id'] ?? ("PAR-" . time() . rand(10, 99));
            $senderWarden = !empty($st['warden']) ? $st['warden'] : ($wardenUsername ?: 'warden1');

            $db->prepare("
                INSERT INTO chat_messages (request_id, sender_id, receiver_id, message, message_type, status)
                VALUES (?, ?, ?, ?, 'attendance_alert', 'sent')
            ")->execute([$reqId, $senderWarden, $parentId, $jsonPayload]);

        } catch (Exception $eChat) {}

        $alertsSent++;
        $results[] = [
            "register_no" => $regNo,
            "name" => $name,
            "status" => "absent",
            "alert_status" => "alert_sent",
            "fcm_response" => $notifRes['fcm_response'] ?? null
        ];
    }

    echo json_encode([
        "status"                 => "success",
        "message"                => "Processed 5:50 PM biometric cutoff alerts",
        "date"                   => $date,
        "cutoff_time"            => "17:50:00 (05:50 PM)",
        "total_students"         => $totalStudents,
        "punched_before_cutoff"  => $punchedCount,
        "absent_missing"         => $missingCount,
        "alerts_sent_now"        => $alertsSent,
        "already_alerted"        => $alreadyAlerted,
        "results_sample"         => array_slice($results, 0, 10)
    ]);

} catch (Throwable $e) {
    echo json_encode([
        "status"  => "error",
        "message" => "Error: " . $e->getMessage() . " on line " . $e->getLine()
    ]);
}
