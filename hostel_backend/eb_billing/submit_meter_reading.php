<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/auth_helper.php';

$authUser = requireAuth(['maintenance', 'warden', 'admin', 'super_admin', 'it']);

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $photoUrl = null;
    $uploadDir = __DIR__ . '/../uploads/maintenance_photos/';
    if (!file_exists($uploadDir)) {
        @mkdir($uploadDir, 0777, true);
    }

    // 1. Handle file upload if present
    if (isset($_FILES['photo']) && $_FILES['photo']['error'] === UPLOAD_ERR_OK) {
        $fileTmp = $_FILES['photo']['tmp_name'];
        $fileName = $_FILES['photo']['name'];
        $ext = strtolower(pathinfo($fileName, PATHINFO_EXTENSION));
        $allowed = ['jpg', 'jpeg', 'png', 'webp'];
        if (!in_array($ext, $allowed)) {
            $ext = 'jpg';
        }
        $newFileName = 'eb_meter_' . time() . '_' . rand(1000, 9999) . '.' . $ext;
        $destPath = $uploadDir . $newFileName;
        if (move_uploaded_file($fileTmp, $destPath)) {
            $photoUrl = 'uploads/maintenance_photos/' . $newFileName;
        }
    }

    // 2. Read body inputs (either POST form-data or JSON)
    $input = $_POST;
    if (empty($input)) {
        $raw = file_get_contents('php://input');
        $json = json_decode($raw, true);
        if (is_array($json)) {
            $input = $json;
        }
    }

    // Check base64 photo fallback
    if (empty($photoUrl) && !empty($input['photo_base64'])) {
        $base64 = $input['photo_base64'];
        $allowed = ['jpg', 'jpeg', 'png', 'webp'];
        $ext = 'jpg';
        if (preg_match('/^data:image\/(\w+);base64,/', $base64, $match)) {
            $base64 = substr($base64, strpos($base64, ',') + 1);
            $parsedExt = strtolower($match[1]);
            if (in_array($parsedExt, $allowed)) {
                $ext = $parsedExt;
            }
        }
        $decoded = base64_decode($base64);
        if ($decoded !== false) {
            $newFileName = 'eb_meter_' . time() . '_' . rand(1000, 9999) . '.' . $ext;
            file_put_contents($uploadDir . $newFileName, $decoded);
            $photoUrl = 'uploads/maintenance_photos/' . $newFileName;
        }
    }

    $hostelName = trim($input['hostel_name'] ?? '');
    $buildingCode = trim($input['building_code'] ?? $hostelName);
    $floorNo = trim($input['floor_no'] ?? '');
    $roomNo = trim($input['room_no'] ?? '');
    $meterNo = trim($input['meter_no'] ?? '');
    $previousReading = isset($input['previous_reading']) ? (float)$input['previous_reading'] : 0.00;
    $currentReading = isset($input['current_reading']) ? (float)$input['current_reading'] : 0.00;
    $volts = isset($input['volts']) ? (float)$input['volts'] : 230.00;
    $watts = isset($input['watts']) ? (float)$input['watts'] : 0.00;
    $anomalyTags = trim($input['anomaly_tags'] ?? '');
    $notes = trim($input['notes'] ?? '');
    $recordedBy = trim($input['recorded_by'] ?? 'maintenance');
    $inspectorName = trim($input['inspector_name'] ?? 'Maintenance Staff');

    if (empty($roomNo)) {
        echo json_encode(["status" => "error", "message" => "Room number is required"]);
        exit();
    }

    if ($currentReading < 0) {
        echo json_encode(["status" => "error", "message" => "Current meter reading cannot be negative"]);
        exit();
    }

    $unitsConsumed = max(0.00, round($currentReading - $previousReading, 2));

    // 3. Insert reading record
    $stmt = $db->prepare("
        INSERT INTO eb_meter_readings (
            hostel_name, building_code, floor_no, room_no, meter_no,
            previous_reading, current_reading, units_consumed, volts, watts,
            photo_url, anomaly_tags, notes, recorded_by, inspector_name, status
        ) VALUES (
            ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, 'pending'
        )
    ");

    $stmt->execute([
        $hostelName,
        $buildingCode,
        $floorNo,
        $roomNo,
        $meterNo,
        $previousReading,
        $currentReading,
        $unitsConsumed,
        $volts,
        $watts,
        $photoUrl,
        $anomalyTags,
        $notes,
        $recordedBy,
        $inspectorName
    ]);

    $insertId = $db->lastInsertId();

    // 4. Automatically sync reading record to vStudy & log to vstay_webhook_events
    $vstudySynced = false;
    $vstudyResponse = null;
    $readingDate = date('Y-m-d H:i:s');
    $externalEventId = function_exists('generateUuidV4') ? generateUuidV4() : sprintf('%04x%04x-%04x-%04x-%04x-%04x%04x%04x', mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0x0fff) | 0x4000, mt_rand(0, 0x3fff) | 0x8000, mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff));

    $roomRecord = [
        'roomNumber'    => $roomNo,
        'hostelName'    => $hostelName,
        'floorName'     => $floorNo,
        'meterNo'       => !empty($meterNo) ? $meterNo : 'MTR-' . $roomNo,
        'unitsConsumed' => (float)$unitsConsumed,
        'readingDate'   => $readingDate,
        'recordedBy'    => $recordedBy,
        'inspectorName' => $inspectorName
    ];

    try {
        require_once __DIR__ . '/../config/api_config.php';
        require_once __DIR__ . '/../utils/vstudy_sync_helper.php';

        $vstudyUrl = defined('VSTUDY_EB_SYNC_API_URL') ? VSTUDY_EB_SYNC_API_URL : 'https://vstudy.saveetha.com/api/hostel-applications/external/eb-meter-readings';
        $clientId = defined('VSTUDY_CLIENT_ID') ? VSTUDY_CLIENT_ID : '';
        $clientSecret = defined('VSTUDY_CLIENT_SECRET') ? VSTUDY_CLIENT_SECRET : '';

        $vstudyPayload = [
            'externalEventId' => $externalEventId,
            'eventType'       => 'electricity.meter_reading_single',
            'month'           => date('Y-m'),
            'record'          => $roomRecord
        ];

        $httpCode = 0;
        if (!empty($clientId) && !empty($clientSecret)) {
            $ch = curl_init($vstudyUrl);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($vstudyPayload));
            curl_setopt($ch, CURLOPT_HTTPHEADER, [
                'Content-Type: application/json',
                'x-client-id: ' . $clientId,
                'x-client-secret: ' . $clientSecret
            ]);
            curl_setopt($ch, CURLOPT_TIMEOUT, 10);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
            $res = curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);

            $vstudyResponse = json_decode($res, true) ?: $res;
            $vstudySynced = ($httpCode === 200 || $httpCode === 201);
        }

        // Always log to vstay_webhook_events
        ensureVstayWebhookEventsTable($db);
        $stmtIns = $db->prepare("
            INSERT INTO vstay_webhook_events (
                event_id, event_type, entity_type, entity_id,
                roll_number, room_number, hostel_name, direction, status,
                occurred_at, payload, response
            ) VALUES (
                ?, 'electricity.meter_reading_single', 'HOSTEL_EB_READINGS', ?,
                ?, ?, ?, 'OUTBOUND', ?,
                NOW(), ?, ?
            )
        ");
        $stmtIns->execute([
            $externalEventId,
            $roomNo,
            $recordedBy,
            $roomNo,
            $hostelName,
            $vstudySynced ? 'PROCESSED' : 'SENT',
            json_encode($roomRecord),
            json_encode(['http_code' => $httpCode, 'vstudy_response' => $vstudyResponse])
        ]);
    } catch (Exception $syncEx) {
        error_log("EB single room sync error: " . $syncEx->getMessage());
    }

    echo json_encode([
        "status" => "success",
        "message" => "EB meter reading submitted and synced to vStudy successfully",
        "data" => [
            "id" => (int)$insertId,
            "room_no" => $roomNo,
            "units_consumed" => $unitsConsumed,
            "volts" => $volts,
            "watts" => $watts,
            "photo_url" => $photoUrl,
            "status" => "verified",
            "vstudy_record" => $roomRecord,
            "vstudy_synced" => $vstudySynced
        ]
    ]);
} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "message" => $e->getMessage()
    ]);
}
