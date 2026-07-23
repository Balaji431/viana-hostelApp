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

/**
 * Student Hostel Rooms API
 * For fetching available rooms for room booking/changing
 */

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

$database = new DatabaseMysqli();
$conn = $database->getConnection();

function getNormalizedGender($str) {
    $str = strtolower(trim($str));
    if (stripos($str, 'girl') !== false || stripos($str, 'female') !== false || stripos($str, 'women') !== false) {
        return 'girls';
    }
    return 'boys';
}

$method = $_SERVER['REQUEST_METHOD'];

// Auto-release expired reservations
releaseExpiredReservations($conn);

if ($method === 'GET') {
    if (isset($_GET['hostel_id'])) {
        // Get available rooms for specific hostel
        getAvailableRoomsByHostel($conn, $_GET['hostel_id']);
    } elseif (isset($_GET['room_type'])) {
        // Get rooms by type
        getRoomsByType($conn, $_GET['room_type']);
    } elseif (isset($_GET['vacant_only']) && $_GET['vacant_only'] === 'true') {
        // Get only rooms with vacancies
        getVacantRooms($conn);
    } else {
        // Get all available rooms with filters
        getAvailableRooms($conn, $_GET);
    }
} else {
    http_response_code(405);
    echo json_encode(['status' => 'error', 'message' => 'Method not allowed']);
}

/**
 * Get available rooms by hostel with grouped by floor
 */
function getAvailableRoomsByHostel($conn, $hostelId) {
    try {
        $sql = "SELECT hr.*, 
                       (hr.available_rooms - COALESCE(res.res_count, 0)) as available_beds_calc
                FROM hostel_rooms hr
                LEFT JOIN (
                    SELECT TRIM(requested_room) as requested_room, COUNT(*) as res_count 
                    FROM room_change_requests 
                    WHERE status IN ('pre_approved', 'approved') 
                    AND payment_status = 'unpaid'
                    AND reserved_until > NOW()
                    AND requested_room IS NOT NULL AND requested_room != ''
                    GROUP BY TRIM(requested_room)
                ) res ON TRIM(hr.room_code) = res.requested_room
                WHERE hr.hostel_id = ? 
                ORDER BY hr.floor_code, hr.room_no";
        
        $stmt = $conn->prepare($sql);
        $stmt->bind_param("i", $hostelId);
        $stmt->execute();
        $result = $stmt->get_result();
        $rooms_raw = $result->fetch_all(MYSQLI_ASSOC);
        
        // Map calculated beds back to available_rooms for UI compatibility
        $rooms = array_map(function($r) {
            $r['available_rooms'] = max(0, (int)$r['available_beds_calc']);
            return $r;
        }, $rooms_raw);

        // Group by floor
        $floors = [];
        foreach ($rooms as $room) {
            $floorCode = $room['floor_code'];
            if (!isset($floors[$floorCode])) {
                $floors[$floorCode] = [
                    'floor_code' => $floorCode,
                    'floor_name' => $room['floor'],
                    'rooms' => []
                ];
            }
            $floors[$floorCode]['rooms'][] = $room;
        }

        // Calculate hostel summary
        $totalRooms = count($rooms);
        $totalBeds = array_sum(array_column($rooms, 'total_capacity'));
        $availableBeds = array_sum(array_column($rooms, 'available_rooms'));
        $occupiedBeds = array_sum(array_column($rooms, 'occupied_rooms'));

        echo json_encode([
            'status' => 'success',
            'summary' => [
                'total_rooms' => $totalRooms,
                'total_beds' => $totalBeds,
                'available_beds' => $availableBeds,
                'occupied_beds' => $occupiedBeds
            ],
            'floors' => array_values($floors)
        ]);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
    }
}

/**
 * Get rooms by type
 */
