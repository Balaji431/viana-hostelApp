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

$database = new Database();
$db = $database->getConnection();

$warden_username = $_GET['warden_username'] ?? null;
$student_username = $_GET['student_username'] ?? null;

$summary = array(
    "warden"        => 0,
    "parent_warden" => 0,
    "security"      => 0,
    "maintenance"   => 0
);

if (empty($warden_username) && empty($student_username)) {
    echo json_encode(array("status" => "success", "data" => $summary));
    exit;
}

try {
    if ($student_username) {
        // Resolve student canonical username and integer ID
        $user_stmt = $db->prepare("SELECT id, username FROM users WHERE (CONVERT(username USING utf8mb4) = CONVERT(? USING utf8mb4)) OR id = ? LIMIT 1");
        $user_stmt->execute([$student_username, $student_username]);
        $user_row = $user_stmt->fetch(PDO::FETCH_ASSOC);
        
        $stu_username = $user_row ? $user_row['username'] : $student_username;
        $stu_id = $user_row ? $user_row['id'] : $student_username;

        // Unread messages sent TO this student (sender != student)
        $sql = "SELECT LOWER(TRIM(r.department)) as department, COUNT(*) as unread_count 
                FROM chat_messages m 
                JOIN request1 r ON (CONVERT(m.request_id USING utf8mb4) = CONVERT(r.request_id USING utf8mb4)) 
                WHERE m.status IN ('sent', 'delivered') 
                  AND m.message_type NOT IN ('request_card', 'status')
                  AND (
                    CONVERT(m.receiver_id USING utf8mb4) = CONVERT(:stu_username USING utf8mb4)
                    OR CONVERT(m.receiver_id USING utf8mb4) = CONVERT(:stu_id USING utf8mb4)
                    OR CONVERT(r.student_id USING utf8mb4) = CONVERT(:stu_id USING utf8mb4)
                    OR CONVERT(r.student_id USING utf8mb4) = CONVERT(:stu_username USING utf8mb4)
                  )
                  AND CONVERT(m.sender_id USING utf8mb4) != CONVERT(:stu_username USING utf8mb4)
                  AND CONVERT(m.sender_id USING utf8mb4) != CONVERT(:stu_id USING utf8mb4)
                GROUP BY LOWER(TRIM(r.department))";
        
        $stmt = $db->prepare($sql);
        $stmt->execute([
            ':stu_username' => $stu_username,
            ':stu_id'       => $stu_id
        ]);
    } else {
        // Resolve warden / staff username, ID, staff_bio_id
        $user_stmt = $db->prepare("SELECT id, username FROM users WHERE (CONVERT(username USING utf8mb4) = CONVERT(? USING utf8mb4)) OR id = ? LIMIT 1");
        $user_stmt->execute([$warden_username, $warden_username]);
        $user_row = $user_stmt->fetch(PDO::FETCH_ASSOC);
        
        $w_username = $user_row ? $user_row['username'] : $warden_username;
        $w_id = $user_row ? $user_row['id'] : $warden_username;

        // Also resolve staff_bio_id from mapping_staff if present
        $ms_stmt = $db->prepare("SELECT staff_bio_id FROM mapping_staff WHERE (CONVERT(username USING utf8mb4) = CONVERT(? USING utf8mb4)) OR (CONVERT(staff_bio_id USING utf8mb4) = CONVERT(? USING utf8mb4)) LIMIT 1");
        $ms_stmt->execute([$w_username, $w_username]);
        $ms_row = $ms_stmt->fetch(PDO::FETCH_ASSOC);
        $w_bio_id = ($ms_row && !empty($ms_row['staff_bio_id'])) ? $ms_row['staff_bio_id'] : $w_username;

        // Unread messages sent BY STUDENTS to this warden/department where sender is NOT the warden
        $sql = "SELECT LOWER(TRIM(r.department)) as department, COUNT(*) as unread_count 
                FROM chat_messages m 
                JOIN request1 r ON (CONVERT(m.request_id USING utf8mb4) = CONVERT(r.request_id USING utf8mb4)) 
                WHERE m.status IN ('sent', 'delivered') 
                  AND m.message_type NOT IN ('request_card', 'status')
                  AND (
                    CONVERT(m.receiver_id USING utf8mb4) = CONVERT(:w_username USING utf8mb4)
                    OR CONVERT(m.receiver_id USING utf8mb4) = CONVERT(:w_id USING utf8mb4)
                    OR CONVERT(m.receiver_id USING utf8mb4) = CONVERT(:w_bio_id USING utf8mb4)
                    OR CONVERT(m.receiver_id USING utf8mb4) = 'warden'
                    OR CONVERT(m.receiver_id USING utf8mb4) = 'warden1'
                  )
                  AND CONVERT(m.sender_id USING utf8mb4) != CONVERT(:w_username USING utf8mb4)
                  AND CONVERT(m.sender_id USING utf8mb4) != CONVERT(:w_id USING utf8mb4)
                  AND CONVERT(m.sender_id USING utf8mb4) != CONVERT(:w_bio_id USING utf8mb4)
                GROUP BY LOWER(TRIM(r.department))";
        
        $stmt = $db->prepare($sql);
        $stmt->execute([
            ':w_username' => $w_username,
            ':w_id'       => $w_id,
            ':w_bio_id'   => $w_bio_id
        ]);
    }

    while($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $dept = strtolower(trim($row['department']));
        if ($dept == 'messages' || strpos($dept, 'warden') !== false) $dept = 'warden';
        else if (strpos($dept, 'maint') !== false) $dept = 'maintenance';
        else if (strpos($dept, 'sec') !== false) $dept = 'security';
        $summary[$dept] = (int)$row['unread_count'];
    }

    echo json_encode(array("status" => "success", "data" => $summary));
} catch (Exception $e) {
    echo json_encode(array("status" => "error", "message" => $e->getMessage()));
}
?>