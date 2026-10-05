<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json; charset=UTF-8");

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $roomNo = isset($_GET['room_no']) ? trim($_GET['room_no']) : '';
    $hostelName = isset($_GET['hostel_name']) ? trim($_GET['hostel_name']) : '';

    if (empty($roomNo)) {
        echo json_encode([
            "status" => "error",
            "message" => "Room number is required"
        ]);
        exit();
    }

    // 1. Get previous reading & meter number
    $readingStmt = $db->prepare("
        SELECT id, current_reading, meter_no, created_at, volts, watts, status 
        FROM eb_meter_readings 
        WHERE room_no = ? " . (!empty($hostelName) ? "AND hostel_name = ? " : "") . "
        ORDER BY id DESC 
        LIMIT 1
    ");
    $params = [$roomNo];
    if (!empty($hostelName)) {
        $params[] = $hostelName;
    }
    $readingStmt->execute($params);
    $lastReading = $readingStmt->fetch(PDO::FETCH_ASSOC);

    $previousReading = $lastReading ? (float)$lastReading['current_reading'] : 0.0;
    $meterNo = $lastReading ? ($lastReading['meter_no'] ?? '') : '';
    $lastReadingDate = $lastReading ? $lastReading['created_at'] : null;

    // 2. Get room details from room_master
    $roomStmt = $db->prepare("
        SELECT id, location_name, building_code, floor_no, room_no, room_type, total_beds, occupied_beds 
        FROM room_master 
        WHERE room_no = ? " . (!empty($hostelName) ? "AND (building_code = ? OR location_name = ?)" : "") . "
        LIMIT 1
    ");
    $roomParams = [$roomNo];
    if (!empty($hostelName)) {
        $roomParams[] = $hostelName;
        $roomParams[] = $hostelName;
    }
    $roomStmt->execute($roomParams);
    $roomInfo = $roomStmt->fetch(PDO::FETCH_ASSOC);

    // 3. Get students allocated to this room
    $studentStmt = $db->prepare("
        SELECT DISTINCT p.reg_no, p.full_name, p.phone, p.email, p.hostel_name 
        FROM profile p
        WHERE p.room_allocation = ? OR p.room_allocation LIKE ?
    ");
    $studentStmt->execute([$roomNo, "%$roomNo%"]);
    $occupants = $studentStmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "status" => "success",
        "data" => [
            "room_no" => $roomNo,
            "hostel_name" => $roomInfo['building_code'] ?? $hostelName,
            "floor_no" => $roomInfo['floor_no'] ?? '',
            "meter_no" => $meterNo,
            "previous_reading" => $previousReading,
            "last_reading_date" => $lastReadingDate,
            "occupants" => $occupants,
            "occupant_count" => count($occupants),
            "room_details" => $roomInfo ?: null
        ]
    ]);
} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "message" => $e->getMessage()
    ]);
}