function getRoomsByType($conn, $roomType) {
    try {
        $sql = "SELECT hr.*, ht.campus, ht.hostel_name as hostel,
                       (hr.available_rooms - COALESCE(res.res_count, 0)) as available_beds_calc
                FROM hostel_rooms hr
                JOIN hostel_type ht ON hr.hostel_id = ht.id
                LEFT JOIN (
                    SELECT TRIM(requested_room) as requested_room, COUNT(*) as res_count 
                    FROM room_change_requests 
                    WHERE status IN ('pre_approved', 'approved') 
                    AND payment_status = 'unpaid'
                    AND reserved_until > NOW()
                    AND requested_room IS NOT NULL AND requested_room != ''
                    GROUP BY TRIM(requested_room)
                ) res ON TRIM(hr.room_code) = res.requested_room
                WHERE hr.room_type LIKE ?
                HAVING available_beds_calc > 0
                ORDER BY hr.amount ASC";
        
        $stmt = $conn->prepare($sql);
        $search = "%$roomType%";
        $stmt->bind_param("s", $search);
        $stmt->execute();
        $result = $stmt->get_result();
        $rooms_raw = $result->fetch_all(MYSQLI_ASSOC);
        
        $rooms = array_map(function($r) {
            $r['available_rooms'] = max(0, (int)$r['available_beds_calc']);
            return $r;
        }, $rooms_raw);

        echo json_encode([
            'status' => 'success',
            'count' => count($rooms),
            'data' => $rooms
        ]);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
    }
}

/**
 * Get all rooms with vacancies
 */
