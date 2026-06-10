<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

if (!$pdo) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

$hostel_id = isset($_GET['hostel_id']) ? $_GET['hostel_id'] : null;

if (!$hostel_id) {
    echo json_encode(["success" => false, "message" => "Hostel ID is required"]);
    exit();
}

try {
    // 1. Get Hostel Info
    $stmt = $pdo->prepare("SELECT * FROM hostel_type WHERE id = ?");
    $stmt->execute([$hostel_id]);
    $hostel = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$hostel) {
        echo json_encode(["success" => false, "message" => "Hostel not found"]);
        exit();
    }

    // 2. Get all rooms for this hostel with active reservation counts
    $stmt = $pdo->prepare("
        SELECT hr.*, 
               (hr.available_rooms - COALESCE(res.res_count, 0)) as real_available,
               COALESCE(res.res_count, 0) as res_count
        FROM hostel_rooms hr
        LEFT JOIN (
            SELECT TRIM(requested_room) as requested_room, COUNT(*) as res_count 
            FROM room_change_requests 
            WHERE status IN ('pre_approved', 'approved') 
            AND payment_status = 'unpaid'
            AND reserved_until > NOW()
            AND requested_room IS NOT NULL 
            AND requested_room != ''
            GROUP BY TRIM(requested_room)
        ) res ON TRIM(hr.room_code) = res.requested_room
        WHERE hr.hostel_id = ? 
        ORDER BY hr.wing_code, hr.floor_code, hr.room_no
    ");
    $stmt->execute([$hostel_id]);
    $rooms = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // 3. Build hierarchy: Floor -> Wing -> Room
    $hierarchy = [];
    $floors_grouped = [];

    foreach ($rooms as $room) {
        $floorName = $room['floor'] ?: 'Ground';
        $wingName = $room['wing_code'] ?: 'General';

        if (!isset($floors_grouped[$floorName])) {
            $floors_grouped[$floorName] = [
                "name" => $floorName,
                "code" => $room['floor_code'] ?: $floorName,
                "floors" => [] // We use "floors" key here because the provider expects it for sub-level
            ];
        }

        if (!isset($floors_grouped[$floorName]['floors'][$wingName])) {
            $floors_grouped[$floorName]['floors'][$wingName] = [
                "name" => $wingName,
                "code" => $room['wing_code'] ?: $wingName,
                "rooms" => []
            ];
        }

        $floors_grouped[$floorName]['floors'][$wingName]['rooms'][] = [
            "id" => $room['id'],
            "room_no" => $room['room_no'],
            "room_code" => $room['room_code'],
            "capacity" => $room['total_capacity'],
            "available" => max(0, (int)$room['real_available']),
            "physical_available" => (int)$room['available_rooms'],
            "reserved_count" => (int)($room['res_count'] ?? 0),
            "type" => $room['room_type'],
            "facility" => $room['facility'],
            "amount" => $room['amount']
        ];
    }

    // Convert associative arrays to indexed arrays for JSON
    $finalFloors = [];
    foreach ($floors_grouped as $fName => $fData) {
        $finalWings = [];
        foreach ($fData['floors'] as $wName => $wData) {
            $finalWings[] = $wData;
        }
        $fData['floors'] = $finalWings; // Sub-level is now Wings
        $finalFloors[] = $fData; // Top-level is now Floors
    }

    echo json_encode([
        "success" => true,
        "data" => [
            "id" => $hostel['id'],
            "name" => $hostel['hostel_name'],
            "campus" => $hostel['campus'],
            "type" => $hostel['hostel_type'],
            "building_code" => $hostel['building_code'],
            "wings" => $finalFloors // We still call it "wings" for compatibility with existing provider logic
        ]
    ]);

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
}
?>
