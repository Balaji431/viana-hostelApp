<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if (($_SERVER['REQUEST_METHOD'] ?? '') == 'OPTIONS') {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

if (!$pdo) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

$hostel_id = isset($_GET['hostel_id']) ? trim($_GET['hostel_id']) : null;
$hostel_name = isset($_GET['hostel_name']) ? trim($_GET['hostel_name']) : null;
$query_param = !empty($hostel_name) ? $hostel_name : $hostel_id;

if (!$query_param) {
    echo json_encode(["success" => false, "message" => "Hostel ID or Name is required"]);
    exit();
}

try {
    // 1. Get Hostel Info
    $hostelName = $query_param;
    $buildingCode = '';
    $hostelType = 'Boys';
    $campus = 'Thandalam Campus';

    $stmt = $pdo->prepare("SELECT * FROM hostel_type WHERE id = ? OR TRIM(hostel_name) = TRIM(?) OR TRIM(hostel_name) LIKE CONCAT('%', TRIM(?), '%') LIMIT 1");
    $stmt->execute([$query_param, $query_param, $query_param]);
    $hostel = $stmt->fetch(PDO::FETCH_ASSOC);

    if ($hostel) {
        $hostelName = $hostel['hostel_name'];
        $buildingCode = $hostel['building_code'] ?? '';
        $hostelType = $hostel['hostel_type'] ?? 'Boys';
        $campus = $hostel['campus'] ?? 'Thandalam Campus';
    }

    // 2. Get all rooms for this hostel from rooms_groups_details
    $stmt = $pdo->prepare("
        SELECT rgd.s_no as id,
               rgd.room_number as room_no,
               rgd.room_number as room_code,
               rgd.group_name as floor,
               'General' as wing_code,
               rgd.total_beds as total_capacity,
               rgd.occupied_beds as occupied_rooms,
               rgd.available_beds as available_rooms,
               rgd.available_beds as real_available,
               0 as res_count,
               rgd.room_type,
               CASE 
                   WHEN LOWER(rgd.room_type) LIKE '%non%ac%' OR LOWER(rgd.room_type) LIKE '%non-ac%' THEN 'Non AC' 
                   WHEN LOWER(rgd.room_type) LIKE '%ac%' THEN 'AC' 
                   ELSE 'Standard' 
               END as facility,
               rgd.amount,
               rgd.reserved_for,
               rgd.reserved_for_roles
        FROM rooms_groups_details rgd
        WHERE TRIM(rgd.hostel_name) = TRIM(?) OR TRIM(rgd.hostel_name) LIKE CONCAT('%', TRIM(?), '%')
        ORDER BY rgd.group_name, rgd.room_number
    ");
    $stmt->execute([$hostelName, $hostelName]);
    $rooms = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // 3. Build hierarchy: Floor -> Wing -> Room
    $hierarchy = [];
    $floors_grouped = [];

    // Helper to clean floor names
    $cleanFloor = function($rawFloor, $hName) {
        $clean = preg_replace('/^' . preg_quote($hName, '/') . '\s*/i', '', $rawFloor);
        $clean = preg_replace('/^\(New\)\s*/i', '', $clean);
        return trim($clean) ?: $rawFloor;
    };

    // Helper for ordinal floor sorting weight
    $floorWeight = function($floorName) {
        $f = strtolower($floorName);
        if (strpos($f, 'ground') !== false) return 0;
        if (strpos($f, 'first') !== false || strpos($f, '1st') !== false) return 1;
        if (strpos($f, 'second') !== false || strpos($f, '2nd') !== false) return 2;
        if (strpos($f, 'third') !== false || strpos($f, '3rd') !== false) return 3;
        if (strpos($f, 'fourth') !== false || strpos($f, '4th') !== false) return 4;
        if (strpos($f, 'fifth') !== false || strpos($f, '5th') !== false) return 5;
        if (strpos($f, 'sixth') !== false || strpos($f, '6th') !== false) return 6;
        if (strpos($f, 'seventh') !== false || strpos($f, '7th') !== false) return 7;
        if (strpos($f, 'eighth') !== false || strpos($f, '8th') !== false) return 8;
        if (strpos($f, 'ninth') !== false || strpos($f, '9th') !== false) return 9;
        if (strpos($f, 'tenth') !== false || strpos($f, '10th') !== false) return 10;
        return 99;
    };

    foreach ($rooms as $room) {
        $rawFloorName = $room['floor'] ?: 'Ground';
        $floorName = $cleanFloor($rawFloorName, $hostelName);
        $wingName = $room['wing_code'] ?: 'General';

        if (!isset($floors_grouped[$floorName])) {
            $floors_grouped[$floorName] = [
                "name" => $floorName,
                "code" => $floorName,
                "floors" => []
            ];
        }

        if (!isset($floors_grouped[$floorName]['floors'][$wingName])) {
            $floors_grouped[$floorName]['floors'][$wingName] = [
                "name" => $wingName,
                "code" => $wingName,
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
            "reserved_count" => 0,
            "type" => $room['room_type'],
            "room_type" => $room['room_type'],
            "facility" => $room['facility'],
            "amount" => $room['amount'],
            "reserved_for" => $room['reserved_for'] ? json_decode($room['reserved_for'], true) : null,
            "reserved_for_roles" => $room['reserved_for_roles'] ? json_decode($room['reserved_for_roles'], true) : null
        ];
    }

    // Convert associative arrays to indexed arrays for JSON and sort by floor order
    $finalFloors = [];
    foreach ($floors_grouped as $fName => $fData) {
        $finalWings = [];
        foreach ($fData['floors'] as $wName => $wData) {
            $finalWings[] = $wData;
        }
        $fData['floors'] = $finalWings; // Sub-level is now Wings
        $finalFloors[] = $fData; // Top-level is now Floors
    }

    usort($finalFloors, function($a, $b) use ($floorWeight) {
        return $floorWeight($a['name']) <=> $floorWeight($b['name']);
    });

    echo json_encode([
        "success" => true,
        "data" => [
            "id" => $hostel['id'],
            "name" => $hostel['hostel_name'],
            "campus" => $hostel['campus'],
            "type" => $hostel['hostel_type'],
            "building_code" => $hostel['building_code'],
            "wings" => $finalFloors
        ]
    ]);

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
}
?>
