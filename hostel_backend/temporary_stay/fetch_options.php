<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
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
    doc_file_path TEXT NULL,
    hostel_name VARCHAR(191) NOT NULL,
    room_type VARCHAR(191) NOT NULL,
    room_no VARCHAR(64) NOT NULL,
    room_code VARCHAR(191) NULL,
    room_id INT DEFAULT 0,
    from_date DATE NOT NULL,
    to_date DATE NOT NULL,
    duration_type VARCHAR(16) NOT NULL DEFAULT 'days',
    duration_value INT NOT NULL DEFAULT 1,
    amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    annual_fee DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    payment_status VARCHAR(32) NOT NULL DEFAULT 'unpaid',
    payment_txn_id VARCHAR(128) NULL,
    fcm_token TEXT NULL,
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

$isFemale = (stripos($gender, 'female') !== false || stripos($gender, 'girls') !== false);
$hostel_type = $isFemale ? 'Girls' : 'Boys';

try {
    // 1. Fetch Hostels for this Gender from rooms_groups_details
    if ($isFemale) {
        $stmtHostels = $db->prepare("
            SELECT DISTINCT hostel_name 
            FROM rooms_groups_details 
            WHERE (LOWER(gender) = 'female' OR LOWER(gender) = 'girls' OR LOWER(hostel_name) LIKE '%girls%' OR LOWER(hostel_name) LIKE '%ponni%' OR LOWER(hostel_name) LIKE '%vaigai%' OR LOWER(hostel_name) LIKE '%siruvani%' OR LOWER(hostel_name) LIKE '%porunai%') 
              AND available_beds > 0 
            ORDER BY hostel_name ASC
        ");
    } else {
        $stmtHostels = $db->prepare("
            SELECT DISTINCT hostel_name 
            FROM rooms_groups_details 
            WHERE (LOWER(gender) = 'male' OR LOWER(gender) = 'boys' OR LOWER(hostel_name) LIKE '%boys%' OR LOWER(hostel_name) LIKE '%krishna%' OR LOWER(hostel_name) LIKE '%noyyal%' OR LOWER(hostel_name) LIKE '%palar%' OR LOWER(hostel_name) LIKE '%kaveri%') 
              AND available_beds > 0 
            ORDER BY hostel_name ASC
        ");
    }
    $stmtHostels->execute();
    $hostels = $stmtHostels->fetchAll(PDO::FETCH_COLUMN);

    if (empty($hostels)) {
        if ($isFemale) {
            $hostels = ['Vaigai Hostel', 'Ponni Hostel', 'Siruvani Hostel'];
        } else {
            $hostels = ['Krishna Hostel', 'Noyyal Hostel', 'Palar Hostel', 'Kaveri Hostel'];
        }
    }

    $room_types = [];
    if (!empty($hostel_name)) {
        $stmtTypes = $db->prepare("
            SELECT DISTINCT room_type 
            FROM rooms_groups_details 
            WHERE hostel_name = ? AND available_beds > 0 
            ORDER BY room_type ASC
        ");
        $stmtTypes->execute([$hostel_name]);
        $room_types = $stmtTypes->fetchAll(PDO::FETCH_COLUMN);
    }

    $available_rooms = [];
    if (!empty($hostel_name) && !empty($room_type)) {
        $stmtRooms = $db->prepare("
            SELECT s_no as id, room_number as room_no, room_number as room_code, group_name as floor, room_type, available_beds, total_beds, amount, warden_name, warden_user_id, warden_bio_id
            FROM rooms_groups_details 
            WHERE hostel_name = ? AND room_type = ? AND available_beds > 0 
            ORDER BY room_number ASC
        ");
        $stmtRooms->execute([$hostel_name, $room_type]);
        $rows = $stmtRooms->fetchAll(PDO::FETCH_ASSOC);

        foreach ($rows as $row) {
            $fullCode = !empty($row['room_code']) ? $row['room_code'] : ("Room " . $row['room_no']);
            
            // Calculate active temporary requests and held rooms (block for 24h or while pending/allocated)
            $stmtActiveReq = $db->prepare("
                SELECT COUNT(*) as active_count 
                FROM temporary_stay_requests 
                WHERE (room_no = ? OR room_code = ? OR REPLACE(REPLACE(room_no, ' ', ''), '-', '') = REPLACE(REPLACE(?, ' ', ''), '-', ''))
                  AND (
                      status = 'allocated' 
                      OR status = 'pending'
                      OR (status = 'approved' AND (hold_expires_at IS NULL OR hold_expires_at > NOW()))
                  )
            ");
            $stmtActiveReq->execute([$row['room_no'], $row['room_code'], $row['room_no']]);
            $activeReqCount = (int)($stmtActiveReq->fetchColumn() ?: 0);

            $vacCount = max(0, (int)$row['available_beds'] - $activeReqCount);

            // If no beds available in this room after deducting pending/approved/allocated stays, do not show it!
            if ($vacCount <= 0) {
                continue;
            }

            $bedLabel = ($vacCount === 1) ? "1 bed available" : "$vacCount beds available";

            $wName = $row['warden_name'] ?? '';
            if (empty($wName)) {
                try {
                    $stmtMW = $db->prepare("SELECT name FROM mapping_staff WHERE LOWER(role) LIKE '%warden%' AND (LOWER(hostel_name) LIKE LOWER(?) OR LOWER(?) LIKE LOWER(CONCAT('%', hostel_name, '%'))) LIMIT 1");
                    $stmtMW->execute(["%$hostel_name%", $hostel_name]);
                    $mwRow = $stmtMW->fetch(PDO::FETCH_ASSOC);
                    if ($mwRow) $wName = $mwRow['name'];
                } catch (Exception $eW) {}
            }

            // Calculate Per-Night Pricing (rounded to nearest 50)
            $annual = (float)($row['amount'] ?? 0);
            if ($annual <= 0) {
                try {
                    $stmtF = $db->prepare("SELECT total_fee, hostel_fee FROM hostel_renew_fee WHERE LOWER(room_type) = LOWER(?) LIMIT 1");
                    $stmtF->execute([trim($room_type)]);
                    $fRow = $stmtF->fetch(PDO::FETCH_ASSOC);
                    if ($fRow && !empty($fRow['total_fee']) && (float)$fRow['total_fee'] > 0) {
                        $annual = (float)$fRow['total_fee'];
                    } else if ($fRow && !empty($fRow['hostel_fee']) && (float)$fRow['hostel_fee'] > 0) {
                        $annual = (float)$fRow['hostel_fee'];
                    }
                } catch (Exception $eF) {}
            }
            if ($annual <= 0) {
                $rtLower = strtolower($room_type);
                if (strpos($rtLower, 'single') !== false && strpos($rtLower, 'ac') !== false) {
                    $annual = 150000;
                } else if (strpos($rtLower, 'single') !== false) {
                    $annual = 55000;
                } else if (strpos($rtLower, '2 in 1') !== false || strpos($rtLower, 'double') !== false) {
                    $annual = (strpos($rtLower, 'ac') !== false) ? 100000 : 55000;
                } else if (strpos($rtLower, '3 in 1') !== false || strpos($rtLower, 'triple') !== false) {
                    $annual = (strpos($rtLower, 'ac') !== false) ? 80000 : 55000;
                } else if (strpos($rtLower, '4 in 1') !== false) {
                    $annual = (strpos($rtLower, 'ac') !== false) ? 70000 : 50000;
                } else if (strpos($rtLower, 'dorm') !== false) {
                    $annual = 36500;
                } else {
                    $annual = 75000;
                }
            }

            $rawPerNight = $annual / 365.0;
            // Round to nearest 50 (e.g. 150.68 -> 150, 410.95 -> 400 or 450)
            $roundedPerNight = round($rawPerNight / 50.0) * 50.0;
            if ($roundedPerNight < 50) $roundedPerNight = 50.0;

            $available_rooms[] = [
                "id" => (int)$row['id'],
                "room_no" => $row['room_no'],
                "room_code" => $fullCode,
                "floor" => $row['floor'] ?? '',
                "building_code" => '',
                "vacancies" => $vacCount,
                "capacity" => (int)($row['total_beds'] ?? 1),
                "warden_name" => $wName,
                "warden_id" => $row['warden_user_id'] ?? '',
                "warden_bio_id" => $row['warden_bio_id'] ?? '',
                "price_per_night" => (int)$roundedPerNight,
                "annual_fee" => (float)$annual,
                "display_label" => $fullCode . " (" . $bedLabel . ") · ₹" . (int)$roundedPerNight . "/night"
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
