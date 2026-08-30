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

    // Check if the user is in the users table first, matching both ID and role if provided to avoid ID collisions between tables
    $is_in_users_table = false;
    if ($role) {
        $stmt_check = $db->prepare("SELECT id FROM users WHERE id = :id AND LOWER(role) = LOWER(:role) LIMIT 1");
        $stmt_check->bindParam(':id', $id);
        $stmt_check->bindParam(':role', $role);
        $stmt_check->execute();
        $is_in_users_table = ($stmt_check->rowCount() > 0);
    } else {
        $stmt_check = $db->prepare("SELECT id FROM users WHERE id = :id LIMIT 1");
        $stmt_check->bindParam(':id', $id);
        $stmt_check->execute();
        $is_in_users_table = ($stmt_check->rowCount() > 0);
    }

    if ($is_in_users_table) {
        $query = "SELECT u.id, u.full_name, u.username as register_no, u.role, u.conduct, u.conduct_remarks, u.Status, u.HostelType as hostel_gender, u.RoomType as u_room_type,
                         COALESCE(p.email, u.email) as email, 
                         COALESCE(p.personal_phone, u.phone_number) as phone, 
                         COALESCE(p.institution, u.Institution) as institution, COALESCE(p.hostel_name, u.HostelName) as profile_hostel, p.address, p.dob, p.profile_pic,
                         COALESCE(NULLIF(p.room_allocation,''), u.RoomId) as room_allocation,
                         COALESCE(p.check_in_date, p.valid_from) as p_from, 
                         COALESCE(p.renewal_date, p.valid_to) as p_to,
                         p.renewal_date,
                         p.remaining_days,
                         p.bed_no,
                         COALESCE(NULLIF(rgd.warden_name,''), p.warden) as warden,
                         u.biometric_id,
                         rgd.room_number as hr_room_no, rgd.hostel_name as block, rgd.group_name as floor_name, rgd.group_name as group_name, '' as wing_name, rgd.hostel_name as room_hostel,
                         COALESCE(NULLIF(rgd.room_type,''), NULLIF(rm.room_type,''), u.RoomType) as room_type,
                         COALESCE(NULLIF(rm.amount, 0), NULLIF(rgd.amount, 0), 0) as rm_amount,
                         COALESCE(NULLIF(rm.food, 0), NULLIF(rgd.food, 0), 0) as rm_food,
                         COALESCE(NULLIF(rm.caution_deposit, 0), NULLIF(rgd.caution_deposit, 0), 0) as rm_caution,
                         rgd.room_number as room_code
                  FROM users u
                  LEFT JOIN profile p ON u.username = p.reg_no
                  LEFT JOIN rooms_groups_details rgd ON (
                      rgd.room_number = COALESCE(NULLIF(p.room_allocation,''), u.RoomId)
                      OR REPLACE(REPLACE(TRIM(rgd.room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(COALESCE(NULLIF(p.room_allocation,''), u.RoomId)), ' ', ''), '-', '')
                  )
                  LEFT JOIN room_master rm ON (
                      rm.room_code = COALESCE(NULLIF(p.room_allocation,''), u.RoomId)
                      OR REPLACE(REPLACE(TRIM(rm.room_code), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(COALESCE(NULLIF(p.room_allocation,''), u.RoomId)), ' ', ''), '-', '')
                  )
                  WHERE u.id = :id LIMIT 1";

        $stmt = $db->prepare($query);
        $stmt->bindParam(':id', $id);
        $stmt->execute();

        if ($stmt->rowCount() > 0) {
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            
            $valid_from = (!empty($row['p_from']) && $row['p_from'] != '0000-00-00') ? $row['p_from'] : '';
            $valid_to = (!empty($row['p_to']) && $row['p_to'] != '0000-00-00') ? $row['p_to'] : '';
            
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

            // Mapped warden/staff details override
            $final_role = $row['role'];
            $mapped_hostel = $hostel;
            $mapped_floor = $block;
            $mapped_wing = $wing;

            if (in_array(strtolower($row['role']), ['warden', 'security', 'maintenance', 'staff'])) {
                $mappingStmt = $db->prepare("SELECT role, hostel_name, floor_name, wing_name FROM mapping_staff WHERE staff_bio_id = :bio_id OR username = :username LIMIT 1");
                $mappingStmt->execute([':bio_id' => $row['register_no'], ':username' => $row['register_no']]);
                $mappingRow = $mappingStmt->fetch(PDO::FETCH_ASSOC);
                if ($mappingRow) {
                    $mapped_role = strtolower($mappingRow['role'] ?? '');
                    if (in_array($mapped_role, ['warden', 'security', 'maintenance'])) {
                        $final_role = $mapped_role;
                    }
                    $mapped_hostel = $mappingRow['hostel_name'] ?? $hostel;
                    $mapped_floor = $mappingRow['floor_name'] ?? $block;
                    $mapped_wing = $mappingRow['wing_name'] ?? $wing;
                }
            }

            // Dynamic fee calculation per room and room type
            $resolvedRoomType = trim($row['room_type'] ?? $row['u_room_type'] ?? 'Standard Room');
            $rTypeLower = strtolower($resolvedRoomType);
            $isAc = (strpos($rTypeLower, 'ac') !== false);

            $room_amount = (float)($row['rm_amount'] > 0 ? $row['rm_amount'] : 0);
            if ($room_amount <= 0 && !empty($resolvedRoomType)) {
                $typeStmt = $db->prepare("SELECT MAX(amount) as amt FROM room_master WHERE LOWER(TRIM(room_type)) = ? AND amount > 0");
                $typeStmt->execute([$rTypeLower]);
                $typeAmt = $typeStmt->fetchColumn();
                if ($typeAmt && $typeAmt > 0) {
                    $room_amount = (float)$typeAmt;
                } else {
                    $room_amount = 70000;
                }
            }

            $room_food = (float)($row['rm_food'] > 0 ? $row['rm_food'] : 50000);
            $room_caution = (float)($row['rm_caution'] > 0 ? $row['rm_caution'] : ($isAc ? 10000 : 5000));
            $total_fee = $room_amount + $room_food + $room_caution;
            $renew_amount = $room_amount + $room_food;

            // Resolve available_roles for dual-role access (e.g. Warden + Maintenance)
            $available_roles = [strtolower($final_role)];
            if (in_array(strtolower($final_role), ['warden', 'maintenance', 'security', 'staff'])) {
                $bio_check = trim($row['register_no']);
                
                $maintCheck = $db->prepare("SELECT COUNT(*) FROM maintenance_users WHERE bio_id = :bio");
                $maintCheck->execute([':bio' => $bio_check]);
                if ($maintCheck->fetchColumn() > 0 && !in_array('maintenance', $available_roles)) {
                    $available_roles[] = 'maintenance';
                }
                
                $wardenCheck = $db->prepare("SELECT COUNT(*) FROM staff_users WHERE bio_id = :bio AND LOWER(role) = 'warden'");
                $wardenCheck->execute([':bio' => $bio_check]);
                if ($wardenCheck->fetchColumn() > 0 && !in_array('warden', $available_roles)) {
                    $available_roles[] = 'warden';
                }
                
                if (strtolower($row['role']) === 'warden' && !in_array('warden', $available_roles)) {
                    $available_roles[] = 'warden';
                }
            }

            $user_data = [
                "id" => $row['id'],
                "username" => $row['register_no'],
                "full_name" => $row['full_name'],
                "register_no" => $row['register_no'],
                "email" => $row['email'] ?? '',
                "phone" => $row['phone'] ?? '',
                "dob" => $row['dob'] ?? '',
                "address" => $row['address'] ?? '',
                "role" => $final_role,
                "available_roles" => array_values(array_unique($available_roles)),
                "institution" => $row['institution'] ?? 'N/A',
                "hostel_name" => $mapped_hostel,
                "room_allocation" => $row['room_allocation'] ?? 'N/A',
                "bed_no" => $row['bed_no'] ?? 'N/A',
                "profile_pic" => $row['profile_pic'] ?? '',
                "valid_from" => $valid_from,
                "valid_to" => $valid_to,
                "renewal_date" => $row['renewal_date'] ?? $valid_to,
                "remaining_days" => (int)($row['remaining_days'] ?? 0),
                "conduct" => $row['conduct'] ?? 'Good',
                "conduct_remarks" => $row['conduct_remarks'] ?? '',
                "biometric_id" => $row['biometric_id'] ?? '',
                "warden" => $row['warden'] ?? '',
                "group_name" => $row['group_name'] ?? $row['floor_name'] ?? '',
                "floor_name" => $row['floor_name'] ?? $row['group_name'] ?? '',
                "room_no" => $room_no,
                "room_code" => $row['room_code'] ?? $row['room_allocation'] ?? 'N/A',
                "block" => $mapped_floor,
                "wing" => $mapped_wing,
                "room_type" => $resolvedRoomType,
                "room_facility" => $isAc ? 'AC' : 'NON AC',
                "room_bath_attached" => (strpos($rTypeLower, 'bath') !== false || strpos($rTypeLower, 'b and t') !== false) ? 'Yes' : 'No',
                "hostel_type" => $row['hostel_gender'] ?? 'Boys',
                "room_amount" => $room_amount,
                "room_food" => $room_food,
                "room_caution" => $room_caution,
                "total_fee" => $total_fee,
                "renew_amount" => $renew_amount
            ];

            // Check for associated temporary stay requests
            try {
                $stmtTsr = $db->prepare("SELECT * FROM temporary_stay_requests WHERE LOWER(email) = LOWER(:email) OR full_name = :full_name ORDER BY id DESC LIMIT 1");
                $stmtTsr->execute([':email' => $row['email'] ?? '', ':full_name' => $row['full_name']]);
                $tsrRow = $stmtTsr->fetch(PDO::FETCH_ASSOC);
                if ($tsrRow) {
                    if (!empty($tsrRow['hold_expires_at']) && $tsrRow['hold_status'] === 'held') {
                        $rem = strtotime($tsrRow['hold_expires_at']) - time();
                        $tsrRow['hold_remaining_seconds'] = max(0, $rem);
                    }
                    $user_data['temporary_stay_request'] = $tsrRow;
                    if ($final_role === 'guest' || strpos($row['register_no'], 'TEMP_') === 0) {
                        $user_data['role'] = 'guest';
                    }
                    if (!empty($tsrRow['from_date'])) {
                        $user_data['valid_from'] = $tsrRow['from_date'];
                    }
                    if (!empty($tsrRow['to_date'])) {
                        $user_data['valid_to'] = $tsrRow['to_date'];
                        $user_data['renewal_date'] = $tsrRow['to_date'];
                        $nowDay = strtotime(date('Y-m-d'));
                        $toDay = strtotime($tsrRow['to_date']);
                        $calcDays = (int)(($toDay - $nowDay) / 86400);
                        $user_data['remaining_days'] = $calcDays > 0 ? $calcDays : (int)($tsrRow['duration_value'] ?? 1);
                    }
                    if (!empty($tsrRow['amount'])) {
                        $user_data['total_fee'] = (float)$tsrRow['amount'];
                        $user_data['room_amount'] = (float)$tsrRow['amount'];
                        $user_data['renew_amount'] = (float)$tsrRow['amount'];
                    }
                    if (!empty($tsrRow['room_type'])) {
                        $user_data['room_type'] = $tsrRow['room_type'];
                    }
                    if (!empty($tsrRow['warden_name'])) {
                        $user_data['warden'] = $tsrRow['warden_name'];
                    }
                    if (!empty($tsrRow['hostel_name'])) {
                        $user_data['hostel_name'] = $tsrRow['hostel_name'];
                    }
                    if (!empty($tsrRow['room_no'])) {
                        $user_data['room_no'] = $tsrRow['room_no'];
                        $user_data['room_code'] = !empty($tsrRow['room_code']) ? $tsrRow['room_code'] : $tsrRow['room_no'];
                        $user_data['room_allocation'] = $user_data['room_code'];
                    }
                }
            } catch (Exception $eTsr) {}

            echo json_encode(['success' => true, 'data' => $user_data]);
        } else {
            echo json_encode(['success' => false, 'message' => 'User not found']);
        }
        exit;
    }

    if ($role === 'parent') {
        $parent_query = "SELECT p.*, s.full_name as student_name, s.username as student_username, s.id as std_id, s.HostelType as student_hostel_type
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
                "linked_student_name" => $p_row['student_name'],
                "hostel_type" => $p_row['student_hostel_type'] ?? 'Boys'
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

    // All users are now in the unified users table. If we reach here, the user was not found.
    echo json_encode(['success' => false, 'message' => 'User not found']);
} catch (Exception $e) {
    echo json_encode(['success' => false, 'message' => 'Server error: ' . $e->getMessage()]);
}
?>
