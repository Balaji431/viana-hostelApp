<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json");
header("Cache-Control: no-store, no-cache, must-revalidate, max-age=0");
header("Cache-Control: post-check=0, pre-check=0", false);
header("Pragma: no-cache");
// Enable gzip output compression on the PHP level for large payloads
if (extension_loaded('zlib') && !ob_get_level()) {
    ob_start('ob_gzhandler');
}

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once '../config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();

    $locationFilter = isset($_GET['location_name']) ? $_GET['location_name'] : '';
    $buildingFilter = isset($_GET['building_code']) ? $_GET['building_code'] : '';
    $floorFilter    = isset($_GET['floor_no'])      ? $_GET['floor_no']      : '';
    $roomTypeFilter = isset($_GET['room_type'])     ? $_GET['room_type']     : '';
    $searchFilter   = isset($_GET['search'])        ? $_GET['search']        : '';

    // Pagination support — default: return all (page=0 disables pagination)
    $page     = isset($_GET['page'])  ? max(0, (int)$_GET['page'])  : 0;
    $per_page = isset($_GET['limit']) ? max(1, (int)$_GET['limit']) : 500;

    $sql    = "SELECT * FROM room_master WHERE 1=1";
    $params = [];

    if (!empty($locationFilter)) {
        $sql    .= " AND location_name = ?";
        $params[] = $locationFilter;
    }

    if (!empty($buildingFilter)) {
        $sql    .= " AND building_code = ?";
        $params[] = $buildingFilter;
    }

    if (!empty($floorFilter)) {
        $sql    .= " AND floor_no = ?";
        $params[] = $floorFilter;
    }

    if (!empty($roomTypeFilter)) {
        $sql    .= " AND room_type = ?";
        $params[] = $roomTypeFilter;
    }

    if (!empty($searchFilter)) {
        $sql           .= " AND (room_no LIKE ? OR location_name LIKE ? OR building_code LIKE ? OR room_code LIKE ?)";
        $searchParam    = "%$searchFilter%";
        $params[]       = $searchParam;
        $params[]       = $searchParam;
        $params[]       = $searchParam;
        $params[]       = $searchParam;
    }

    $sql .= " ORDER BY id ASC";

    // Count total rows
    $countSql  = "SELECT COUNT(*) as total FROM room_master WHERE 1=1";
    // (Re-build count with same filters but skip ORDER BY / LIMIT)
    $countBase = substr($sql, strpos($sql, 'WHERE'));
    $countStmt = $db->prepare("SELECT COUNT(*) as total FROM room_master " . $countBase);
    // Remove ORDER BY from count query
    $countSqlClean = preg_replace('/ORDER BY.*$/i', '', "SELECT COUNT(*) as total FROM room_master " . $countBase);
    $countStmt2 = $db->prepare($countSqlClean);
    $countStmt2->execute($params);
    $totalRows = (int)($countStmt2->fetch(PDO::FETCH_ASSOC)['total'] ?? 0);

    // Apply pagination only when page > 0
    if ($page > 0) {
        $offset  = ($page - 1) * $per_page;
        $sql    .= " LIMIT $per_page OFFSET $offset";
    }

    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $rooms = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Helper function to normalize room keys for fuzzy matching
    if (!function_exists('normRoomKey')) {
        function normRoomKey($str) {
            if (empty($str)) return '';
            $s = strtoupper(trim($str));
            // Standardize WO / W-O to W0
            $s = preg_replace('/W[-_\s]*O(?=\d)/', 'W0', $s);
            // Strip bed suffixes like -B1, -BED1, -B2, -A, -B at the end
            $s = preg_replace('/[-_\s]+(BED|B|SLOT)?\s*\d+$/i', '', $s);
            // Remove non-alphanumeric
            $s = preg_replace('/[^A-Z0-9]/', '', $s);
            return $s;
        }
    }

    $studentMap = []; // normKey => array of roll_numbers
    $roomIdMap  = []; // room_id => array of roll_numbers

    $addRoll = function(&$map, $key, $rollNo) {
        $k = normRoomKey($key);
        $r = trim($rollNo);
        if (!empty($k) && !empty($r)) {
            if (!isset($map[$k])) $map[$k] = [];
            if (!in_array($r, $map[$k])) $map[$k][] = $r;
        }
    };

    // 0. Query users table directly for synchronized student RoomId allocations
    try {
        $stmt0 = $db->query("
            SELECT username as roll_no, RoomId as room_allocation, id as user_id
            FROM users
            WHERE role = 'student' AND (RoomId IS NOT NULL AND RoomId != '' AND RoomId != '0')
        ");
        if ($stmt0) {
            while ($row = $stmt0->fetch(PDO::FETCH_ASSOC)) {
                $rollNo = trim($row['roll_no']);
                $roomAlloc = trim($row['room_allocation']);
                if (!empty($rollNo) && !empty($roomAlloc)) {
                    $addRoll($studentMap, $roomAlloc, $rollNo);
                }
            }
        }
    } catch (Exception $e) {}

    // 1. Query profile table
    try {
        $stmt1 = $db->query("
            SELECT u.username as roll_no, p.reg_no, p.room_allocation, p.current_room_id
            FROM profile p
            LEFT JOIN users u ON p.user_id = u.id OR p.reg_no = u.username
            WHERE (p.room_allocation IS NOT NULL AND p.room_allocation != '')
               OR (p.current_room_id IS NOT NULL AND p.current_room_id > 0)
        ");
        if ($stmt1) {
            while ($row = $stmt1->fetch(PDO::FETCH_ASSOC)) {
                $rollNo = !empty($row['reg_no']) ? trim($row['reg_no']) : trim($row['roll_no']);
                if (!empty($row['room_allocation'])) $addRoll($studentMap, $row['room_allocation'], $rollNo);
                if (!empty($row['current_room_id'])) {
                    $rid = (int)$row['current_room_id'];
                    if (!isset($roomIdMap[$rid])) $roomIdMap[$rid] = [];
                    if (!in_array($rollNo, $roomIdMap[$rid])) $roomIdMap[$rid][] = $rollNo;
                }
            }
        }
    } catch (Exception $e) {}

    // 2. Query room_allocations table
    try {
        $stmt2 = $db->query("
            SELECT u.username as roll_no, p.reg_no, ra.allocated_room_id, rm.room_code, rm.room_no, rm.location_code
            FROM room_allocations ra
            JOIN users u ON ra.student_id = u.id
            LEFT JOIN profile p ON u.id = p.user_id
            LEFT JOIN room_master rm ON ra.allocated_room_id = rm.id
            WHERE ra.allocation_status IN ('approved', 'confirmed', 'payment_pending', 'allocated')
        ");
        if ($stmt2) {
            while ($row = $stmt2->fetch(PDO::FETCH_ASSOC)) {
                $rollNo = !empty($row['reg_no']) ? trim($row['reg_no']) : trim($row['roll_no']);
                if (!empty($row['allocated_room_id'])) {
                    $rid = (int)$row['allocated_room_id'];
                    if (!isset($roomIdMap[$rid])) $roomIdMap[$rid] = [];
                    if (!in_array($rollNo, $roomIdMap[$rid])) $roomIdMap[$rid][] = $rollNo;
                }
                if (!empty($row['room_code'])) $addRoll($studentMap, $row['room_code'], $rollNo);
                if (!empty($row['location_code'])) $addRoll($studentMap, $row['location_code'], $rollNo);
                if (!empty($row['room_no'])) $addRoll($studentMap, $row['room_no'], $rollNo);
            }
        }
    } catch (Exception $e) {}

    // 3. Query allocation_requests table
    try {
        $stmt3 = $db->query("
            SELECT u.username as roll_no, p.reg_no, ar.selected_room_id
            FROM allocation_requests ar
            JOIN users u ON ar.student_id = u.id
            LEFT JOIN profile p ON u.id = p.user_id
            WHERE ar.status IN ('approved', 'confirmed', 'payment_pending', 'allocated')
        ");
        if ($stmt3) {
            while ($row = $stmt3->fetch(PDO::FETCH_ASSOC)) {
                $rollNo = !empty($row['reg_no']) ? trim($row['reg_no']) : trim($row['roll_no']);
                if (!empty($row['selected_room_id'])) {
                    $rid = (int)$row['selected_room_id'];
                    if (!isset($roomIdMap[$rid])) $roomIdMap[$rid] = [];
                    if (!in_array($rollNo, $roomIdMap[$rid])) $roomIdMap[$rid][] = $rollNo;
                }
            }
        }
    } catch (Exception $e) {}

    // 4. Query room_change_requests table
    try {
        $stmt4 = $db->query("
            SELECT u.username as roll_no, p.reg_no, rcr.requested_room, rcr.allocated_room
            FROM room_change_requests rcr
            JOIN users u ON rcr.student_id = u.id
            LEFT JOIN profile p ON u.id = p.user_id
            WHERE rcr.status IN ('approved', 'completed', 'pre_approved')
        ");
        if ($stmt4) {
            while ($row = $stmt4->fetch(PDO::FETCH_ASSOC)) {
                $rollNo = !empty($row['reg_no']) ? trim($row['reg_no']) : trim($row['roll_no']);
                if (!empty($row['allocated_room'])) $addRoll($studentMap, $row['allocated_room'], $rollNo);
                if (!empty($row['requested_room'])) $addRoll($studentMap, $row['requested_room'], $rollNo);
            }
        }
    } catch (Exception $e) {}

    // 5. Query vstudy_payments table directly for paid student room allocations
    try {
        $stmt5 = $db->query("
            SELECT roll_number, room_number
            FROM vstudy_payments
            WHERE (room_number IS NOT NULL AND room_number != '')
        ");
        if ($stmt5) {
            while ($row = $stmt5->fetch(PDO::FETCH_ASSOC)) {
                $rollNo = trim($row['roll_number']);
                $roomNo = trim($row['room_number']);
                if (!empty($rollNo) && !empty($roomNo)) {
                    $addRoll($studentMap, $roomNo, $rollNo);
                }
            }
        }
    } catch (Exception $e) {}

    // 6. Query new_api table directly for external booked room allocations
    try {
        $stmt6 = $db->query("
            SELECT registerNumber, roomNumber
            FROM new_api
            WHERE (roomNumber IS NOT NULL AND roomNumber != '')
        ");
        if ($stmt6) {
            while ($row = $stmt6->fetch(PDO::FETCH_ASSOC)) {
                $rollNo = trim($row['registerNumber']);
                $roomNo = trim($row['roomNumber']);
                if (!empty($rollNo) && !empty($roomNo)) {
                    $addRoll($studentMap, $roomNo, $rollNo);
                }
            }
        }
    } catch (Exception $e) {}

    foreach ($rooms as &$room) {
        $rid = isset($room['id']) ? (int)$room['id'] : 0;
        $students = [];

        if ($rid > 0 && isset($roomIdMap[$rid])) {
            $students = array_merge($students, $roomIdMap[$rid]);
        }

        $codeKey = normRoomKey($room['room_code'] ?? '');
        if (!empty($codeKey) && isset($studentMap[$codeKey])) {
            $students = array_merge($students, $studentMap[$codeKey]);
        }

        $noKey = normRoomKey($room['room_no'] ?? '');
        if (!empty($noKey) && isset($studentMap[$noKey])) {
            $students = array_merge($students, $studentMap[$noKey]);
        }

        $uniqueStudents = array_values(array_unique($students));
        $room['students'] = $uniqueStudents;

        // REAL-TIME Occupied Beds calculation:
        // Ensures occupied count & roll numbers update immediately when booked,
        // without waiting for midnight cron job!
        $stCount       = count($uniqueStudents);
        $dbOccupied    = (int)($room['occupied_beds'] ?? 0);
        $liveOccupied  = max($dbOccupied, $stCount);
        $totalBeds     = max(1, (int)($room['total_beds'] ?? 1));
        $pending       = (int)($room['assigned_pending'] ?? 0);

        $room['occupied_beds']  = $liveOccupied;
        $room['available_beds'] = max(0, $totalBeds - $liveOccupied - $pending);
    }
    unset($room);

    echo json_encode([
        "status"      => "success",
        "success"     => true,
        "data"        => $rooms,
        "count"       => count($rooms),
        "total"       => $totalRows,
        "page"        => $page,
        "per_page"    => $per_page,
        "total_pages" => $page > 0 ? ceil($totalRows / $per_page) : 1,
    ]);
} catch (Exception $e) {
    echo json_encode([
        "status"  => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
