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

// Initialize database connection
$database = new DatabaseMysqli();
$conn = $database->getConnection();

/**
 * Helper to fetch exact fee from renew_fee table
 */
function getFeeForRoomType($conn, $room_type_name, $request_id = null) {
    if (empty($room_type_name)) {
        if ($request_id) {
            // Try to find the actual room type from the requested room
            $res = $conn->query("SELECT rm.room_type FROM room_master rm JOIN room_change_requests rcr ON rm.room_code = rcr.requested_room WHERE rcr.request_id = '$request_id'");
            if ($res && $row = $res->fetch_assoc()) {
                $room_type_name = $row['room_type'];
            }
        }
    }
    
    $normalized = strtoupper(trim($room_type_name ?? ''));
    
    // Robust check for 6 IN 1 AC rooms
    if ($normalized === 'AC - B ATTACHED (6 IN 1)' || 
        $normalized === 'AC - B ATTACHED' || 
        (strpos($normalized, '6 IN 1') !== false && strpos($normalized, 'AC') !== false)) {
        return 65000.00;
    }

    // Robust check for 4 IN 1 AC rooms
    if ($normalized === 'AC - B ATTACHED (4 IN 1)' || 
        (strpos($normalized, '4 IN 1') !== false && strpos($normalized, 'AC') !== false)) {
        return 75000.00;
    }
    
    if (empty($normalized) || $normalized === 'AC' || $normalized === 'NON AC' || $normalized === 'STANDARD') {
        if ($request_id) {
             $res = $conn->query("SELECT rm.room_type FROM room_master rm JOIN room_change_requests rcr ON rm.room_code = rcr.requested_room WHERE rcr.request_id = '$request_id'");
             if ($res && $row = $res->fetch_assoc()) {
                 return getFeeForRoomType($conn, $row['room_type']);
             }
        }
    }
    
    // Look up in hostel_renew_fee table for other types
    $query = "SELECT hostel_fee, monthly_amount FROM hostel_renew_fee WHERE UPPER(TRIM(room_type)) = ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("s", $normalized);
    $stmt->execute();
    $res = $stmt->get_result()->fetch_assoc();
    
    if ($res) {
        if (floatval($res['hostel_fee']) > 0) return (float)$res['hostel_fee'];
        if (floatval($res['monthly_amount']) > 0) return (float)$res['monthly_amount'] * 12;
    }
    
    return 0;
}

/**
 * Helper to fetch the floorwise warden for the requested room code
 */
