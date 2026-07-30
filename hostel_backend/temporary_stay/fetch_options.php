<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

// Auto-create table if not exists
$createSql = "CREATE TABLE IF NOT EXISTS temporary_stay_requests (
    id INT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(64) NOT NULL UNIQUE,
    full_name VARCHAR(191) NOT NULL,
    email VARCHAR(191) NOT NULL,
    phone VARCHAR(32) NOT NULL,
    gender VARCHAR(16) NOT NULL,
    institution_purpose TEXT NOT NULL,
    doc_type VARCHAR(64) NOT NULL,
    doc_number VARCHAR(128) NOT NULL,
    hostel_name VARCHAR(191) NOT NULL,
    room_type VARCHAR(191) NOT NULL,
    room_no VARCHAR(64) NOT NULL,
    room_id INT DEFAULT 0,
    from_date DATE NOT NULL,
    to_date DATE NOT NULL,
    duration_type VARCHAR(16) NOT NULL DEFAULT 'days',
    duration_value INT NOT NULL DEFAULT 1,
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    admin_notes TEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_status (status),
    INDEX idx_email (email),
    INDEX idx_gender (gender)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;";
$db->exec($createSql);

$gender = isset($_GET['gender']) ? trim($_GET['gender']) : '';
$hostel_name = isset($_GET['hostel_name']) ? trim($_GET['hostel_name']) : '';
$room_type = isset($_GET['room_type']) ? trim($_GET['room_type']) : '';

$hostel_type = (stripos($gender, 'female') !== false || stripos($gender, 'girls') !== false) ? 'Girls' : 'Boys';

try {
    // 1. Fetch Hostels for this Gender
    $stmtHostels = $db->prepare("SELECT DISTINCT hostel_name FROM hostel_rooms WHERE hostel_type = ? AND available_rooms > 0 ORDER BY hostel_name ASC");
    $stmtHostels->execute([$hostel_type]);
    $hostels = $stmtHostels->fetchAll(PDO::FETCH_COLUMN);

    if (empty($hostels)) {
        // Fallback default hostels by gender if table not populated
        if ($hostel_type === 'Girls') {
            $hostels = ['Vaigai Hostel', 'Ponni Hostel'];
        } else {
            $hostels = ['Krishna Hostel', 'Noyyal Hostel', 'Palar Hostel'];
        }
    }

    $room_types = [];
    if (!empty($hostel_name)) {
        $stmtTypes = $db->prepare("SELECT DISTINCT room_type FROM hostel_rooms WHERE hostel_name = ? AND hostel_type = ? AND available_rooms > 0 ORDER BY room_type ASC");
        $stmtTypes->execute([$hostel_name, $hostel_type]);
        $room_types = $stmtTypes->fetchAll(PDO::FETCH_COLUMN);
    }

    $available_rooms = [];
    if (!empty($hostel_name) && !empty($room_type)) {
        $stmtRooms = $db->prepare("SELECT id, room_no, building_code, floor, room_type, facility, available_rooms, total_capacity, room_code, wing_code, floor_code FROM hostel_rooms WHERE hostel_name = ? AND room_type = ? AND hostel_type = ? AND available_rooms > 0 ORDER BY room_code ASC, room_no ASC");
        $stmtRooms->execute([$hostel_name, $room_type, $hostel_type]);
        $rows = $stmtRooms->fetchAll(PDO::FETCH_ASSOC);

        foreach ($rows as $row) {
            $fullCode = !empty($row['room_code']) ? $row['room_code'] : trim(($row['building_code'] ?? '') . '-' . ($row['floor_code'] ?? '') . '-' . ($row['wing_code'] ?? '') . '-' . ($row['room_no'] ?? ''), '-');
            if (empty($fullCode)) {
                $fullCode = "Room " . $row['room_no'];
            }

            $vacCount = (int)$row['available_rooms'];
            $bedLabel = ($vacCount === 1) ? "1 bed available" : "$vacCount beds available";

            $available_rooms[] = [
                "id" => (int)$row['id'],
                "room_no" => $row['room_no'],
                "room_code" => $fullCode,
                "floor" => $row['floor'],
                "building_code" => $row['building_code'],
                "vacancies" => $vacCount,
                "capacity" => (int)$row['total_capacity'],
                "display_label" => $fullCode . " (" . $bedLabel . ")"
            ];
        }
    }

    echo json_encode([
        "success" => true,
        "gender" => $gender,
        "hostel_type" => $hostel_type,
        "hostels" => $hostels,
        "room_types" => $room_types,
        "rooms" => $available_rooms
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Error fetching options: " . $e->getMessage()
    ]);
}
?>
