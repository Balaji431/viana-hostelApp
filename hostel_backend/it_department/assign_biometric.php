<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../send_notification.php';
require_once __DIR__ . '/../utils/auth_helper.php';
require_once __DIR__ . '/db_helper.php';

$authUser = requireAuth(['it', 'admin', 'super_admin', 'warden']);

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

ensureBiometricAuditTables($db);

$input = json_decode(file_get_contents('php://input'), true) ?? [];
$register_no = trim($input['register_no'] ?? $_POST['register_no'] ?? '');
$biometric_id = trim($input['biometric_id'] ?? $_POST['biometric_id'] ?? $register_no);
$notes = trim($input['notes'] ?? $_POST['notes'] ?? 'Biometric ID Assigned for punch registration.');
$created_by = trim($input['created_by'] ?? $_POST['created_by'] ?? 'IT Department');

if (empty($register_no) || empty($biometric_id)) {
    echo json_encode(["success" => false, "message" => "Please enter a valid student register number and biometric machine ID first."]);
    exit();
}

try {
    // 1. Get student info
    $stmt = $db->prepare("
        SELECT u.id, u.username, u.full_name, u.email, u.fcm_token, COALESCE(p.hostel_name, u.HostelName) as hostel_name, COALESCE(p.room_allocation, u.RoomId) as room_no
        FROM users u
        LEFT JOIN profile p ON u.username COLLATE utf8mb4_general_ci = p.reg_no COLLATE utf8mb4_general_ci
        WHERE u.username = ?
        LIMIT 1
    ");
    $stmt->execute([$register_no]);
    $student = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$student) {
        echo json_encode(["success" => false, "message" => "Student account ($register_no) not found in the hostel system. Please verify registration number."]);
        exit();
    }

    $roomNo = $student['room_no'] ?? 'N/A';
    $fullName = $student['full_name'] ?? 'Student';
    $hostelName = $student['hostel_name'] ?? 'N/A';
    $email = $student['email'] ?? null;
    $fcmToken = $student['fcm_token'] ?? null;
    $userId = (int)$student['id'];

    // 2. Query external biometric attendance API with the biometric_id
    $api_url = "https://stay.saveetha.com/attendance/vaigai_attendance.php?UserId=" . urlencode($biometric_id);
    
    $ch = curl_init($api_url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 10);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_USERAGENT, 'VStay-IT-Audit/1.0');
    $raw_response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    $is_synced = false;
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
            $is_synced = true;
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
            $api_message = $api_data['message'] ?? 'No attendance punch records found on machine.';
        }
    } else {
        $api_message = "External machine API returned HTTP $http_code";
    }

    // 3. IF NO RECORDS FOUND ON MACHINE: DO NOT SEND NOTIFICATION TO STUDENT
    if (!$is_synced) {
        $noteMsg = "Assigned BioID: $biometric_id by $created_by on " . date('Y-m-d H:i') . " | Machine check pending: $api_message";
        
        // Update users table
        try {
            $db->prepare("UPDATE users SET biometric_id = ? WHERE username = ?")->execute([$biometric_id, $register_no]);
        } catch (Exception $eUser) {}

        // Upsert into biometric_not_synced_students
        $db->prepare("
            INSERT INTO biometric_not_synced_students 
                (user_id, register_no, full_name, email, hostel_name, room_allocation, last_checked_at, biometric_id, notes)
            VALUES 
                (?, ?, ?, ?, ?, ?, NOW(), ?, ?)
            ON DUPLICATE KEY UPDATE
                biometric_id = VALUES(biometric_id),
                notes = CONCAT(COALESCE(notes, ''), ' | ', VALUES(notes)),
                last_checked_at = NOW(),
                updated_at = NOW()
        ")->execute([$userId, $register_no, $fullName, $email, $hostelName, $roomNo, $biometric_id, $noteMsg]);

        // Clean up from synced table if previously present
        $db->prepare("DELETE FROM biometric_synced_students WHERE register_no = ?")->execute([$register_no]);

        // Return error message to IT Department (no student notification sent)
        echo json_encode([
            "success" => false,
            "message" => "No biometric punch records found on the machine for ID '$biometric_id'. Please enroll the student's fingerprint on the biometric machine first before activating.",
            "records_found" => 0,
            "is_synced" => false,
            "biometric_id" => $biometric_id,
            "register_no" => $register_no
        ]);
        exit();
    }

    // 4. IF RECORDS EXIST ON MACHINE: PROCEED WITH ACTIVATION & NOTIFY STUDENT
    // Update biometric_id in users table
    try {
        $db->prepare("UPDATE users SET biometric_id = ? WHERE username = ?")->execute([$biometric_id, $register_no]);
    } catch (Exception $eUser) {}

    $noteMsg = "Assigned BioID: $biometric_id by $created_by on " . date('Y-m-d H:i') . " | Verified ($records_count records)";

    // Insert/Update in biometric_synced_students
    $upsertSynced = $db->prepare("
        INSERT INTO biometric_synced_students 
            (user_id, register_no, full_name, email, hostel_name, room_allocation, records_found, last_attendance_date, last_checked_at, biometric_id, notes)
        VALUES 
            (?, ?, ?, ?, ?, ?, ?, ?, NOW(), ?, ?)
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
    $upsertSynced->execute([
        $userId,
        $register_no,
        $fullName,
        $email,
        $hostelName,
        $roomNo,
        $records_count,
        $last_date,
        $biometric_id,
        $noteMsg
    ]);

    // Remove from not_synced table
    $db->prepare("DELETE FROM biometric_not_synced_students WHERE register_no = ?")->execute([$register_no]);

    // 5. Create request ticket in request1
    $requestId = 'IT-' . time() . '-' . rand(100, 999);
    $reqType = 'Biometric Registration';
    $dept = 'it';
    $purpose = "Biometric Profile Setup (ID: $biometric_id): $notes";

    $reqStmt = $db->prepare("
        INSERT INTO request1 
            (request_id, student_id, request_type, departure_date, return_date, destination, purpose, attachment, room_number, status, department)
        VALUES 
            (?, ?, ?, NULL, NULL, NULL, ?, NULL, ?, 'pending', ?)
    ");
    $reqStmt->execute([
        $requestId,
        $register_no,
        $reqType,
        $purpose,
        $roomNo,
        $dept
    ]);

    // 6. Insert initial chat message
    try {
        $chatStmt = $db->prepare("
            INSERT INTO chat_messages (request_id, sender_id, sender_role, message, timestamp)
            VALUES (?, ?, 'it', ?, NOW())
        ");
        $chatStmt->execute([
            $requestId,
            $created_by,
            "Dear $fullName, your Biometric Attendance Profile (ID: $biometric_id) has been verified ($records_count punch logs) and activated in the hostel attendance system. You can now use the biometric readers for daily attendance punch."
        ]);
    } catch (Exception $eChat) {}

    // 7. Send push notification & in-app notification to student ONLY when verified
    $notifTitle = "Biometric Profile Activated";
    $notifBody = "Dear $fullName, your biometric attendance profile (ID: $biometric_id) has been registered and verified. You can now punch your attendance at the hostel biometric readers.";

    try {
        if (!empty($fcmToken) && function_exists('sendFCM')) {
            sendFCM(
                $fcmToken,
                $notifTitle,
                $notifBody,
                $requestId,
                'IT-DEPT',
                'IT Department',
                $notifBody,
                'biometric_sync',
                'it'
            );
        }
    } catch (Exception $eNotif) {}

    try {
        $insNotif = $db->prepare("
            INSERT INTO notifications (user_id, register_no, title, message, type, is_read, created_at)
            VALUES (?, ?, ?, ?, 'biometric_sync', 0, NOW())
        ");
        $insNotif->execute([$userId, $register_no, $notifTitle, $notifBody]);
    } catch (Exception $eNotifDb) {}

    echo json_encode([
        "success" => true,
        "message" => "Biometric ID verified ($records_count records found)! Profile activated and notification sent to student.",
        "request_id" => $requestId,
        "biometric_id" => $biometric_id,
        "records_found" => $records_count,
        "register_no" => $register_no
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
