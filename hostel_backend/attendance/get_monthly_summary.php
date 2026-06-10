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

$database = new DatabaseMysqli();
$conn = $database->getConnection();

$month = isset($_GET['month']) ? $_GET['month'] : date('Y-m');
$warden_username = isset($_GET['warden_username']) ? $_GET['warden_username'] : null;

try {
    // 1. Get total student count for this warden
    $student_count_sql = "SELECT COUNT(p.id) as total 
                          FROM profile p
                          JOIN hostel_rooms hr ON (CONVERT(p.room_allocation USING utf8mb4) = CONVERT(hr.room_code USING utf8mb4))";
    
    if ($warden_username) {
        $student_count_sql .= " JOIN mapping_staff ms ON (CONVERT(ms.username USING utf8mb4) = ?)
                                WHERE (TRIM(CONVERT(ms.hostel_name USING utf8mb4)) = TRIM(CONVERT(hr.hostel_name USING utf8mb4)) 
                                       OR TRIM(CONVERT(ms.hostel_name USING utf8mb4)) = TRIM(CONVERT(hr.building_code USING utf8mb4)))
                                  AND (
                                      (TRIM(CONVERT(ms.floor_name USING utf8mb4)) = TRIM(CONVERT(hr.floor USING utf8mb4)))
                                      OR (ms.floor_name = 'Ground' AND hr.floor = 'F00')
                                      OR (ms.floor_name = '1st Floor' AND hr.floor = 'F01')
                                      OR (ms.floor_name = '2nd Floor' AND hr.floor = 'F02')
                                      OR (ms.floor_name IS NULL OR ms.floor_name = '')
                                  )
                                  AND (TRIM(CONVERT(ms.wing_name USING utf8mb4)) = TRIM(CONVERT(hr.wing_code USING utf8mb4)) 
                                       OR ms.wing_name IS NULL OR ms.wing_name = '')
                                  AND ms.role = 'Warden'";
        $st_stmt = $conn->prepare($student_count_sql);
        $st_stmt->bind_param("s", $warden_username);
        $st_stmt->execute();
        $total_students = $st_stmt->get_result()->fetch_assoc()['total'];
    } else {
        $st_res = $conn->query($student_count_sql);
        $total_students = $st_res ? $st_res->fetch_assoc()['total'] : 0;
    }

    // 2. Get daily attendance counts for these students
    // We use a subquery to get the latest/best status per student per day to avoid duplicates
    $sql = "SELECT date, SUM(present_val) as present_count FROM (
                SELECT DATE(a.log_time) as date, a.student_id,
                       MAX(CASE 
                            WHEN a.status IN ('present', 'in', 'IN') THEN 1 
                            WHEN a.status = 'halfday' THEN 0.5 
                            ELSE 0 
                           END) as present_val
                FROM attendance a
                JOIN profile p ON (CONVERT(a.student_id USING utf8mb4) = CONVERT(p.reg_no USING utf8mb4) OR a.student_id = p.id)
                JOIN hostel_rooms hr ON (CONVERT(p.room_allocation USING utf8mb4) = CONVERT(hr.room_code USING utf8mb4))";

    if ($warden_username) {
        $sql .= " JOIN mapping_staff ms ON (CONVERT(ms.username USING utf8mb4) = ?)
                  WHERE (TRIM(CONVERT(ms.hostel_name USING utf8mb4)) = TRIM(CONVERT(hr.hostel_name USING utf8mb4)) 
                         OR TRIM(CONVERT(ms.hostel_name USING utf8mb4)) = TRIM(CONVERT(hr.building_code USING utf8mb4)))
                    AND (
                        (TRIM(CONVERT(ms.floor_name USING utf8mb4)) = TRIM(CONVERT(hr.floor USING utf8mb4)))
                        OR (ms.floor_name = 'Ground' AND hr.floor = 'F00')
                        OR (ms.floor_name = '1st Floor' AND hr.floor = 'F01')
                        OR (ms.floor_name = '2nd Floor' AND hr.floor = 'F02')
                        OR (ms.floor_name IS NULL OR ms.floor_name = '')
                    )
                    AND (TRIM(CONVERT(ms.wing_name USING utf8mb4)) = TRIM(CONVERT(hr.wing_code USING utf8mb4)) 
                         OR ms.wing_name IS NULL OR ms.wing_name = '')
                    AND ms.role = 'Warden'
                    AND a.log_time LIKE '$month-%'
                    GROUP BY DATE(a.log_time), a.student_id
            ) AS daily_student_stats 
            GROUP BY date";
        $stmt = $conn->prepare($sql);
        $stmt->bind_param("s", $warden_username);
        $stmt->execute();
        $result = $stmt->get_result();
    } else {
        $sql .= " WHERE a.log_time LIKE '$month-%' GROUP BY DATE(a.log_time), a.student_id
            ) AS daily_student_stats 
            GROUP BY date";
        $result = $conn->query($sql);
    }

    $daily_data = array();
    $overall_present_sum = 0;
    $days_recorded = 0;

    if ($result) {
        while($row = $result->fetch_assoc()) {
            $day = (int)date('j', strtotime($row['date']));
            $percentage = ($total_students > 0) ? ($row['present_count'] / $total_students) * 100 : 0;
            $daily_data[$day] = round($percentage, 1);
            $overall_present_sum += $percentage;
            $days_recorded++;
        }
    }

    $average_attendance = ($days_recorded > 0) ? ($overall_present_sum / $days_recorded) : 0;

    echo json_encode(array(
        "status" => "success",
        "success" => true,
        "total_students" => $total_students,
        "average_attendance" => round($average_attendance, 1),
        "daily_data" => (object)$daily_data
    ));
} catch (Exception $e) {
    echo json_encode(array(
        "status" => "error",
        "success" => false,
        "message" => $e->getMessage()
    ));
}

$conn->close();
?>
