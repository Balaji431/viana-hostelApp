<?php
/**
 * get_student_by_regno.php
 * Fetches full student details by registration number.
 * Used by Room Master screen when clicking a bed cell to see student info.
 *
 * GET/POST params:
 *   reg_no  - student registration number
 */
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') { 
    exit(0); 
}

require_once __DIR__ . '/../config/database.php';

$regNo = trim($_GET['reg_no'] ?? $_POST['reg_no'] ?? '');
if (empty($regNo)) {
    echo json_encode(['success' => false, 'message' => 'reg_no is required']);
    exit;
}

try {
    $database = new Database();
    $db = $database->getConnection();

    if (!$db) {
        echo json_encode(['success' => false, 'message' => 'Database connection failed']);
        exit;
    }

    // 1. Primary: profile table
    $stmt = $db->prepare("
        SELECT
            COALESCE(NULLIF(p.full_name,''), NULLIF(su.full_name,''), 'Student') AS student_name,
            p.reg_no,
            COALESCE(NULLIF(p.email,''), su.email, '') AS email,
            COALESCE(NULLIF(p.personal_phone,''), su.phone_number, '') AS phone,
            p.room_allocation,
            p.hostel_name,
            COALESCE(p.renewal_date, p.valid_to) AS renewal_date,
            COALESCE(p.check_in_date, p.valid_from) AS check_in_date,
            p.valid_from,
            p.valid_to,
            COALESCE(su.status, 'Active') AS status,
            p.bed_no,
            p.institution,
            p.warden,
            COALESCE(NULLIF(su.gender,''), 'Male') AS gender,
            su.course,
            su.department,
            su.academic_year,
            COALESCE(NULLIF(su.room_type,''), '') AS room_type
        FROM profile p
        LEFT JOIN student_users su ON su.reg_no = p.reg_no
        WHERE p.reg_no = ?
        LIMIT 1
    ");
    $stmt->execute([$regNo]);
    $student = $stmt->fetch(PDO::FETCH_ASSOC);

    // 2. Fallback: student_users table
    if (!$student) {
        $stmt2 = $db->prepare("
            SELECT
                su.full_name AS student_name,
                su.reg_no,
                su.email,
                su.phone_number AS phone,
                su.room_allocation,
                su.hostel_name,
                NULL AS renewal_date,
                NULL AS check_in_date,
                NULL AS valid_from,
                NULL AS valid_to,
                su.status,
                su.bed_no,
                su.institution,
                su.warden,
                COALESCE(su.gender, 'Male') AS gender,
                su.course,
                su.department,
                su.academic_year,
                su.room_type
            FROM student_users su
            WHERE su.reg_no = ?
            LIMIT 1
        ");
        $stmt2->execute([$regNo]);
        $student = $stmt2->fetch(PDO::FETCH_ASSOC);
    }

    // 3. Fallback: users table directly
    if (!$student) {
        $stmt3 = $db->prepare("
            SELECT
                u.full_name AS student_name,
                u.username AS reg_no,
                u.email,
                COALESCE(NULLIF(u.phone_number,''), u.ContactNumber, '') AS phone,
                u.RoomId AS room_allocation,
                u.HostelName AS hostel_name,
                u.DOL AS renewal_date,
                u.DOJ AS check_in_date,
                NULL AS valid_from,
                NULL AS valid_to,
                u.Status AS status,
                '' AS bed_no,
                u.Institution AS institution,
                '' AS warden,
                COALESCE(u.Gender, 'Male') AS gender,
                u.Course AS course,
                u.department,
                u.Academic AS academic_year,
                u.RoomType AS room_type
            FROM users u
            WHERE u.username = ?
            LIMIT 1
        ");
        $stmt3->execute([$regNo]);
        $student = $stmt3->fetch(PDO::FETCH_ASSOC);
    }

    if (!$student) {
        echo json_encode(['success' => false, 'message' => "Student '$regNo' not found"]);
        exit;
    }

    // Strip country code prefix (91, +91, 0) from phone to return clean 10-digit number
    $phone = trim($student['phone'] ?? '');
    $phone = preg_replace('/[^0-9]/', '', $phone);
    if (strlen($phone) > 10) {
        if (substr($phone, 0, 2) === '91' && strlen($phone) === 12) {
            $phone = substr($phone, 2);
        } elseif (substr($phone, 0, 1) === '0' && strlen($phone) === 11) {
            $phone = substr($phone, 1);
        } else {
            $phone = substr($phone, -10);
        }
    }
    $student['phone'] = $phone;

    echo json_encode([
        'success' => true,
        'student' => $student,
    ]);
} catch (Exception $e) {
    echo json_encode(['success' => false, 'message' => $e->getMessage()]);
}
?>
