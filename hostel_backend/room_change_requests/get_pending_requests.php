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
function getWardenDetailsForRequestedRoom($conn, $requested_room_code, $reason_text = '') {
    if (empty($requested_room_code)) {
        return ['username' => 'warden1', 'name' => 'Hostel Warden'];
    }

    // 1. Direct check in rooms_groups_details (live physical rooms sync table)
    $rgd_stmt = $conn->prepare("
        SELECT hostel_name, warden_bio_id, warden_name 
        FROM rooms_groups_details 
        WHERE TRIM(room_number) = TRIM(?) 
           OR REPLACE(REPLACE(TRIM(room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(?), ' ', ''), '-', '')
        LIMIT 1
    ");
    $rgd_stmt->bind_param("ss", $requested_room_code, $requested_room_code);
    $rgd_stmt->execute();
    $rgd_res = $rgd_stmt->get_result()->fetch_assoc();
    
    if ($rgd_res) {
        $wname = trim($rgd_res['warden_name'] ?? '');
        $wbio = trim($rgd_res['warden_bio_id'] ?? '');

        if (!empty($wname)) {
            return [
                'username' => !empty($wbio) ? $wbio : $wname,
                'name' => $wname
            ];
        }
        if (!empty($wbio)) {
            $staff_w = $conn->query("SELECT name FROM mapping_staff WHERE staff_bio_id = '" . $conn->real_escape_string($wbio) . "' OR username = '" . $conn->real_escape_string($wbio) . "' LIMIT 1");
            if ($staff_w && $sw_row = $staff_w->fetch_assoc()) {
                return ['username' => $wbio, 'name' => trim($sw_row['name'])];
            }
            return ['username' => $wbio, 'name' => 'Hostel Warden'];
        }
        if (!empty($rgd_res['hostel_name'])) {
            $hname = trim($rgd_res['hostel_name']);
            $staff_h = $conn->query("SELECT COALESCE(staff_bio_id, username) as uname, name FROM mapping_staff WHERE LOWER(role) = 'warden' AND LOWER(TRIM(hostel_name)) LIKE '%" . strtolower($conn->real_escape_string($hname)) . "%' LIMIT 1");
            if ($staff_h && $sh_row = $staff_h->fetch_assoc()) {
                return ['username' => $sh_row['uname'], 'name' => trim($sh_row['name'])];
            }
        }
    }

    // 2. Check room_master table
    $query = "SELECT rm.location_name as hostel_name, rm.floor_no as floor, rm.building_code as wing_code 
              FROM room_master rm 
              WHERE rm.room_code = ? LIMIT 1";
              
    $stmt = $conn->prepare($query);
    $stmt->bind_param("s", $requested_room_code);
    $stmt->execute();
    $location = $stmt->get_result()->fetch_assoc();
    
    $h_name = strtolower(trim($location['hostel_name'] ?? ''));
    $f_name = strtolower(trim($location['floor'] ?? ''));
    $w_name = strtolower(trim($location['wing_code'] ?? ''));

    // Extract hostel name from reason or requested room if location not found
    if (empty($h_name)) {
        $combined_text = strtolower(($requested_room_code ?? '') . ' ' . ($reason_text ?? ''));
        if (strpos($combined_text, 'radiance') !== false || strpos($combined_text, 'p-05') !== false || strpos($combined_text, 'p05') !== false) $h_name = 'radiance inn';
        else if (strpos($combined_text, 'stunner') !== false || strpos($combined_text, 'p-10') !== false || strpos($combined_text, 'p10') !== false) $h_name = 'stunners den';
        else if (strpos($combined_text, 'ponni') !== false || strpos($combined_text, 't-09') !== false || strpos($combined_text, 't09') !== false) $h_name = 'ponni';
        else if (strpos($combined_text, 'porunai') !== false || strpos($combined_text, 't-19') !== false || strpos($combined_text, 't19') !== false) $h_name = 'porunai';
        else if (strpos($combined_text, 'vaigai') !== false || strpos($combined_text, 't-32') !== false || strpos($combined_text, 't32') !== false) $h_name = 'vaigai';
        else if (strpos($combined_text, 'bhavani') !== false) $h_name = 'bhavani';
        else if (strpos($combined_text, 'kaveri') !== false || strpos($combined_text, 't-12') !== false || strpos($combined_text, 't12') !== false) $h_name = 'kaveri';
        else if (strpos($combined_text, 'krishna') !== false || strpos($combined_text, 't-30') !== false || strpos($combined_text, 't30') !== false) $h_name = 'krishna';
        else if (strpos($combined_text, 'siruvani') !== false || strpos($combined_text, 't-14') !== false || strpos($combined_text, 't14') !== false) $h_name = 'siruvani';
        else if (strpos($combined_text, 'noyyal') !== false || strpos($combined_text, 't-22') !== false || strpos($combined_text, 't22') !== false) $h_name = 'noyyal';
        else if (strpos($combined_text, 'palar') !== false || strpos($combined_text, 't-10') !== false || strpos($combined_text, 't10') !== false) $h_name = 'palar';
    }
    
    // 3. Fetch matching warden from mapping_staff
    $staff_res = $conn->query("SELECT COALESCE(su.full_name, ms.name) as name, ms.role, COALESCE(su.phone_number, ms.phone) as phone, COALESCE(ms.staff_bio_id, ms.username) as username, ms.hostel_name, ms.floor_name, ms.wing_name 
                               FROM mapping_staff ms
                               LEFT JOIN users su ON ms.staff_bio_id COLLATE utf8mb4_general_ci = su.username COLLATE utf8mb4_general_ci
                               WHERE LOWER(TRIM(ms.role)) COLLATE utf8mb4_general_ci = 'warden' COLLATE utf8mb4_general_ci");
    if (!$staff_res) {
        if (strpos($h_name, 'radiance') !== false || strpos($requested_room_code, 'P-05') !== false || strpos($requested_room_code, 'P05') !== false) return '29563';
        if (strpos($h_name, 'stunner') !== false || strpos($requested_room_code, 'P-10') !== false || strpos($requested_room_code, 'P10') !== false) return '2919';
        return 'warden1';
    }

    $normFloor = function($val) {
        $v = strtolower(trim($val ?? ''));
        if (strpos($v, 'ground') !== false || strpos($v, 'f00') !== false || strpos($v, 'g floor') !== false) return 'ground';
        if (strpos($v, 'first') !== false || strpos($v, '1st') !== false || strpos($v, 'f01') !== false) return '1st floor';
        if (strpos($v, 'second') !== false || strpos($v, '2nd') !== false || strpos($v, 'f02') !== false) return '2nd floor';
        if (strpos($v, 'third') !== false || strpos($v, '3rd') !== false || strpos($v, 'f03') !== false) return '3rd floor';
        if (strpos($v, 'fourth') !== false || strpos($v, '4th') !== false || strpos($v, 'f04') !== false) return '4th floor';
        if (strpos($v, 'fifth') !== false || strpos($v, '5th') !== false || strpos($v, 'f05') !== false) return '5th floor';
        if (strpos($v, 'sixth') !== false || strpos($v, '6th') !== false || strpos($v, 'f06') !== false) return '6th floor';
        return $v;
    };
    
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
        $f_name_norm = $normFloor($f_name);
        $ms_f_norm = $normFloor($ms_f);
        
        $floor_match = false;
        if ($ms_f_norm === $f_name_norm || empty($ms_f_norm) || empty($f_name_norm)) {
            $floor_match = true;
        }
        
        if (!$floor_match) continue;
        
        if ($ms_w !== $w_name && !empty($ms_w) && !empty($w_name) && $ms_w !== 'all') {
            continue;
        }
        
        $score = 0;
        if ($ms_w === $w_name && !empty($w_name)) $score += 10;
        if ($ms_f_norm === $f_name_norm && !empty($f_name_norm)) $score += 5;
        if ($ms_h === $h_name && !empty($h_name)) $score += 1;
        
        $staff['score'] = $score;
        $staff_list[] = $staff;
    }
    
    if (empty($staff_list)) {
        // Precise campus-aware fallbacks
        if (strpos($h_name, 'radiance') !== false || strpos($requested_room_code, 'P-05') !== false || strpos($requested_room_code, 'P05') !== false) {
            return ['username' => '29563', 'name' => 'Syed Surath Nisha'];
        }
        if (strpos($h_name, 'stunner') !== false || strpos($requested_room_code, 'P-10') !== false || strpos($requested_room_code, 'P10') !== false) {
            return ['username' => '2919', 'name' => 'Saroj Kumar Tivari'];
        }
        return ['username' => 'warden1', 'name' => 'Hostel Warden'];
    }
    
    usort($staff_list, function($a, $b) {
        return $b['score'] <=> $a['score'];
    });
    
    return [
        'username' => $staff_list[0]['username'] ?? 'warden1',
        'name' => $staff_list[0]['name'] ?? 'Hostel Warden'
    ];
}

function getWardenForRequestedRoom($conn, $requested_room_code, $reason_text = '') {
    $info = getWardenDetailsForRequestedRoom($conn, $requested_room_code, $reason_text);
    return $info['username'] ?? 'warden1';
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
                    $assigned_warden = getWardenForRequestedRoom($conn, $row['requested_room'], $row['reason'] ?? '');
                    if ($assigned_warden !== $warden_username) {
                        continue;
                    }
                }
            }
        }
        $amt = (float)($row['amount_to_pay'] ?? 0.0);
        $rtype = $row['requested_room_type'] ?? 'Standard';

        $r_code = strtoupper($row['requested_room'] ?? $row['current_room'] ?? '');
        $r_reason = strtolower($row['reason'] ?? '');
        $campus = 'Thandalam Campus';
        if (strpos($r_code, 'P-05') !== false || strpos($r_code, 'P05') !== false ||
            strpos($r_code, 'P-10') !== false || strpos($r_code, 'P10') !== false ||
            strpos($r_code, 'P-') !== false || strpos($r_code, 'P0') !== false ||
            strpos($r_reason, 'radiance') !== false || strpos($r_reason, 'stunner') !== false) {
            $campus = 'Poonamallee Campus';
        }

        $warden_info = getWardenDetailsForRequestedRoom($conn, $row['requested_room'], $row['reason'] ?? '');

        $requests[] = [
            'request_id' => $row['request_id'],
            'student_id' => (int)$row['student_id'],
            'student_name' => $row['student_name'],
            'student_reg_no' => $row['student_reg_no'],
            'campus' => $campus,
            'current_room' => $row['current_room'],
            'requested_room' => $row['requested_room'],
            'requested_room_type' => $rtype,
            'amount_to_pay' => $amt,
            'payment_status' => $row['payment_status'] ?? 'unpaid',
            'reason' => $row['reason'],
            'status' => $row['status'],
            'assigned_warden_name' => $warden_info['name'],
            'assigned_warden_username' => $warden_info['username'],
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
