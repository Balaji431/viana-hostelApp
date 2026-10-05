<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

if (!$conn) {
    echo json_encode(["status" => "error", "success" => false, "message" => "Database connection failed"]);
    exit();
}

$warden_username = trim($_GET['warden_username'] ?? $_POST['warden_username'] ?? '');
$status_filter = trim($_GET['status'] ?? $_POST['status'] ?? 'all');

if (empty($warden_username)) {
    $raw = file_get_contents("php://input");
    $body = json_decode($raw, true);
    if (is_array($body)) {
        $warden_username = trim($body['warden_username'] ?? '');
        $status_filter = trim($body['status'] ?? 'all');
    }
}

// 1. Fetch managed hostels for this warden
$managed_hostels = [];
if (!empty($warden_username) && $warden_username !== 'admin') {
    $h_stmt = $conn->prepare("SELECT DISTINCT hostel_name FROM mapping_staff WHERE staff_bio_id = ? OR username = ?");
    $h_stmt->bind_param("ss", $warden_username, $warden_username);
    $h_stmt->execute();
    $h_res = $h_stmt->get_result();
    while ($hr = $h_res->fetch_assoc()) {
        if (!empty($hr['hostel_name'])) {
            $managed_hostels[] = trim($hr['hostel_name']);
        }
    }
}

// 2. Build query
$where_clauses = ["1=1"];
$params = [];
$types = "";

if ($status_filter !== 'all' && !empty($status_filter)) {
    $where_clauses[] = "vr.status = ?";
    $params[] = $status_filter;
    $types .= "s";
}

$sql = "
    SELECT 
        vr.*,
        COALESCE(u.phone_number, p.personal_phone, '') as student_phone,
        COALESCE(u.ParentContact, '') as parent_phone,
        COALESCE(u.department, '') as department,
        p.valid_to,
        DATEDIFF(vr.renewal_date, vr.expected_vacate_date) as remaining_days_at_vacate
    FROM vacate_requests vr
    LEFT JOIN users u ON vr.student_reg_no = u.username
    LEFT JOIN profile p ON vr.student_reg_no = p.reg_no
    WHERE " . implode(" AND ", $where_clauses) . "
    ORDER BY vr.created_at DESC
";

$stmt = $conn->prepare($sql);
if (!empty($params)) {
    $stmt->bind_param($types, ...$params);
}
$stmt->execute();
$res = $stmt->get_result();

$requests = [];
while ($row = $res->fetch_assoc()) {
    // Check warden filtering
    if (!empty($warden_username) && $warden_username !== 'admin') {
        $assigned_w = trim($row['assigned_warden_username'] ?? '');
        $req_hostel = trim($row['hostel_name'] ?? '');

        $is_match = false;
        if ($assigned_w === $warden_username) {
            $is_match = true;
        } else {
            foreach ($managed_hostels as $mh) {
                if (!empty($mh) && stripos($req_hostel, $mh) !== false) {
                    $is_match = true;
                    break;
                }
            }
        }
        if (!$is_match && !empty($managed_hostels)) {
            continue;
        }
    }

    $requests[] = [
        'id' => (int)$row['id'],
        'request_id' => $row['request_id'],
        'student_id' => (int)$row['student_id'],
        'student_reg_no' => $row['student_reg_no'],
        'student_name' => $row['student_name'],
        'hostel_name' => $row['hostel_name'],
        'room_number' => $row['room_number'],
        'renewal_date' => $row['renewal_date'],
        'expected_vacate_date' => $row['expected_vacate_date'],
        'remaining_days' => max(0, (int)($row['remaining_days_at_vacate'] ?? 0)),
        'reason' => $row['reason'],
        'status' => $row['status'],
        'rejection_reason' => $row['rejection_reason'],
        'assigned_warden_name' => $row['assigned_warden_name'],
        'assigned_warden_username' => $row['assigned_warden_username'],
        'processed_by_name' => $row['processed_by_name'],
        'processed_at' => $row['processed_at'],
        'remarks' => $row['remarks'],
        'created_at' => $row['created_at'],
        'student_phone' => $row['student_phone'] ?? '',
        'parent_phone' => $row['parent_phone'] ?? ''
    ];
}

echo json_encode([
    "status" => "success",
    "success" => true,
    "count" => count($requests),
    "data" => $requests
]);

$conn->close();
?>