function getWardenForRequestedRoom($conn, $requested_room_code) {
    // 1. Get requested room's location details
    $query = "SELECT rm.location_name as hostel_name, rm.floor_no as floor, rm.building_code as wing_code 
              FROM room_master rm 
              WHERE rm.room_code = ? LIMIT 1";
              
    $stmt = $conn->prepare($query);
    $stmt->bind_param("s", $requested_room_code);
    $stmt->execute();
    $location = $stmt->get_result()->fetch_assoc();
    
    if (!$location) {
        return 'warden1'; // If room not found, falls back to chief warden warden1
    }
    
    $h_name = strtolower(trim($location['hostel_name'] ?? ''));
    $f_name = strtolower(trim($location['floor'] ?? ''));
    $w_name = strtolower(trim($location['wing_code'] ?? ''));
    
    // 2. Fetch all wardens from mapping_staff (joining unified users table to get synchronized names)
    $staff_res = $conn->query("SELECT COALESCE(su.full_name, ms.name) as name, ms.role, COALESCE(su.phone_number, ms.phone) as phone, COALESCE(ms.staff_bio_id, ms.username) as username, ms.hostel_name, ms.floor_name, ms.wing_name 
                               FROM mapping_staff ms
                               LEFT JOIN users su ON ms.staff_bio_id COLLATE utf8mb4_general_ci = su.username COLLATE utf8mb4_general_ci
                               WHERE LOWER(TRIM(ms.role)) COLLATE utf8mb4_general_ci = 'warden' COLLATE utf8mb4_general_ci");
    if (!$staff_res) {
        return 'warden1';
    }
    
    $staff_list = [];
    while ($staff = $staff_res->fetch_assoc()) {
        $ms_h = strtolower(trim($staff['hostel_name'] ?? ''));
        $ms_f = strtolower(trim($staff['floor_name'] ?? ''));
        $ms_w = strtolower(trim($staff['wing_name'] ?? ''));
        
        // Match hostel
        $hostel_match = false;
        if ($ms_h === $h_name || 
            (!empty($ms_h) && strpos($h_name, $ms_h) !== false) || 
            (!empty($h_name) && strpos($ms_h, $h_name) !== false) || 
            empty($ms_h)) {
            $hostel_match = true;
        }
        
        if (!$hostel_match) continue;
        
        // Match floor
        $floor_match = false;
        $f_name_norm = $f_name;
        $ms_f_norm = $ms_f;
        
        // Normalize floor values
        if ($f_name === 'f00' || $f_name === 'ground' || $f_name === 'ground floor') $f_name_norm = 'ground';
        if ($f_name === 'f01' || $f_name === '1st floor') $f_name_norm = '1st floor';
        if ($f_name === 'f02' || $f_name === '2nd floor') $f_name_norm = '2nd floor';
        if ($f_name === 'f03' || $f_name === '3rd floor') $f_name_norm = '3rd floor';
        if ($f_name === 'f04' || $f_name === '4th floor') $f_name_norm = '4th floor';
        
        if ($ms_f === 'f00' || $ms_f === 'ground' || $ms_f === 'ground floor') $ms_f_norm = 'ground';
        if ($ms_f === 'f01' || $ms_f === '1st floor') $ms_f_norm = '1st floor';
        if ($ms_f === 'f02' || $ms_f === '2nd floor') $ms_f_norm = '2nd floor';
        if ($ms_f === 'f03' || $ms_f === '3rd floor') $ms_f_norm = '3rd floor';
        if ($ms_f === 'f04' || $ms_f === '4th floor') $ms_f_norm = '4th floor';
        
        if ($ms_f_norm === $f_name_norm || empty($ms_f)) {
            $floor_match = true;
        }
        
        if (!$floor_match) continue;
        
        // Match wing
        if ($ms_w !== $w_name && !empty($ms_w)) {
            continue;
        }
        
        // Calculate score exactly like get_assigned_staff.php
        $score = 0;
        if ($ms_w === $w_name) {
            $score += 10;
        }
        if ($ms_f_norm === $f_name_norm) {
            $score += 5;
        }
        if ($ms_h === $h_name) {
            $score += 1;
        }
        
        $staff['score'] = $score;
        $staff_list[] = $staff;
    }
    
    if (empty($staff_list)) {
        return 'warden1'; // Fallback
    }
    
    // Sort by score desc
    usort($staff_list, function($a, $b) {
        return $b['score'] <=> $a['score'];
    });
    
    return $staff_list[0]['username'] ?? 'warden1';
}

try {
    // Auto-cancel approved requests that were not completed/paid within 3 days (72 hours)
    $conn->query("UPDATE room_change_requests 
                  SET status = 'cancelled', payment_status = 'unpaid', remarks = 'Auto-cancelled after 3 days due to non-payment' 
                  WHERE (LOWER(status) = 'approved' OR LOWER(status) = 'pre_approved') 
                  AND payment_status = 'unpaid' 
                  AND updated_at < DATE_SUB(NOW(), INTERVAL 3 DAY)");

    // Get filters
    $status = isset($_GET['status']) ? $_GET['status'] : 'pending';
    $warden_username = isset($_GET['warden_username']) ? $_GET['warden_username'] : null;
    $student_id = isset($_GET['student_id']) ? $_GET['student_id'] : null;
    
    $params = [];
    $param_types = "";
    
    if ($status !== 'all') {
        $params[] = $status;
        $param_types .= "s";
    }

    $student_filter = "";
    if ($student_id) {
        $student_filter = " AND student_id = ?";
        $params[] = intval($student_id);
        $param_types .= "i";
    }

    // Prepare query based on status
    if ($status === 'all') {
        $query = "SELECT * FROM room_change_requests WHERE 1=1 $student_filter ORDER BY created_at DESC";
    } else {
        $query = "SELECT * FROM room_change_requests WHERE status = ? $student_filter ORDER BY created_at DESC";
    }

    $stmt = $conn->prepare($query);
    if (!empty($params)) {
        $stmt->bind_param($param_types, ...$params);
    }
    
    $stmt->execute();
    $result = $stmt->get_result();
    
    $requests = [];
    while ($row = $result->fetch_assoc()) {
        // Filter by assigned warden in PHP
        if ($warden_username && strtolower($warden_username) !== 'admin' && strtolower($warden_username) !== 'warden1') {
            $escaped_w = $conn->real_escape_string($warden_username);
            $w_check = $conn->query("SELECT DISTINCT hostel_name FROM mapping_staff WHERE (TRIM(username) = '$escaped_w' OR TRIM(staff_bio_id) = '$escaped_w' OR LOWER(TRIM(name)) LIKE '%" . strtolower($escaped_w) . "%') AND LOWER(role) = 'warden'");
            $managed_hostels = [];
            if ($w_check) {
                while ($w_row = $w_check->fetch_assoc()) {
                    if (!empty($w_row['hostel_name'])) {
                        $managed_hostels[] = strtolower(trim($w_row['hostel_name']));
                    }
                }
            }

            if (!empty($managed_hostels)) {
                $req_room = strtolower($row['requested_room'] ?? '');
                $curr_room = strtolower($row['current_room'] ?? '');
                $reason_str = strtolower($row['reason'] ?? '');
                $is_match = false;
                foreach ($managed_hostels as $mh) {
                    if ($mh != '' && (strpos($req_room, $mh) !== false || strpos($curr_room, $mh) !== false || strpos($reason_str, $mh) !== false)) {
                        $is_match = true;
                        break;
                    }
                }
                if (!$is_match) {
                    $assigned_warden = getWardenForRequestedRoom($conn, $row['requested_room']);
                    if ($assigned_warden !== $warden_username && $assigned_warden !== 'warden1') {
                        continue;
                    }
                }
            }
        }
        $amt = (float)$row['amount_to_pay'];
        $rtype = $row['requested_room_type'] ?? 'Standard';
        
        // Lazy fix for existing requests with 0 amount
        if (($row['status'] == 'pre_approved' || $row['status'] == 'approved') && $amt <= 0) {
            $amt = getFeeForRoomType($conn, $rtype, $row['request_id']);
            if ($amt > 0) {
                $conn->query("UPDATE room_change_requests SET amount_to_pay = $amt WHERE request_id = '" . $row['request_id'] . "'");
            }
        }

        $requests[] = [
            'request_id' => $row['request_id'],
            'student_id' => (int)$row['student_id'],
            'student_name' => $row['student_name'],
            'student_reg_no' => $row['student_reg_no'],
            'current_room' => $row['current_room'],
            'requested_room' => $row['requested_room'],
            'requested_room_type' => $rtype,
            'amount_to_pay' => $amt,
            'payment_status' => $row['payment_status'] ?? 'unpaid',
            'reason' => $row['reason'],
            'status' => $row['status'],
            'processed_by' => $row['processed_by'] ? (int)$row['processed_by'] : null,
            'processed_by_name' => $row['processed_by_name'],
            'remarks' => $row['remarks'],
            'created_at' => $row['created_at'],
            'updated_at' => $row['updated_at']
        ];
    }
    
    echo json_encode([
        'success' => true,
        'status' => 'success',
        'message' => 'Room change requests retrieved successfully',
        'data' => $requests
    ]);
    
} catch(mysqli_sql_exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'status' => 'error',
        'message' => 'Database error: ' . $e->getMessage()
    ]);
} catch(Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}
?>
