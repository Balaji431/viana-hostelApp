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
require_once '../utils/auth_helper.php';

$authUser = requireAuth(['warden', 'admin', 'super_admin']);

$database = new DatabaseMysqli();
$conn = $database->getConnection();

$data = json_decode(file_get_contents("php://input"), true);

$renewalId = $data['renewal_id'] ?? null;
$wardenId = $authUser['id'] ?? ($data['warden_id'] ?? null);

try {
    // 1️⃣ Get request details
    $stmt = $conn->prepare("SELECT student_id, student_reg_no FROM renewal_requests WHERE id=?");
    $stmt->bind_param("i", $renewalId);
    $stmt->execute();
    $result = $stmt->get_result();
    $req = $result->fetch_assoc();

    if (!$req) throw new Exception("Request not found");

    $regNo = $req['student_reg_no'];

    // 2️⃣ Extend validity (1 year from latest date)
    $pStmt = $conn->prepare("SELECT renewal_date, valid_to FROM profile WHERE reg_no = ?");
    $pStmt->bind_param("s", $regNo);
    $pStmt->execute();
    $pRes = $pStmt->get_result()->fetch_assoc();

    $baseDate = date('Y-m-d');
    if ($pRes) {
        if (!empty($pRes['renewal_date']) && strtotime($pRes['renewal_date']) > strtotime($baseDate)) {
            $baseDate = $pRes['renewal_date'];
        }
        if (!empty($pRes['valid_to']) && strtotime($pRes['valid_to']) > strtotime($baseDate)) {
            $baseDate = $pRes['valid_to'];
        }
    }
    $newDate = date('Y-m-d', strtotime("$baseDate +1 year"));
    $remDays = max(0, (int)round((strtotime($newDate) - strtotime(date('Y-m-d'))) / 86400));

    $updateProfile = "
        UPDATE profile 
        SET valid_from = IF(valid_from IS NULL OR valid_from = '0000-00-00', CURRENT_DATE, valid_from),
            valid_to = ?,
            renewal_date = ?,
            remaining_days = ?
        WHERE reg_no = ?
    ";

    $stmt2 = $conn->prepare($updateProfile);
    $stmt2->bind_param("ssis", $newDate, $newDate, $remDays, $regNo);
    $stmt2->execute();

    // 3️⃣ Get warden name
    $wardenName = null;
    if ($wardenId) {
        $stmt3 = $conn->prepare("SELECT full_name FROM users WHERE id=?");
        $stmt3->bind_param("i", $wardenId);
        $stmt3->execute();
        $res3 = $stmt3->get_result();
        $warden = $res3->fetch_assoc();
        $wardenName = $warden['full_name'] ?? null;
    }

    // 4️⃣ Update request
    $stmt4 = $conn->prepare("
        UPDATE renewal_requests 
        SET status='approved',
            processed_by=?,
            processed_by_name=?,
            processed_at=NOW()
        WHERE id=?
    ");

    $stmt4->bind_param("isi", $wardenId, $wardenName, $renewalId);
    $stmt4->execute();

    echo json_encode([
        "success" => true,
        "status" => "success",
        "message" => "Renewal approved successfully"
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "status" => "error",
        "message" => $e->getMessage()
    ]);
}
?>
