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

function getStudentDetails($conn, $filters) {
    $reg = $filters['register_no'] ?? $filters['username'] ?? $filters['roll_number'] ?? null;
    $id  = $filters['student_id'] ?? null;

    if ($reg) {
        $stmt = $conn->prepare("
            SELECT u.Gender, u.HostelType, u.Institution, p.institution as p_institution, p.hostel_name
            FROM users u
            LEFT JOIN profile p ON u.username = p.reg_no
            WHERE u.username = ? OR u.email = ? LIMIT 1
        ");
        $stmt->bind_param("ss", $reg, $reg);
        $stmt->execute();
        $res = $stmt->get_result()->fetch_assoc();
        if ($res) return $res;
    }

    if ($id) {
        $stmt = $conn->prepare("
            SELECT u.Gender, u.HostelType, u.Institution, p.institution as p_institution, p.hostel_name
            FROM users u
            LEFT JOIN profile p ON u.id = p.user_id
            WHERE u.id = ? LIMIT 1
        ");
        $stmt->bind_param("i", $id);
        $stmt->execute();
        $res = $stmt->get_result()->fetch_assoc();
        if ($res) return $res;
    }

    return null;
}

$method = $_SERVER['REQUEST_METHOD'];

// Auto-release expired reservations
releaseExpiredReservations($conn);

if ($method === 'GET') {
    if ((isset($_GET['vacant_only']) && $_GET['vacant_only'] === 'true') || isset($_GET['hostel_name'])) {
        // Get only rooms with vacancies filtered by student & hostel
        getVacantRooms($conn, $_GET);
    } elseif (isset($_GET['hostel_id']) && is_numeric($_GET['hostel_id'])) {
        // Get available rooms for specific hostel
        getAvailableRoomsByHostel($conn, (int)$_GET['hostel_id']);
    } elseif (isset($_GET['room_type'])) {
        // Get rooms by type
        getRoomsByType($conn, $_GET['room_type']);
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
        $stmtH = $conn->prepare("SELECT hostel_name FROM hostel_type WHERE id = ?");
        $stmtH->bind_param("i", $hostelId);
        $stmtH->execute();
        $resH = $stmtH->get_result()->fetch_assoc();
        $hName = $resH['hostel_name'] ?? '';

        $sql = "SELECT rgd.s_no as id,
                       rgd.room_number as room_no,
                       rgd.room_number as room_code,
                       rgd.group_name as floor,
                       rgd.group_name as floor_code,
                       'General' as wing_code,
                       rgd.total_beds as total_capacity,
                       rgd.occupied_beds as occupied_rooms,
                       rgd.available_beds as available_rooms,
                       rgd.room_type,
                       rgd.amount,
                       rgd.hostel_name,
                       rgd.reserved_for,
                       rgd.reserved_for_roles
                FROM rooms_groups_details rgd
                WHERE TRIM(rgd.hostel_name) = TRIM(?) OR TRIM(rgd.hostel_name) LIKE CONCAT('%', TRIM(?), '%')
                ORDER BY rgd.group_name, rgd.room_number";
        
        $stmt = $conn->prepare($sql);
        $stmt->bind_param("ss", $hName, $hName);
        $stmt->execute();
        $result = $stmt->get_result();
        $rooms = $result->fetch_all(MYSQLI_ASSOC);

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
        $sql = "SELECT rgd.s_no as id, rgd.room_number as room_no, rgd.room_number as room_code,
                       rgd.group_name as floor, rgd.group_name as floor_code, 'General' as wing_code,
                       rgd.total_beds as total_capacity, rgd.occupied_beds as occupied_rooms,
                       rgd.available_beds as available_rooms, rgd.room_type, rgd.amount,
                       rgd.hostel_name as hostel, 'Thandalam Campus' as campus
                FROM rooms_groups_details rgd
                WHERE rgd.room_type LIKE ?
                ORDER BY rgd.amount ASC";
        
        $stmt = $conn->prepare($sql);
        $search = "%$roomType%";
        $stmt->bind_param("s", $search);
        $stmt->execute();
        $result = $stmt->get_result();
        $rooms = $result->fetch_all(MYSQLI_ASSOC);

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
 * Get all rooms with vacancies (Filtered by student Gender & Institution)
 */
function getVacantRooms($conn, $filters = []) {
    try {
        $student = getStudentDetails($conn, $filters);
        $gender = null;
        $institution = null;

        if ($student) {
            $rawGender = $student['Gender'] ?? $student['HostelType'] ?? '';
            $gender = (stripos($rawGender, 'girl') !== false || stripos($rawGender, 'female') !== false) ? 'Female' : 'Male';
            // Prefer users.Institution; fall back to profile.institution if blank
            $rawInst = '';
            if (!empty(trim($student['Institution'] ?? ''))) {
                $rawInst = trim($student['Institution']);
            } elseif (!empty(trim($student['p_institution'] ?? ''))) {
                $rawInst = trim($student['p_institution']);
            }
            if ($rawInst !== '') {
                $inst = $rawInst;
                if (stripos($inst, 'Engineering') !== false || stripos($inst, 'SSE') !== false
                    || (stripos($inst, 'SIMATS') !== false && stripos($inst, 'Medicine') === false && stripos($inst, 'Dentist') === false)
                    || stripos($inst, 'Thandalam') !== false) {
                    $institution = 'SIMATS - Engineering';
                } elseif (stripos($inst, 'Medicine') !== false || stripos($inst, 'SMC') !== false) {
                    $institution = 'SMC - Medicine';
                } elseif (stripos($inst, 'Dentist') !== false || stripos($inst, 'SDC') !== false) {
                    $institution = 'SDC - Dentistry';
                } elseif (stripos($inst, 'Law') !== false || stripos($inst, 'SSL') !== false) {
                    $institution = 'SSL - Law';
                } elseif (stripos($inst, 'Management') !== false || stripos($inst, 'SSM') !== false) {
                    $institution = 'SSM - Management';
                } elseif (stripos($inst, 'Physical') !== false || stripos($inst, 'SSPE') !== false) {
                    $institution = 'SSPE - Physical Education';
                } elseif (stripos($inst, 'Nursing') !== false || stripos($inst, 'SNC') !== false) {
                    $institution = 'SNC - Nursing';
                } else {
                    $institution = $inst;
                }
            }
        }

        $conditions = ["rgd.available_beds > 0"];
        $params = [];
        $types = "";

        if ($gender) {
            // Strict gender match — blank/NULL gender rooms excluded from both boys & girls
            $conditions[] = "(rgd.gender = ? AND rgd.gender IS NOT NULL AND TRIM(rgd.gender) != '')";
            $params[] = $gender;
            $types .= "s";
        }

        if ($institution) {
            // Institution KNOWN → show ONLY rooms explicitly reserved for this institution
            $conditions[] = "(rgd.reserved_for IS NOT NULL AND rgd.reserved_for != '[]' AND JSON_CONTAINS(rgd.reserved_for, JSON_QUOTE(?)))";
            $params[] = $institution;
            $types .= "s";
        } else {
            // Institution UNKNOWN → only show completely unrestricted rooms
            $conditions[] = "(rgd.reserved_for IS NULL OR rgd.reserved_for = '[]')";
        }

        // Filter by specific hostel if provided
        if (!empty($filters['hostel_name'])) {
            $conditions[] = "TRIM(rgd.hostel_name) = TRIM(?)";
            $params[] = $filters['hostel_name'];
            $types .= "s";
        } elseif (!empty($filters['hostel_id'])) {
            $conditions[] = "rgd.hostel_name = (SELECT hostel_name FROM hostel_type WHERE id = ? LIMIT 1)";
            $params[] = $filters['hostel_id'];
            $types .= "i";
        }

        $whereClause = implode(" AND ", $conditions);

        $sql = "SELECT rgd.s_no as id,
                       rgd.room_number,
                       rgd.room_number as room_code,
                       rgd.group_name as floor,
                       rgd.group_name as floor_code,
                       rgd.total_beds as total_capacity,
                       rgd.occupied_beds as occupied_rooms,
                       rgd.available_beds,
                       rgd.available_beds as available_rooms,
                       rgd.room_type,
                       rgd.amount,
                       rgd.hostel_name,
                       rgd.gender as hostel_gender,
                       rgd.reserved_for
                FROM rooms_groups_details rgd
                WHERE $whereClause
                ORDER BY rgd.hostel_name, rgd.room_type, rgd.group_name, rgd.room_number";

        $stmt = $conn->prepare($sql);
        if (!empty($params)) {
            $stmt->bind_param($types, ...$params);
        }
        $stmt->execute();
        $result = $stmt->get_result();
        $rooms = $result->fetch_all(MYSQLI_ASSOC);

        // Group by hostel
        $hostels = [];
        foreach ($rooms as $room) {
            $hName = $room['hostel_name'];
            if (!isset($hostels[$hName])) {
                $hostels[$hName] = [
                    'hostel_name' => $room['hostel_name'],
                    'rooms' => []
                ];
            }
            $hostels[$hName]['rooms'][] = $room;
        }

        echo json_encode([
            'status'               => 'success',
            'count'                => count($rooms),
            'data'                 => $rooms,
            'student_institution'  => $institution,
            'student_gender'       => $gender,
            'hostels'              => array_values($hostels)
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
