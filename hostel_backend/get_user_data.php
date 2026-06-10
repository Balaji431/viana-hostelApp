<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header('Access-Control-Allow-Credentials: true');
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/config/database.php';

$id = $_GET['id'] ?? null;
$role = $_GET['role'] ?? null;

if (!$id) {
    echo json_encode(['success' => false, 'message' => 'ID is required']);
    exit;
}

try {
    $database = new Database();
    $db = $database->getConnection();

    if ($role === 'parent') {
        $parent_query = "SELECT p.*, s.full_name as student_name, s.username as student_username, s.id as std_id
                        FROM parent_users p
                        LEFT JOIN parent_student_map psm ON p.parent_id = psm.parent_id
                        LEFT JOIN users s ON psm.student_id = s.username
                        WHERE p.id = :id LIMIT 1";
        $stmt = $db->prepare($parent_query);
        $stmt->bindParam(':id', $id);
        $stmt->execute();
        
        if ($stmt->rowCount() > 0) {
            $p_row = $stmt->fetch(PDO::FETCH_ASSOC);
            $user_data = [
                "id" => $p_row['id'],
                "username" => $p_row['parent_id'],
                "register_no" => $p_row['parent_id'],
                "full_name" => "Parent of " . ($p_row['student_name'] ?? 'Student'),
                "phone" => $p_row['contact'],
                "role" => 'parent',
                "profile_pic" => "",
                "linked_student_id" => $p_row['std_id'],
                "linked_student_username" => $p_row['student_username'],
                "linked_student_name" => $p_row['student_name']
            ];
            
            if ($p_row['student_username']) {
                $prof_query = "SELECT room_allocation, institution, hostel_name, profile_pic FROM profile WHERE reg_no = ?";
                $prof_stmt = $db->prepare($prof_query);
                $prof_stmt->execute([$p_row['student_username']]);
                $prof = $prof_stmt->fetch(PDO::FETCH_ASSOC);
                if ($prof) {
                    $user_data['linked_student_room'] = $prof['room_allocation'];
                    $user_data['linked_student_institution'] = $prof['institution'];
                    $user_data['linked_student_hostel'] = $prof['hostel_name'];
                    $user_data['linked_student_profile_pic'] = $prof['profile_pic'];
                }
            }
            echo json_encode(['success' => true, 'data' => $user_data]);
        } else {
            echo json_encode(['success' => false, 'message' => 'Parent not found']);
        }
        exit;
    }

    // Use profile directly as primary source of room allocation details
    $query = "SELECT u.id, u.full_name, u.username as register_no, u.role, u.conduct, u.conduct_remarks, u.Status, 
                     COALESCE(p.email, u.email) as email, 
                     COALESCE(p.personal_phone, u.phone_number) as phone, 
                     p.institution, p.hostel_name as profile_hostel, p.address, p.dob, p.profile_pic, p.room_allocation,
                     COALESCE(p.check_in_date, p.valid_from) as p_from, 
                     COALESCE(p.renewal_date, p.valid_to) as p_to,
                     p.bed_no,
                     u.biometric_id,
                     hr.room_no as hr_room_no, hr.building_code as block, hr.floor as floor_name, hr.wing_code as wing_name, hr.hostel_name as room_hostel,
                     hr.room_type as room_type, hr.facility as room_facility, hr.bath_attached as room_bath_attached
              FROM users u
              LEFT JOIN profile p ON u.username = p.reg_no
              LEFT JOIN hostel_rooms hr ON (hr.id = p.current_room_id OR (COALESCE(p.current_room_id, 0) = 0 AND hr.room_code = p.room_allocation))
              WHERE u.id = :id LIMIT 1";

    $stmt = $db->prepare($query);
    $stmt->bindParam(':id', $id);
    $stmt->execute();

    if ($stmt->rowCount() > 0) {
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        
        // Logical Date Resolution:
        // Use profile dates directly
        $valid_from = (!empty($row['p_from']) && $row['p_from'] != '0000-00-00') ? $row['p_from'] : '';
        $valid_to = (!empty($row['p_to']) && $row['p_to'] != '0000-00-00') ? $row['p_to'] : '';
        
        // Final fallback if empty
        if (empty($valid_from) || $valid_from == '0000-00-00') $valid_from = date('Y-m-d');
        if (empty($valid_to) || $valid_to == '0000-00-00') $valid_to = date('Y-m-d', strtotime('+1 year'));

        $room_no = $row['hr_room_no'] ?? 'N/A';
        $block = $row['block'] ?? 'N/A';
        
        $floor = (!empty($row['floor_name']) && $row['floor_name'] != 'N/A') ? $row['floor_name'] : '';
        $wing_code = (!empty($row['wing_name']) && $row['wing_name'] != 'N/A') ? $row['wing_name'] : '';
        
        $wing = 'N/A';
        if ($floor && $wing_code) {
            $wing = "$floor - $wing_code";
        } else if ($floor) {
            $wing = $floor;
        } else if ($wing_code) {
            $wing = $wing_code;
        }
        $hostel = $row['room_hostel'] ?? $row['profile_hostel'] ?? 'N/A';
        
        if ($room_no == 'N/A' && !empty($row['room_allocation'])) {
            $room_no = $row['room_allocation'];
        }

        $user_data = [
            "id" => $row['id'],
            "username" => $row['register_no'],
            "full_name" => $row['full_name'],
            "register_no" => $row['register_no'],
            "email" => $row['email'],
            "phone" => $row['phone'],
            "dob" => $row['dob'],
            "address" => $row['address'],
            "role" => $row['role'],
            "institution" => $row['institution'] ?? 'N/A',
            "hostel_name" => $hostel,
            "room_allocation" => $row['room_allocation'] ?? 'N/A',
            "bed_no" => $row['bed_no'] ?? 'N/A',
            "profile_pic" => $row['profile_pic'],
            "valid_from" => $valid_from,
            "valid_to" => $valid_to,
            "conduct" => $row['conduct'] ?? 'Good',
            "conduct_remarks" => $row['conduct_remarks'] ?? '',
            "biometric_id" => $row['biometric_id'],
            "room_no" => $room_no,
            "block" => $block,
            "wing" => $wing,
            "room_type" => $row['room_type'],
            "room_facility" => $row['room_facility'] ?? 'NON AC',
            "room_bath_attached" => $row['room_bath_attached'] ?? 'No'
        ];
        echo json_encode(['success' => true, 'data' => $user_data]);
    } else {
        echo json_encode(['success' => false, 'message' => 'User not found']);
    }
} catch (Exception $e) {
    echo json_encode(['success' => false, 'message' => 'Server error: ' . $e->getMessage()]);
}
?>
