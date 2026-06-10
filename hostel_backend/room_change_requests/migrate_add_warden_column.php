<?php
require_once '../config/database.php';
$database = new DatabaseMysqli();
$conn = $database->getConnection();

// 1. Add column if not exists
$conn->query("ALTER TABLE room_change_requests ADD COLUMN IF NOT EXISTS assigned_warden_username VARCHAR(100) DEFAULT NULL");

// 2. Back-fill existing rows that don't have a warden set yet
$res = $conn->query("SELECT request_id, student_id FROM room_change_requests WHERE assigned_warden_username IS NULL");
$updated = 0;
while ($row = $res->fetch_assoc()) {
    $sid = (int)$row['student_id'];

    // Get student location
    $loc = $conn->query("SELECT hr.hostel_name, hr.floor, hr.wing_code, p.room_allocation
                         FROM users u
                         LEFT JOIN profile p ON u.username = p.reg_no
                         LEFT JOIN hostel_rooms hr ON p.room_allocation = hr.room_code
                         WHERE u.id = $sid LIMIT 1");
    if (!$loc || $loc->num_rows === 0) continue;
    $location = $loc->fetch_assoc();
    if (empty($location['room_allocation']) || strtolower(trim($location['room_allocation'])) === 'unallocated') continue;

    $h = $conn->real_escape_string(strtolower(trim($location['hostel_name'] ?? '')));
    $f = $conn->real_escape_string(strtolower(trim($location['floor'] ?? '')));
    $w = $conn->real_escape_string(strtolower(trim($location['wing_code'] ?? '')));

    // Find best matching warden
    $staff = $conn->query("SELECT username FROM mapping_staff
                           WHERE LOWER(TRIM(role)) = 'warden'
                           AND username != 'warden1'
                           ORDER BY
                             (CASE WHEN LOWER(TRIM(wing_name))  = '$w' THEN 10 ELSE 0 END) +
                             (CASE WHEN LOWER(TRIM(floor_name)) = '$f' THEN 5 ELSE 0 END) +
                             (CASE WHEN LOWER(TRIM(hostel_name))= '$h' THEN 1 ELSE 0 END) DESC
                           LIMIT 1");
    if ($staff && $staff->num_rows > 0) {
        $warden_username = $conn->real_escape_string($staff->fetch_assoc()['username']);
        $rid = $conn->real_escape_string($row['request_id']);
        $conn->query("UPDATE room_change_requests SET assigned_warden_username='$warden_username' WHERE request_id='$rid'");
        $updated++;
    }
}
echo "Done. Column added. Back-filled $updated rows.";
?>
