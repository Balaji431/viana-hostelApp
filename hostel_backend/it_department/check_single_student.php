<?php
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

$input = json_decode(file_get_contents('php://input'), true) ?? [];
$register_no = trim($_GET['register_no'] ?? $input['register_no'] ?? $_GET['UserId'] ?? $input['UserId'] ?? '');
$user_id = trim($_GET['user_id'] ?? $input['user_id'] ?? '');

if (empty($register_no) && empty($user_id)) {
    echo json_encode(["success" => false, "message" => "register_no or user_id is required"]);
    exit();
}

try {
    // 1. Find user from users table
    if (!empty($register_no)) {
        $stmt = $db->prepare("
            SELECT u.id, u.username as register_no, u.full_name, u.email, u.HostelName as hostel_name, u.RoomId as room_allocation, u.biometric_id
            FROM users u
            WHERE u.username = ? OR u.biometric_id = ?
            LIMIT 1
        ");
        $stmt->execute([$register_no, $register_no]);
    } else {
        $stmt = $db->prepare("
            SELECT u.id, u.username as register_no, u.full_name, u.email, u.HostelName as hostel_name, u.RoomId as room_allocation, u.biometric_id
            FROM users u
            WHERE u.id = ?
            LIMIT 1
        ");
        $stmt->execute([(int)$user_id]);
    }

    $student = $stmt->fetch(PDO::FETCH_ASSOC);

    $effectiveRegNo = $student ? $student['register_no'] : $register_no;
    $fullName = $student ? $student['full_name'] : 'Unknown Student';
    $email = $student ? $student['email'] : null;
    $hostelName = $student ? $student['hostel_name'] : null;
    $roomAllocation = $student ? $student['room_allocation'] : null;
    $userId = $student ? (int)$student['id'] : null;

    // Check profile table for hostel / room if missing
    if ($student && (empty($hostelName) || empty($roomAllocation))) {
        try {
            $pStmt = $db->prepare("SELECT hostel_name, room_allocation FROM profile WHERE reg_no = ? LIMIT 1");
            $pStmt->execute([$effectiveRegNo]);
            $pRow = $pStmt->fetch(PDO::FETCH_ASSOC);
            if ($pRow) {
                if (empty($hostelName) && !empty($pRow['hostel_name'])) $hostelName = $pRow['hostel_name'];
                if (empty($roomAllocation) && !empty($pRow['room_allocation'])) $roomAllocation = $pRow['room_allocation'];
            }
        } catch (Exception $eP) {}
    }

    // Check if student is already confirmed registered in biometric_synced_students
    $syncedCheckStmt = $db->prepare("SELECT * FROM biometric_synced_students WHERE register_no = ? LIMIT 1");
    $syncedCheckStmt->execute([$effectiveRegNo]);
    $existingSynced = $syncedCheckStmt->fetch(PDO::FETCH_ASSOC);
    $wasAlreadySynced = !empty($existingSynced);

    // 2. Query external attendance API
    $api_url = "https://stay.saveetha.com/attendance/vaigai_attendance.php?UserId=" . urlencode($effectiveRegNo);
    
    $ch = curl_init($api_url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 5);
    curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 3);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
    curl_setopt($ch, CURLOPT_USERAGENT, 'VStay-IT-Audit/1.0');
    $raw_response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    $is_synced = 0;
    $records_count = 0;
    $last_date = $existingSynced['last_attendance_date'] ?? null;
    $api_message = '';
    $processed = [];

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
            
            $grouped = [];
            foreach ($attendance_logs as $log) {
                $d = $log['LogDate']['date'] ?? $log['LogDate'] ?? $log['date'] ?? null;
                if ($d) {
                    $cleaned = explode('.', $d)[0];
                    $parts = explode(' ', $cleaned);
                    if (count($parts) >= 2) {
                        $date = $parts[0];
                        $time = explode('.', $parts[1])[0];
                        $grouped[$date][] = $time;
                    }
                    if ($last_date === null || strtotime($cleaned) > strtotime($last_date)) {
                        $last_date = $cleaned;
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
                    'source'   => 'biometric'
                ];
            }

            usort($processed, function ($a, $b) {
                return strcmp($b['date'], $a['date']);
            });
        } else {
            $api_message = $api_data['message'] ?? 'No live attendance records returned.';
        }
    } else {
        $api_message = "External API status HTTP $http_code";
    }

    $now = date('Y-m-d H:i:s');

    // 3. Fallback: If live API was unreachable or empty BUT student was ALREADY synced / registered
    if ($is_synced === 0 && $wasAlreadySynced) {
        $is_synced = 1;
        $records_count = (int)($existingSynced['records_found'] ?? 1);
        $last_date = $existingSynced['last_attendance_date'] ?? $now;

        // Check local attendance table for this student
        if ($userId) {
            $attStmt = $db->prepare("SELECT date, in_time, out_time, status, source FROM attendance WHERE student_id = ? ORDER BY date DESC");
            $attStmt->execute([$userId]);
            $localRows = $attStmt->fetchAll(PDO::FETCH_ASSOC);
            if (!empty($localRows)) {
                $processed = $localRows;
            }
        }

        // NOTE: The attendance table stores WARDEN MANUAL MARKS only.
        // Biometric logs are fetched live from the external API (above) for display.
        // Do NOT insert fabricated or biometric data into the attendance table.
        // $processed already contains local warden-marked records (if any).
    }

    if ($is_synced === 1) {
        // Insert/Update into biometric_synced_students
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
        $upsertSynced->execute([
            $userId,
            $effectiveRegNo,
            $fullName,
            $email,
            $hostelName,
            $roomAllocation,
            $records_count,
            $last_date,
            $now,
            $effectiveRegNo,
            $api_message
        ]);

        // Remove from biometric_not_synced_students table
        $db->prepare("DELETE FROM biometric_not_synced_students WHERE register_no = ?")->execute([$effectiveRegNo]);

        // Update users table biometric_id if empty
        if ($userId) {
            try {
                $db->prepare("UPDATE users SET biometric_id = ?, IsBiometric = 1 WHERE id = ? AND (biometric_id IS NULL OR biometric_id = '')")
                   ->execute([$effectiveRegNo, $userId]);
            } catch (Exception $eU) {}
        }
    } else {
        // Only mark not synced if student was never synced and API returned nothing
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
        $upsertNotSynced->execute([
            $userId,
            $effectiveRegNo,
            $fullName,
            $email,
            $hostelName,
            $roomAllocation,
            $now,
            $student['biometric_id'] ?? null,
            $api_message
        ]);

        $db->prepare("DELETE FROM biometric_synced_students WHERE register_no = ?")->execute([$effectiveRegNo]);
    }

    echo json_encode([
        "success" => true,
        "register_no" => $effectiveRegNo,
        "full_name" => $fullName,
        "email" => $email,
        "hostel_name" => $hostelName,
        "room_allocation" => $roomAllocation,
        "is_synced" => ($is_synced === 1),
        "records_found" => $records_count,
        "last_attendance_date" => $last_date,
        "last_checked_at" => $now,
        "api_message" => $api_message,
        "data" => $processed
    ]);

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
