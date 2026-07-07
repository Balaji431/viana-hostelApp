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
require_once __DIR__ . '/../utils/auth_helper.php';


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
                        logAudit($row['id'], $row['register_no'], $row['role'], 'LOGIN_FAILED', 'Authentication', null, [
                            'registration_no' => $row['register_no'],
                            'timestamp' => date('Y-m-d H:i:s'),
                            'ip_address' => getClientIp(),
                            'source' => 'Normal Login',
                            'reason' => 'Account inactive'
                        ]);
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
                        "renewal_date" => $row['valid_to'],
                        "token" => generateJWT($row['id'], $row['register_no'], $row['role'])
                    ];
                    
                    logActivity($row['id'], $row['register_no'], $row['role'], 'LOGIN', 'users', null, ['login_time' => date('Y-m-d H:i:s')]);
                    logAudit($row['id'], $row['register_no'], $row['role'], 'LOGIN_SUCCESS', 'Authentication', null, [
                        'registration_no' => $row['register_no'],
                        'timestamp' => date('Y-m-d H:i:s'),
                        'ip_address' => getClientIp(),
                        'source' => 'Normal Login'
                    ]);
                    sendResponse(true, "Login successful", $user_data);
                } else {
                    logAudit($row['id'], $row['register_no'], $row['role'], 'LOGIN_FAILED', 'Authentication', null, [
                        'registration_no' => $row['register_no'],
                        'timestamp' => date('Y-m-d H:i:s'),
                        'ip_address' => getClientIp(),
                        'source' => 'Normal Login',
                        'reason' => 'Invalid password'
                    ]);
                    sendResponse(false, "Invalid credentials", null, 401);
                }
            } else {
                // User not found in users table. Check vstudy_payments.
                $stmtPay = $db->prepare("SELECT * FROM vstudy_payments WHERE roll_number = :username LIMIT 0,1");
                $stmtPay->bindParam(':username', $username);
                $stmtPay->execute();

                if ($stmtPay->rowCount() > 0) {
                    $payRow = $stmtPay->fetch(PDO::FETCH_ASSOC);

                    // Check if entered password matches default welcome123
                    if ($password === 'welcome123') {
                        // Create Student User
                        $hashedPassword = password_hash('welcome123', PASSWORD_BCRYPT);
                        $email = strtolower(str_replace(' ', '', $payRow['student_name'])) . '@saveetha.com';
                        $genderType = (stripos($payRow['gender'], 'female') !== false || stripos($payRow['hostel_preference'], 'girls') !== false) ? 'Girls' : 'Boys';
                        $inst = $payRow['campus'] ?? 'Saveetha School of Engineering';

                        $insertUserQuery = "INSERT INTO users (
                            username, password, full_name, role, email, Campus, Institution, HostelName, HostelType, RoomType, Academic, conduct, Status
                        ) VALUES (
                            :username, :password, :full_name, 'student', :email, :campus, :institution, :hostel_name, :hostel_type, :room_type, :academic, 'Good', 'active'
                        )";

                        $insUserStmt = $db->prepare($insertUserQuery);
                        $insUserStmt->execute([
                            ':username' => $payRow['roll_number'],
                            ':password' => $hashedPassword,
                            ':full_name' => $payRow['student_name'],
                            ':email' => $email,
                            ':campus' => $payRow['campus'] ?? 'Thandalam Campus',
                            ':institution' => $inst,
                            ':hostel_name' => $payRow['hostel_name'],
                            ':hostel_type' => $genderType,
                            ':room_type' => $payRow['hostel_preference'],
                            ':academic' => $payRow['academic_year'] ?? '1st Year'
                        ]);

                        $newUserId = $db->lastInsertId();

                        // Create Student Profile
                        $insertProfileQuery = "INSERT INTO profile (
                            user_id, reg_no, full_name, email, institution, hostel_name, profile_pic, valid_from, valid_to
                        ) VALUES (
                            :user_id, :reg_no, :full_name, :email, :institution, :hostel_name, 'profile.png', '01.06.2026', '30.05.2027'
                        )";
                        $insProfileStmt = $db->prepare($insertProfileQuery);
                        $insProfileStmt->execute([
                            ':user_id' => $newUserId,
                            ':reg_no' => $payRow['roll_number'],
                            ':full_name' => $payRow['student_name'],
                            ':email' => $email,
                            ':institution' => $inst,
                            ':hostel_name' => $payRow['hostel_name']
                        ]);

                        // Audit Logging
                        $logMeta = [
                            'registration_no' => $payRow['roll_number'],
                            'timestamp' => date('Y-m-d H:i:s'),
                            'ip_address' => getClientIp(),
                            'source' => 'Paid Student Sync'
                        ];

                        logAudit($newUserId, $payRow['roll_number'], 'student', 'AUTO_STUDENT_CREATED', 'Paid Student Sync', null, $logMeta);
                        logAudit($newUserId, $payRow['roll_number'], 'student', 'FIRST_STUDENT_LOGIN', 'Paid Student Sync', null, $logMeta);
                        logAudit($newUserId, $payRow['roll_number'], 'student', 'LOGIN_SUCCESS', 'Paid Student Sync', null, $logMeta);
                        logActivity($newUserId, $payRow['roll_number'], 'student', 'LOGIN', 'users', null, ['login_time' => date('Y-m-d H:i:s')]);

                        // Fetch newly created user information using original format
                        $stmt = $db->prepare($query);
                        $stmt->bindParam(':username', $username);
                        $stmt->execute();
                        $row = $stmt->fetch(PDO::FETCH_ASSOC);

                        $user_data = [
                            "id"               => $row['id'],
                            "username"         => $row['register_no'],
                            "full_name"        => $row['full_name'],
                            "register_no"      => $row['register_no'],
                            "phone"            => $row['phone'],
                            "dob"              => $row['dob'],
                            "address"          => $row['address'],
                            "role"             => $row['role'],
                            "institution"      => $row['institution'] ?? 'N/A',
                            "hostel_name"      => $row['room_hostel'] ?? $row['profile_hostel'] ?? 'N/A',
                            "room_allocation"  => $row['room_allocation'] ?? 'N/A',
                            "profile_pic"      => $row['profile_pic'],
                            "valid_from"       => $row['valid_from'] ?? '0000-00-00',
                            "valid_to"         => $row['valid_to'] ?? '0000-00-00',
                            "conduct"          => $row['conduct'] ?? 'Good',
                            "conduct_remarks"  => $row['conduct_remarks'] ?? '',
                            "biometric_id"     => $row['biometric_id'],
                            "room_no"          => 'N/A',
                            "block"            => 'N/A',
                            "wing"             => 'N/A',
                            "room_type"        => $row['room_type'],
                            "room_facility"    => $row['room_facility'] ?? 'NON AC',
                            "room_bath_attached" => $row['room_bath_attached'] ?? 'No',
                            "check_in_date"    => $row['valid_from'],
                            "renewal_date"     => $row['valid_to'],
                            "token"            => generateJWT($row['id'], $row['register_no'], $row['role'])
                        ];
                        sendResponse(true, "Login successful", $user_data);
                        exit();
                    } else {
                        // User in vstudy_payments, but wrong password
                        logAudit(null, $username, 'student', 'LOGIN_FAILED', 'Paid Student Sync', null, [
                            'registration_no' => $username,
                            'timestamp' => date('Y-m-d H:i:s'),
                            'ip_address' => getClientIp(),
                            'source' => 'Paid Student Sync',
                            'reason' => 'Invalid password'
                        ]);
                        sendResponse(false, "Invalid credentials", null, 401);
                        exit();
                    }
                } else {
                    // Check Parent Login Logic if not in users and not in vstudy_payments
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
                            logAudit($p_row['id'], $p_row['parent_id'], 'parent', 'LOGIN_SUCCESS', 'Authentication', null, [
                                'registration_no' => $p_row['parent_id'],
                                'timestamp' => date('Y-m-d H:i:s'),
                                'ip_address' => getClientIp(),
                                'source' => 'Normal Login'
                            ]);
                            sendResponse(true, "Parent Login successful", $user_data);
                        } else {
                            logAudit($p_row['id'], $p_row['parent_id'], 'parent', 'LOGIN_FAILED', 'Authentication', null, [
                                'registration_no' => $p_row['parent_id'],
                                'timestamp' => date('Y-m-d H:i:s'),
                                'ip_address' => getClientIp(),
                                'source' => 'Normal Login',
                                'reason' => 'Invalid password'
                            ]);
                            sendResponse(false, "Invalid parent credentials", null, 401);
                        }
                    } else {
                        // User not found in users, vstudy_payments, and parents
                        logAudit(null, $username, 'unknown', 'LOGIN_FAILED', 'Authentication', null, [
                            'registration_no' => $username,
                            'timestamp' => date('Y-m-d H:i:s'),
                            'ip_address' => getClientIp(),
                            'source' => 'Normal Login',
                            'reason' => 'User not found'
                        ]);
                        sendResponse(false, "Invalid Username or Password", null, 401);
                    }
                }
            }
    } catch (Throwable $e) {
        sendResponse(false, "Server Error", $e->getMessage(), 500);
    }
} else {
    sendResponse(false, "Incomplete data", null, 200);
}
?>
