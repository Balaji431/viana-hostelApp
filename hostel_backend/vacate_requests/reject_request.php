<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/auth_helper.php';

$authUser = requireAuth(['warden', 'admin', 'super_admin']);

$database = new DatabaseMysqli();
$conn = $database->getConnection();

if (!$conn) {
    echo json_encode(["status" => "error", "success" => false, "message" => "Database connection failed"]);
    exit();
}

$raw = file_get_contents("php://input");
$data = json_decode($raw, true) ?? [];

$request_id = trim($data['request_id'] ?? ($_POST['request_id'] ?? ''));
$warden_username = $authUser['username'] ?? 'warden';
$warden_name = $authUser['full_name'] ?? ($data['warden_name'] ?? 'Hostel Warden');
$rejection_reason = trim($data['rejection_reason'] ?? $data['reason'] ?? ($_POST['rejection_reason'] ?? 'Rejected by hostel warden'));

if (empty($request_id)) {
    echo json_encode(["status" => "error", "success" => false, "message" => "Request ID is required."]);
    $conn->close();
    exit();
}

$stmt = $conn->prepare("
    UPDATE vacate_requests 
    SET status = 'rejected',
        rejection_reason = ?,
        processed_by = ?,
        processed_by_name = ?,
        processed_at = NOW(),
        updated_at = NOW()
    WHERE request_id = ? AND status = 'pending'
");

$stmt->bind_param("ssss", $rejection_reason, $warden_username, $warden_name, $request_id);
$stmt->execute();

if ($stmt->affected_rows > 0) {
    // Log to vstudy_webhook_events without sending to VStudy ERP
    try {
        require_once __DIR__ . '/../utils/vstudy_sync_helper.php';
        $vStmt = $conn->prepare("SELECT student_reg_no, room_number, hostel_name FROM vacate_requests WHERE request_id = ? LIMIT 1");
        $vStmt->bind_param("s", $request_id);
        $vStmt->execute();
        $vRow = $vStmt->get_result()->fetch_assoc();
        
        $eventUuid = generateUuidV4();
        $wbPayload = json_encode([
            'eventId'         => $eventUuid,
            'externalEventId' => $eventUuid,
            'eventType'       => 'booking.vacate_rejected',
            'entityType'      => 'HOSTEL_BOOKING',
            'entityId'        => $request_id,
            'occurredAt'      => date('c'),
            'data'            => [
                'requestId'       => $request_id,
                'rollNumber'      => $vRow['student_reg_no'] ?? '',
                'roomNumber'      => $vRow['room_number'] ?? '',
                'hostelName'      => $vRow['hostel_name'] ?? '',
                'rejectionReason' => $rejection_reason,
                'wardenName'      => $warden_name,
                'status'          => 'REJECTED'
            ]
        ]);

        $insWb = $conn->prepare("
            INSERT INTO vstudy_webhook_events (
                event_id, event_type, entity_type, entity_id,
                roll_number, room_number, hostel_name, status,
                occurred_at, payload, response, created_at, updated_at
            ) VALUES (
                ?, 'booking.vacate_rejected', 'HOSTEL_BOOKING', ?,
                ?, ?, ?, 'REJECTED',
                NOW(), ?, ?, NOW(), NOW()
            )
        ");
        $respStr = json_encode(['received' => true, 'status' => 'REJECTED_INTERNAL']);
        $regNo = $vRow['student_reg_no'] ?? '';
        $rNo = $vRow['room_number'] ?? '';
        $hName = $vRow['hostel_name'] ?? '';
        $insWb->bind_param("ssssssss", $eventUuid, $request_id, $regNo, $rNo, $hName, $wbPayload, $respStr);
        $insWb->execute();
    } catch (Exception $eWb) {
        error_log("Failed to log rejected vacate to vstudy_webhook_events: " . $eWb->getMessage());
    }

    echo json_encode([
        "status" => "success",
        "success" => true,
        "message" => "Vacate request has been rejected.",
        "data" => [
            "request_id" => $request_id,
            "rejection_reason" => $rejection_reason,
            "status" => "rejected"
        ]
    ]);
} else {
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => "No pending vacate request found with ID $request_id or it was already processed."
    ]);
}

$conn->close();
?>