function getVacantRooms($conn) {
    try {
        $student_hostel_type = null;
        if (!empty($_GET['register_no'])) {
            $stmt_std = $conn->prepare("SELECT u.HostelType, u.Gender, p.hostel_name 
                                        FROM users u 
                                        LEFT JOIN profile p ON u.username = p.reg_no 
                                        WHERE u.username = ? LIMIT 1");
            $stmt_std->bind_param("s", $_GET['register_no']);
            $stmt_std->execute();
            $res_std = $stmt_std->get_result()->fetch_assoc();
            if ($res_std) {
                $student_hostel_type = !empty(trim($res_std['HostelType'] ?? '')) ? $res_std['HostelType'] : null;
                if ($student_hostel_type === null) {
                    $student_hostel_type = !empty(trim($res_std['Gender'] ?? '')) ? $res_std['Gender'] : null;
                }
                if ($student_hostel_type === null && !empty($res_std['hostel_name'])) {
                    $hn = strtolower($res_std['hostel_name']);
                    if (strpos($hn, 'noyal') !== false || strpos($hn, 'vaigai') !== false || strpos($hn, 'girl') !== false) {
                        $student_hostel_type = 'Girls';
                    }
                }
            }
        } elseif (!empty($_GET['student_id'])) {
            $stmt_std = $conn->prepare("SELECT u.HostelType, u.Gender, p.hostel_name 
                                        FROM users u 
                                        LEFT JOIN profile p ON u.id = p.user_id 
                                        WHERE u.id = ? LIMIT 1");
            $stmt_std->bind_param("i", $_GET['student_id']);
            $stmt_std->execute();
            $res_std = $stmt_std->get_result()->fetch_assoc();
            if ($res_std) {
                $student_hostel_type = !empty(trim($res_std['HostelType'] ?? '')) ? $res_std['HostelType'] : null;
                if ($student_hostel_type === null) {
                    $student_hostel_type = !empty(trim($res_std['Gender'] ?? '')) ? $res_std['Gender'] : null;
                }
                if ($student_hostel_type === null && !empty($res_std['hostel_name'])) {
                    $hn = strtolower($res_std['hostel_name']);
                    if (strpos($hn, 'noyal') !== false || strpos($hn, 'vaigai') !== false || strpos($hn, 'girl') !== false) {
                        $student_hostel_type = 'Girls';
                    }
                }
            }
        }

        // Final fallback if still null: default to 'Boys'
        if ($student_hostel_type === null) {
            $student_hostel_type = 'Boys';
        }

        $student_gender = getNormalizedGender($student_hostel_type);

        $sql = "SELECT hr.*, ht.campus, ht.hostel_name as hostel_name, ht.hostel_type as hostel_type,
                       (hr.available_rooms - COALESCE(res.res_count, 0)) as available_beds_calc
                FROM hostel_rooms hr
                JOIN hostel_type ht ON hr.hostel_id = ht.id
                LEFT JOIN (
                    SELECT TRIM(requested_room) as requested_room, COUNT(*) as res_count 
                    FROM room_change_requests 
                    WHERE status IN ('pre_approved', 'approved') 
                    AND payment_status = 'unpaid'
                    AND reserved_until > NOW()
                    AND requested_room IS NOT NULL AND requested_room != ''
                    GROUP BY TRIM(requested_room)
                ) res ON TRIM(hr.room_code) = res.requested_room";
                
        if ($student_gender !== null) {
            $sql .= " WHERE (hr.available_rooms - COALESCE(res.res_count, 0)) > 0 AND (CASE WHEN LOWER(TRIM(ht.hostel_type)) LIKE '%girl%' OR LOWER(TRIM(ht.hostel_type)) LIKE '%female%' OR LOWER(TRIM(ht.hostel_type)) LIKE '%women%' THEN 'girls' ELSE 'boys' END) = ?";
        } else {
            $sql .= " WHERE (hr.available_rooms - COALESCE(res.res_count, 0)) > 0";
        }
        
        $sql .= " ORDER BY ht.campus, hr.hostel_id, hr.floor_code, hr.room_no";
        
        $stmt = $conn->prepare($sql);
        if ($student_gender !== null) {
            $stmt->bind_param("s", $student_gender);
        }
        $stmt->execute();
        $result = $stmt->get_result();
        $rooms_raw = $result->fetch_all(MYSQLI_ASSOC);
        
        $rooms = array_map(function($r) {
            $r['available_rooms'] = max(0, (int)$r['available_beds_calc']);
            return $r;
        }, $rooms_raw);

        // Group by hostel
        $hostels = [];
        foreach ($rooms as $room) {
            $hostelId = $room['hostel_id'];
            if (!isset($hostels[$hostelId])) {
                $hostels[$hostelId] = [
                    'hostel_id' => $hostelId,
                    'hostel_name' => $room['hostel_name'],
                    'hostel_type' => $room['hostel_type'],
                    'campus' => $room['campus'],
                    'rooms' => []
                ];
            }
            $hostels[$hostelId]['rooms'][] = $room;
        }

        echo json_encode([
            'status' => 'success',
            'count' => count($rooms),
            'hostels' => array_values($hostels)
        ]);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
    }
}

/**
 * Get available rooms with filters
 */
function getAvailableRooms($conn, $filters = []) {
    try {
        $student_hostel_type = null;
        if (!empty($filters['register_no'])) {
            $stmt_std = $conn->prepare("SELECT u.HostelType, u.Gender, p.hostel_name 
                                        FROM users u 
                                        LEFT JOIN profile p ON u.username = p.reg_no 
                                        WHERE u.username = ? LIMIT 1");
            $stmt_std->bind_param("s", $filters['register_no']);
            $stmt_std->execute();
            $res_std = $stmt_std->get_result()->fetch_assoc();
            if ($res_std) {
                $student_hostel_type = !empty(trim($res_std['HostelType'] ?? '')) ? $res_std['HostelType'] : null;
                if ($student_hostel_type === null) {
                    $student_hostel_type = !empty(trim($res_std['Gender'] ?? '')) ? $res_std['Gender'] : null;
                }
                if ($student_hostel_type === null && !empty($res_std['hostel_name'])) {
                    $hn = strtolower($res_std['hostel_name']);
                    if (strpos($hn, 'noyal') !== false || strpos($hn, 'vaigai') !== false || strpos($hn, 'girl') !== false) {
                        $student_hostel_type = 'Girls';
                    }
                }
            }
        } elseif (!empty($filters['student_id'])) {
            $stmt_std = $conn->prepare("SELECT u.HostelType, u.Gender, p.hostel_name 
                                        FROM users u 
                                        LEFT JOIN profile p ON u.id = p.user_id 
                                        WHERE u.id = ? LIMIT 1");
            $stmt_std->bind_param("i", $filters['student_id']);
            $stmt_std->execute();
            $res_std = $stmt_std->get_result()->fetch_assoc();
            if ($res_std) {
                $student_hostel_type = !empty(trim($res_std['HostelType'] ?? '')) ? $res_std['HostelType'] : null;
                if ($student_hostel_type === null) {
                    $student_hostel_type = !empty(trim($res_std['Gender'] ?? '')) ? $res_std['Gender'] : null;
                }
                if ($student_hostel_type === null && !empty($res_std['hostel_name'])) {
                    $hn = strtolower($res_std['hostel_name']);
                    if (strpos($hn, 'noyal') !== false || strpos($hn, 'vaigai') !== false || strpos($hn, 'girl') !== false) {
                        $student_hostel_type = 'Girls';
                    }
                }
            }
        }

        // Final fallback if still null: default to 'Boys'
        if ($student_hostel_type === null) {
            $student_hostel_type = 'Boys';
        }

        $student_gender = getNormalizedGender($student_hostel_type);

        $sql = "SELECT hr.*, ht.campus, ht.hostel_name as hostel_name, ht.hostel_type as hostel_type,
                       (hr.available_rooms - COALESCE(res.res_count, 0)) as available_beds_calc
                FROM hostel_rooms hr
                JOIN hostel_type ht ON hr.hostel_id = ht.id
                LEFT JOIN (
                    SELECT TRIM(requested_room) as requested_room, COUNT(*) as res_count 
                    FROM room_change_requests 
                    WHERE status IN ('pre_approved', 'approved') 
                    AND payment_status = 'unpaid'
                    AND reserved_until > NOW()
                    AND requested_room IS NOT NULL AND requested_room != ''
                    GROUP BY TRIM(requested_room)
                ) res ON TRIM(hr.room_code) = res.requested_room
                WHERE (hr.available_rooms - COALESCE(res.res_count, 0)) > 0";
        $params = [];
        $types = "";

        if ($student_gender !== null) {
            $sql .= " AND (CASE WHEN LOWER(TRIM(ht.hostel_type)) LIKE '%girl%' OR LOWER(TRIM(ht.hostel_type)) LIKE '%female%' OR LOWER(TRIM(ht.hostel_type)) LIKE '%women%' THEN 'girls' ELSE 'boys' END) = ?";
            $params[] = $student_gender;
            $types .= "s";
        }

        if (!empty($filters['campus'])) {
            $sql .= " AND ht.campus = ?";
            $params[] = $filters['campus'];
            $types .= "s";
        }

        if (!empty($filters['hostel_id'])) {
            $sql .= " AND hr.hostel_id = ?";
            $params[] = $filters['hostel_id'];
            $types .= "i";
        }

        if (!empty($filters['floor'])) {
            $sql .= " AND hr.floor_code = ?";
            $params[] = $filters['floor'];
            $types .= "s";
        }

        if (!empty($filters['room_type'])) {
            $sql .= " AND hr.room_type = ?";
            $params[] = $filters['room_type'];
            $types .= "s";
        }

        if (!empty($filters['facility'])) {
            $sql .= " AND hr.facility = ?";
            $params[] = $filters['facility'];
            $types .= "s";
        }

        if (!empty($filters['max_amount'])) {
            $sql .= " AND hr.amount <= ?";
            $params[] = $filters['max_amount'];
            $types .= "d";
        }

        $sql .= " ORDER BY hr.amount ASC, ht.campus, hr.hostel_id";

        $stmt = $conn->prepare($sql);
        if (!empty($params)) {
            $stmt->bind_param($types, ...$params);
        }
        $stmt->execute();
        $result = $stmt->get_result();
        $rooms_raw = $result->fetch_all(MYSQLI_ASSOC);
        
        $rooms = array_map(function($r) {
            $r['available_rooms'] = max(0, (int)$r['available_beds_calc']);
            return $r;
        }, $rooms_raw);

        echo json_encode([
            'status' => 'success',
            'count' => count($rooms),
            'data' => $rooms
        ]);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
    }
}

/**
 * Auto-release rooms where the reservation has expired
 */
function releaseExpiredReservations($conn) {
    try {
        $sql = "UPDATE room_change_requests 
                SET status = 'expired', remarks = 'Reservation expired due to non-payment'
                WHERE status = 'pre_approved' 
                AND payment_status = 'unpaid' 
                AND reserved_until < CURRENT_TIMESTAMP";
        
        $conn->query($sql);
    } catch (Exception $e) {
        // Silently fail
    }
}
?>
