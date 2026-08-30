<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json");

// Allow short-lived caching for near-static room data (30 seconds)
header("Cache-Control: public, max-age=30, stale-while-revalidate=60");
header("Vary: Accept-Encoding");

// Enable gzip output compression on the PHP level for large payloads
if (extension_loaded('zlib') && !ob_get_level()) {
    ob_start('ob_gzhandler');
}

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once '../config/database.php';

// ── Session-based micro-cache (60 seconds) for the student map ──
if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

try {
    $database = new Database();
    $db = $database->getConnection();

    $locationFilter = isset($_GET['location_name']) ? trim($_GET['location_name']) : '';
    $buildingFilter = isset($_GET['building_code'])  ? trim($_GET['building_code'])  : '';
    $floorFilter    = isset($_GET['floor_no'])        ? trim($_GET['floor_no'])        : '';
    $roomTypeFilter = isset($_GET['room_type'])       ? trim($_GET['room_type'])       : '';
    $searchFilter   = isset($_GET['search'])          ? trim($_GET['search'])          : '';

    // Pagination — default: page=1, limit=100 for fast initial load
    // Pass page=0 to get ALL rows (used by Export Excel endpoint)
    $page     = isset($_GET['page'])  ? max(0, (int)$_GET['page'])  : 1;
    $per_page = isset($_GET['limit']) ? max(1, (int)$_GET['limit']) : 100;

    // ── Build WHERE clause ──────────────────────────────────────────────────
    $whereParts = [];
    $params     = [];

    if ($locationFilter !== '') {
        $whereParts[] = "location_name = ?";
        $params[]     = $locationFilter;
    }
    if ($buildingFilter !== '') {
        $whereParts[] = "building_code = ?";
        $params[]     = $buildingFilter;
    }
    if ($floorFilter !== '') {
        $whereParts[] = "floor_no = ?";
        $params[]     = $floorFilter;
    }
    if ($roomTypeFilter !== '') {
        $whereParts[] = "room_type = ?";
        $params[]     = $roomTypeFilter;
    }
    if ($searchFilter !== '') {
        $whereParts[] = "(room_no LIKE ? OR location_name LIKE ? OR building_code LIKE ? OR room_code LIKE ?)";
        $likeParam    = "%$searchFilter%";
        $params[]     = $likeParam;
        $params[]     = $likeParam;
        $params[]     = $likeParam;
        $params[]     = $likeParam;
    }

    $whereSQL = count($whereParts) > 0 ? "WHERE " . implode(" AND ", $whereParts) : "";

    // ── Count total matching rows ───────────────────────────────────────────
    $countStmt = $db->prepare("SELECT COUNT(*) as total FROM room_master $whereSQL");
    $countStmt->execute($params);
    $totalRows = (int)($countStmt->fetch(PDO::FETCH_ASSOC)['total'] ?? 0);

    // ── Fetch paginated room rows ───────────────────────────────────────────
    $sql = "SELECT id, location_name, building_code, floor_no, block_no, room_no,
                   room_code, room_type, occupancy, room_capacity, total_beds, occupied_beds,
                   assigned_pending, available_beds, gender, active, amount
            FROM room_master
            $whereSQL
            ORDER BY id ASC";

    if ($page > 0) {
        $offset  = ($page - 1) * $per_page;
        $sql    .= " LIMIT $per_page OFFSET $offset";
    }

    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $rooms = $stmt->fetchAll(PDO::FETCH_ASSOC);

    if (empty($rooms)) {
        echo json_encode([
            "status"      => "success",
            "success"     => true,
            "data"        => [],
            "count"       => 0,
            "total"       => $totalRows,
            "page"        => $page,
            "per_page"    => $per_page,
            "total_pages" => $page > 0 ? (int)ceil($totalRows / $per_page) : 1,
        ]);
        exit;
    }

    // ── Helper to normalize room keys for fuzzy matching ────────────────────
    $normKey = function($str) {
        if (empty($str)) return '';
        $s = strtoupper(trim($str));
        // W-O / W_O before digits → W0 (e.g. WO1 → W01)
        $s = preg_replace('/W[-_\s]*O(?=\d)/', 'W0', $s);
        // Strip bed/slot suffixes at end
        $s = preg_replace('/[-_\s]+(BED|B|SLOT)?\s*\d+$/i', '', $s);
        // Remove all non-alphanumeric
        $s = preg_replace('/[^A-Z0-9]/', '', $s);
        // Normalize wing codes: WA0 → WA, WB0 → WB, WC0 → WC (trailing zero after letter)
        $s = preg_replace('/W([A-Z])0(?=R|$)/', 'W$1', $s);
        return $s;
    };

    // ── Student map: use session cache (60s) to avoid repeating queries ─────
    $cacheKey        = 'student_map_v4';
    $cacheExpireKey  = 'student_map_expire_v4';
    $cacheValid      = isset($_SESSION[$cacheKey]) &&
                       isset($_SESSION[$cacheExpireKey]) &&
                       time() < $_SESSION[$cacheExpireKey];

    if ($cacheValid) {
        $roomIdMap  = $_SESSION['room_id_map_v4'] ?? [];
        $studentMap = $_SESSION[$cacheKey];
    } else {
        $studentMap = [];
        $roomIdMap  = [];

        $addRoll = function(&$sMap, &$rMap, $roll, $code, $rid = null) use ($normKey) {
            $r = trim($roll ?? '');
            if (empty($r)) return;
            if (!empty($rid) && (int)$rid > 0) {
                $rMap[(int)$rid][$r] = true;
            }
            if (!empty($code)) {
                $k = $normKey($code);
                if ($k !== '') {
                    $sMap[$k][$r] = true;
                }
            }
        };

        // 0. Query users table directly (RoomId)
        try {
            $stmt0 = $db->query("SELECT username as roll_no, RoomId as room_code FROM users WHERE role = 'student' AND RoomId IS NOT NULL AND RoomId != '' AND RoomId != '0'");
            if ($stmt0) {
                while ($row = $stmt0->fetch(PDO::FETCH_ASSOC)) {
                    $addRoll($studentMap, $roomIdMap, $row['roll_no'], $row['room_code']);
                }
            }
        } catch (Exception $e) {}

        // 1. Query profile table
        try {
            $stmt1 = $db->query("SELECT COALESCE(NULLIF(u.username,''), p.reg_no) as roll_no, p.room_allocation, p.current_room_id FROM profile p LEFT JOIN users u ON p.user_id = u.id WHERE (p.room_allocation IS NOT NULL AND p.room_allocation != '') OR (p.current_room_id IS NOT NULL AND p.current_room_id > 0)");
            if ($stmt1) {
                while ($row = $stmt1->fetch(PDO::FETCH_ASSOC)) {
                    $addRoll($studentMap, $roomIdMap, $row['roll_no'], $row['room_allocation'], $row['current_room_id']);
                }
            }
        } catch (Exception $e) {}

        // 2. Query allocation_requests table
        try {
            $stmt2 = $db->query("SELECT COALESCE(NULLIF(p.reg_no,''), u.username, ar.student_reg_no) as roll_no, ar.selected_room_number, ar.selected_room_id FROM allocation_requests ar JOIN users u ON ar.student_id = u.id LEFT JOIN profile p ON u.id = p.user_id WHERE ar.status IN ('approved','confirmed','payment_pending','allocated')");
            if ($stmt2) {
                while ($row = $stmt2->fetch(PDO::FETCH_ASSOC)) {
                    $addRoll($studentMap, $roomIdMap, $row['roll_no'], $row['selected_room_number'], $row['selected_room_id']);
                }
            }
        } catch (Exception $e) {}

        // 3. Query room_change_requests table
        try {
            $stmt3 = $db->query("SELECT COALESCE(NULLIF(p.reg_no,''), u.username, rcr.student_reg_no) as roll_no, rcr.requested_room, rcr.current_room FROM room_change_requests rcr JOIN users u ON rcr.student_id = u.id LEFT JOIN profile p ON u.id = p.user_id WHERE rcr.status IN ('approved','completed','pre_approved')");
            if ($stmt3) {
                while ($row = $stmt3->fetch(PDO::FETCH_ASSOC)) {
                    $addRoll($studentMap, $roomIdMap, $row['roll_no'], $row['requested_room'] ?: $row['current_room']);
                }
            }
        } catch (Exception $e) {}

        // 4. Query vstudy_payments table (contains all booked rooms)
        try {
            $stmt4 = $db->query("SELECT roll_number as roll_no, room_number FROM vstudy_payments WHERE room_number IS NOT NULL AND room_number != ''");
            if ($stmt4) {
                while ($row = $stmt4->fetch(PDO::FETCH_ASSOC)) {
                    $addRoll($studentMap, $roomIdMap, $row['roll_no'], $row['room_number']);
                }
            }
        } catch (Exception $e) {}

        // Convert key-based dedup maps to plain arrays
        foreach ($roomIdMap  as $k => $v) $roomIdMap[$k]  = array_keys($v);
        foreach ($studentMap as $k => $v) $studentMap[$k] = array_keys($v);

        // Cache in session for 60 seconds (v4)
        $_SESSION[$cacheKey]        = $studentMap;
        $_SESSION['room_id_map_v4'] = $roomIdMap;
        $_SESSION[$cacheExpireKey]  = time() + 60;
    }

    // ── Attach students to rooms and recalculate bed counts ────────────────
    foreach ($rooms as &$room) {
        $rid      = isset($room['id']) ? (int)$room['id'] : 0;
        $students = [];

        // Merge by numeric room ID
        if ($rid > 0 && isset($roomIdMap[$rid])) {
            $students = $roomIdMap[$rid];
        }

        // Merge by normalized room_code
        $codeKey = $normKey($room['room_code'] ?? '');
        if ($codeKey !== '' && isset($studentMap[$codeKey])) {
            $students = array_unique(array_merge($students, $studentMap[$codeKey]));
        }

        // Merge by normalized room_no
        $noKey = $normKey($room['room_no'] ?? '');
        if ($noKey !== '' && $noKey !== $codeKey && isset($studentMap[$noKey])) {
            $students = array_unique(array_merge($students, $studentMap[$noKey]));
        }

        $uniqueStudents = array_values($students);
        $room['students'] = $uniqueStudents;

        // Recalculate occupied/available counts in real-time
        $stCount      = count($uniqueStudents);
        $dbOccupied   = (int)($room['occupied_beds'] ?? 0);
        $liveOccupied = max($dbOccupied, $stCount);
        $totalBeds    = max(1, (int)($room['total_beds'] ?? 1));
        $pending      = (int)($room['assigned_pending'] ?? 0);

        $room['occupied_beds']  = $liveOccupied;
        $room['available_beds'] = max(0, $totalBeds - $liveOccupied - $pending);
    }
    unset($room);

    // ── Fetch all distinct locations (hostels), building codes & floor numbers for filter dropdowns ──
    $lStmt = $db->query("SELECT DISTINCT location_name FROM room_master WHERE location_name IS NOT NULL AND location_name != '' ORDER BY location_name");
    $allLocations = $lStmt ? $lStmt->fetchAll(PDO::FETCH_COLUMN) : [];

    $bStmt = $db->query("SELECT DISTINCT building_code FROM room_master WHERE building_code IS NOT NULL AND building_code != '' ORDER BY building_code");
    $allBuildings = $bStmt ? $bStmt->fetchAll(PDO::FETCH_COLUMN) : [];

    $fStmt = $db->query("SELECT DISTINCT floor_no FROM room_master WHERE floor_no IS NOT NULL AND floor_no != '' ORDER BY floor_no");
    $allFloors = $fStmt ? $fStmt->fetchAll(PDO::FETCH_COLUMN) : [];

    echo json_encode([
        "status"      => "success",
        "success"     => true,
        "data"        => $rooms,
        "count"       => count($rooms),
        "total"       => $totalRows,
        "page"        => $page,
        "per_page"    => $per_page,
        "total_pages" => $page > 0 ? (int)ceil($totalRows / $per_page) : 1,
        "locations"   => $allLocations,
        "buildings"   => $allBuildings,
        "floors"      => $allFloors,
    ]);
} catch (Exception $e) {
    echo json_encode([
        "status"  => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
