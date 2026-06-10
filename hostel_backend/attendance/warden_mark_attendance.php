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
require_once '../send_notification.php';
require_once '../send_parent_notification.php';
require_once '../manual_attendance_functions.php';

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"), true);

if ($data && isset($data['date']) && isset($data['students'])) {
    $date = $data['date']; 
    $students = $data['students'];

    // 1. Prevent marking attendance for any date other than strictly today
    $today = date('Y-m-d');
    if ($date !== $today) {
        echo json_encode(["status" => "error", "message" => "Attendance can strictly only be marked for today ($today)."]);
        exit();
    }
 
    $db->beginTransaction();
    try {
        // 2. Check edit count
        $checkQuery = "SELECT edit_count FROM attendance_tracking WHERE attendance_date = ?";
        $checkStmt = $db->prepare($checkQuery);
        $checkStmt->execute([$date]);
        $tracking = $checkStmt->fetch(PDO::FETCH_ASSOC);
 
        $editCount = $tracking ? $tracking['edit_count'] : 0;
 
        if ($editCount >= 1) {
            echo json_encode(["status" => "error", "message" => "Attendance has already been taken for this day. It can only be taken once per day."]);
            $db->rollBack();
            exit();
        }

        // Prepare delete and insert statements
        // We delete by the provided ID AND try to match by reg_no/profile_id to be safe
        $deleteQuery = "DELETE FROM attendance 
                        WHERE DATE(log_time) = ? 
                        AND (student_id = ? 
                             OR student_id = (SELECT id FROM profile WHERE reg_no = ? LIMIT 1)
                             OR student_id = (SELECT reg_no FROM profile WHERE id = ? LIMIT 1))";
        $delStmt = $db->prepare($deleteQuery);
        
        $insertQuery = "INSERT INTO attendance (student_id, status, log_time, source, source_type) VALUES (?, ?, ?, 'warden', 'manual')";
        $insStmt = $db->prepare($insertQuery);

        // 🔥 PARENT NOTIFICATION: Track absent students
        $absentStudents = [];
        $parentNotifications = [];

        foreach ($students as $student) {
            $student_id = $student['id'];
            $status = $student['status'];
            $log_time = date('Y-m-d H:i:s'); 
            
            $delStmt->execute([$date, $student_id, $student_id, $student_id]);
            $insStmt->execute([$student_id, $status, $log_time]);

            // 🔥 TRACK ABSENT STUDENTS FOR PARENT NOTIFICATIONS
            if (strtolower($status) === 'absent') {
                $absentStudents[] = [
                    'id' => $student_id,
                    'name' => $student['name'] ?? 'Unknown Student',
                    'status' => $status
                ];
            }
        }

        // 3. Update edit count
        if ($tracking) {
            $updateTracking = "UPDATE attendance_tracking SET edit_count = edit_count + 1 WHERE attendance_date = ?";
            $updStmt = $db->prepare($updateTracking);
            $updStmt->execute([$date]);
        } else {
            $insertTracking = "INSERT INTO attendance_tracking (attendance_date, edit_count) VALUES (?, 1)";
            $insTrkStmt = $db->prepare($insertTracking);
            $insTrkStmt->execute([$date]);
        }

        $db->commit();

        // 🔥 LOG MANUAL ATTENDANCE BATCH
        $markedBy = 'warden'; // You can get this from session or user context
        $notes = "Manual attendance marking via warden interface";
        
        $logResult = logManualAttendance($db, $date, $markedBy, $students, $notes);
        // Do not echo result here to keep JSON clean. It's included in the response array.

        // 🔥 SEND PARENT NOTIFICATIONS FOR ABSENT STUDENTS
        if (!empty($absentStudents)) {
            foreach ($absentStudents as $absentStudent) {
                $notificationResult = sendAttendanceNotificationToParents(
                    $absentStudent['id'],
                    $absentStudent['name'],
                    $absentStudent['status'],
                    $date
                );
                
                $parentNotifications[] = [
                    'student_id' => $absentStudent['id'],
                    'student_name' => $absentStudent['name'],
                    'notification_result' => $notificationResult
                ];
            }
        }

        $response = [
            "status" => "success", 
            "message" => "Attendance marked successfully!",
            "absent_students" => count($absentStudents),
            "parent_notifications" => $parentNotifications,
            "manual_attendance_log" => [
                "log_id" => $logResult['success'] ? $logResult['log_id'] : null,
                "logged_by" => $markedBy,
                "notes" => $notes,
                "total_students" => count($students),
                "date" => $date
            ]
        ];

        echo json_encode($response);

    } catch (Exception $e) {
        $db->rollBack();
        echo json_encode(["status" => "error", "message" => "Database error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["status" => "error", "message" => "Invalid request data"]);
}
?>
