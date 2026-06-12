<?php
ini_set('display_errors', 0);
error_reporting(E_ALL);

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/response.php';
require_once __DIR__ . '/../utils/activity_logger.php';

$database = new Database();
$db = $database->getConnection();

$raw_input = file_get_contents("php://input");
$data = json_decode($raw_input);

$username = $data->username ?? $_POST['username'] ?? $_GET['username'] ?? null;
$password = $data->password ?? $_POST['password'] ?? $_GET['password'] ?? null;

if ($username && $password) {
    try {
        $query = "SELECT u.id, u.full_name, u.username as register_no, u.password, u.role, u.conduct, u.conduct_remarks, u.Status, 
                         p.personal_phone as phone, p.room_allocation, p.institution, p.hostel_name as profile_hostel, p.address, p.dob, p.profile_pic,
                         p.valid_from, p.valid_to, u.biometric_id,
                         hr.room_no as hr_room_no, hr.building_code as block, hr.floor as floor_name, hr.wing_code as wing_name, hr.hostel_name as room_hostel, hr.room_type as room_type,
                         hr.facility as room_facility, hr.bath_attached as room_bath_attached
                  FROM users u
                  LEFT JOIN profile p ON u.username = p.reg_no
                  LEFT JOIN hostel_rooms hr ON (hr.id = p.current_room_id OR (COALESCE(p.current_room_id, 0) = 0 AND hr.room_code = p.room_allocation))
                  WHERE u.username = :username LIMIT 0,1";
            if ($db === null) {
                sendResponse(false, "Database connection failed", null, 500);
            }

            $stmt = $db->prepare($query);
            $stmt->bindParam(':username', $username);
            $stmt->execute();
    
            if ($stmt->rowCount() > 0) {
                $row = $stmt->fetch(PDO::FETCH_ASSOC);
            
            if (password_verify($password, $row['password'])) { 
                
                if (isset($row['Status']) && (strtolower($row['Status']) == 'inactive' || $row['Status'] == '0') && $row['role'] !== 'admin') {
                    sendResponse(false, "Your account is inactive. Please contact the warden.", null, 403);
                    exit();
                }

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
                    "phone" => $row['phone'],
                    "dob" => $row['dob'],
                    "address" => $row['address'],
                    "role" => $row['role'],
                    "institution" => $row['institution'] ?? 'N/A',
                    "hostel_name" => $hostel,
                    "room_allocation" => $row['room_allocation'] ?? 'N/A',
                    "profile_pic" => $row['profile_pic'],
                    "valid_from" => $row['valid_from'] ?? '0000-00-00',
                    "valid_to" => $row['valid_to'] ?? '0000-00-00',
                    "conduct" => $row['conduct'] ?? 'Good',
                    "conduct_remarks" => $row['conduct_remarks'] ?? '',
                    "biometric_id" => $row['biometric_id'],
                    
                    "room_no" => $room_no,
                    "block" => $block,
                    "wing" => $wing,
                    "room_type" => $row['room_type'],
                    "room_facility" => $row['room_facility'] ?? 'NON AC',
                    "room_bath_attached" => $row['room_bath_attached'] ?? 'No',
                    "check_in_date" => $row['valid_from'],
                    "renewal_date" => $row['valid_to']
                ];
                logActivity($row['id'], $row['register_no'], $row['role'], 'LOGIN', 'users', null, ['login_time' => date('Y-m-d H:i:s')]);
                logAudit($row['id'], $row['register_no'], $row['role'], 'LOGIN', 'Authentication', null, ['login_time' => date('Y-m-d H:i:s')]);
                sendResponse(true, "Login successful", $user_data);
            } else {
                logAudit($row['id'], $row['register_no'], $row['role'], 'FAILED_LOGIN_WRONG_PASSWORD', 'Authentication', null, ['attempt_time' => date('Y-m-d H:i:s')]);
                sendResponse(false, "Invalid credentials", null, 401);
            }
        } else {
            // Parent Login Logic
            $parent_query = "SELECT p.*, s.full_name as student_name, s.username as student_username, s.id as std_id
                            FROM parent_users p
                            LEFT JOIN parent_student_map psm ON p.parent_id = psm.parent_id
                            LEFT JOIN users s ON psm.student_id = s.username
                            WHERE p.parent_id = ? LIMIT 0,1";
            $p_stmt = $db->prepare($parent_query);
            $p_stmt->execute([$username]);
            
            if ($p_stmt->rowCount() > 0) {
                $p_row = $p_stmt->fetch(PDO::FETCH_ASSOC);
                
                $verify = false;
                $db_password = $p_row['password'];
                if (strpos($db_password, '$2y$') === 0) {
                    $verify = password_verify($password, $db_password);
                } else {
                    $verify = ($password === $db_password);
                }
                
                if ($verify) {
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
                    
                    logActivity($p_row['id'], $p_row['parent_id'], 'parent', 'LOGIN', 'parent_users', null, ['login_time' => date('Y-m-d H:i:s')]);
                    logAudit($p_row['id'], $p_row['parent_id'], 'parent', 'LOGIN', 'Authentication', null, ['login_time' => date('Y-m-d H:i:s')]);
                    sendResponse(true, "Parent Login successful", $user_data);
                } else {
                    logAudit($p_row['id'], $p_row['parent_id'], 'parent', 'FAILED_LOGIN_WRONG_PASSWORD', 'Authentication', null, ['attempt_time' => date('Y-m-d H:i:s')]);
                    sendResponse(false, "Invalid parent credentials", null, 401);
                }
            } else {
                logAudit(null, $username, 'unknown', 'FAILED_LOGIN_USER_NOT_FOUND', 'Authentication', null, ['attempt_time' => date('Y-m-d H:i:s')]);
                sendResponse(false, "User not found ($username)", null, 404);
            }
        }
    } catch (Throwable $e) {
        sendResponse(false, "Server Error", $e->getMessage(), 500);
    }
} else {
    sendResponse(false, "Incomplete data", null, 200);
}
?>
