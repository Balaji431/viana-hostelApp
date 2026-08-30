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
$data = !empty($raw_input) ? json_decode($raw_input) : null;

$username = null;
$password = null;

if (is_object($data)) {
    $username = $data->username ?? null;
    $password = $data->password ?? null;
}

if (!$username || !$password) {
    foreach (array_merge($_GET, $_POST, $_REQUEST) as $key => $value) {
        $clean_key = trim(strtolower(str_replace(['_', ' '], '', urldecode($key))));
        if ($clean_key === 'username' && empty($username)) {
            $username = trim($value);
        }
        if ($clean_key === 'password' && empty($password)) {
            $password = trim($value);
        }
    }
}

if ($username && $password) {
    try {
        $query = "SELECT u.id, u.full_name, u.username as register_no, u.password, u.role, u.conduct, u.conduct_remarks, u.Status, u.HostelType, u.RoomType as u_room_type,
                         p.personal_phone as phone, p.room_allocation, p.institution, p.hostel_name as profile_hostel, p.address, p.dob, p.profile_pic,
                         p.valid_from, p.valid_to, u.biometric_id, COALESCE(NULLIF(rgd.warden_name,''), p.warden) as warden,
                         rgd.room_number as hr_room_no, rgd.hostel_name as block, rgd.group_name as floor_name, '' as wing_name, rgd.hostel_name as room_hostel, COALESCE(rgd.room_type, rm.room_type, u.RoomType) as room_type,
                         '' as room_facility, '' as room_bath_attached, rgd.room_number as room_code,
                         COALESCE(rgd.amount, rm.amount, 0) as rm_amount,
                         COALESCE(rgd.food, rm.food, 50000) as rm_food,
                         COALESCE(rgd.caution_deposit, rm.caution_deposit, 0) as rm_caution
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
                    // Block student login via Login ID (username/password), EXCEPT for demo students
                    if (strtolower($row['role']) === 'student' && !in_array(trim($row['register_no']), ['192211929', '192511250', '192524999', 'demo'])) {
                        logAudit($row['id'], $row['register_no'], $row['role'], 'LOGIN_BLOCKED', 'Authentication', null, [
                            'registration_no' => $row['register_no'],
                            'timestamp' => date('Y-m-d H:i:s'),
                            'ip_address' => getClientIp(),
                            'source' => 'Normal Login',
                            'reason' => 'Students must use Google Sign In'
                        ]);
                        sendResponse(false, "Students must log in using 'Sign in with Google'. Login ID access is restricted for student accounts.", null, 403);
                        exit();
                    }

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

                    // For staff/warden/security/maintenance: resolve hostel, block, wing from mapping_staff
                    $final_role = $row['role'];
                    if (!in_array(strtolower($row['role']), ['student', 'parent', 'admin'])) {
                        $mappingStmt = $db->prepare("SELECT role, hostel_name, floor_name, wing_name FROM mapping_staff WHERE staff_bio_id = :bio_id OR username = :username2 LIMIT 1");
                        $mappingStmt->execute([':bio_id' => $row['register_no'], ':username2' => $row['register_no']]);
                        $mappingRow = $mappingStmt->fetch(PDO::FETCH_ASSOC);
                        if ($mappingRow) {
                            $mapped_role = strtolower($mappingRow['role'] ?? '');
                            if (in_array($mapped_role, ['warden', 'security', 'maintenance'])) {
                                $final_role = $mapped_role;
                            }
                            if (!empty($mappingRow['hostel_name'])) $hostel = $mappingRow['hostel_name'];
                            if (!empty($mappingRow['floor_name'])) $block = $mappingRow['floor_name'];
                            if (!empty($mappingRow['wing_name'])) $wing = $mappingRow['wing_name'];
                        }
                    }

                    // Dynamic fee calculation
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
                        "phone" => $row['phone'],
                        "dob" => $row['dob'],
                        "address" => $row['address'],
                        "role" => $final_role,
                        "available_roles" => array_values(array_unique($available_roles)),
                        "institution" => $row['institution'] ?? 'N/A',
                        "hostel_name" => $hostel,
                        "room_allocation" => $row['room_allocation'] ?? 'N/A',
                        "profile_pic" => $row['profile_pic'],
                        "valid_from" => $row['valid_from'] ?? '0000-00-00',
                        "valid_to" => $row['valid_to'] ?? '0000-00-00',
                        "conduct" => $row['conduct'] ?? 'Good',
                        "conduct_remarks" => $row['conduct_remarks'] ?? '',
                        "biometric_id" => $row['biometric_id'],
                        "warden" => $row['warden'] ?? '',
                        "group_name" => $row['floor_name'] ?? $row['group_name'] ?? '',
                        "floor_name" => $row['floor_name'] ?? $row['group_name'] ?? '',
                        "room_no" => $room_no,
                        "room_code" => $row['room_code'] ?? $row['room_allocation'] ?? 'N/A',
                        "block" => $block,
                        "wing" => $wing,
                        "room_type" => $resolvedRoomType,
                        "room_facility" => $row['room_facility'] ?? 'NON AC',
                        "room_bath_attached" => $row['room_bath_attached'] ?? 'No',
                        "room_amount" => $room_amount,
                        "room_food" => $room_food,
                        "room_caution" => $room_caution,
                        "total_fee" => $total_fee,
                        "renew_amount" => $renew_amount,
                        "token" => generateJWT($row['id'], $row['register_no'], $final_role)
                    ];
                    
                    logActivity($row['id'], $row['register_no'], $final_role, 'LOGIN', 'users', null, ['login_time' => date('Y-m-d H:i:s')]);
                    logAudit($row['id'], $row['register_no'], $final_role, 'LOGIN_SUCCESS', 'Authentication', null, [
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
                        if (!in_array(trim($username), ['192211929', '192511250'])) {
                            sendResponse(false, "Students must log in using 'Sign in with Google'. Login ID access is restricted for student accounts.", null, 403);
                            exit();
                        }
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
                            "room_code"        => $row['room_code'] ?? $row['room_allocation'] ?? 'N/A',
                            "block"            => 'N/A',
                            "wing"             => 'N/A',
                            "room_type"        => $row['room_type'],
                            "room_facility"    => $row['room_facility'] ?? 'NON AC',
                            "room_bath_attached" => $row['room_bath_attached'] ?? 'No',
                            "check_in_date"    => $row['valid_from'],
                            "renewal_date"     => $row['valid_to'],
                            "hostel_type"      => $row['HostelType'] ?? 'Boys',
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
                                    LEFT JOIN parent_student_map psm ON (CONVERT(p.parent_id USING utf8mb4) = CONVERT(psm.parent_id USING utf8mb4))
                                    LEFT JOIN users s ON (CONVERT(psm.student_id USING utf8mb4) = CONVERT(s.username USING utf8mb4))
                                    WHERE LOWER(CONVERT(p.parent_id USING utf8mb4)) = LOWER(CONVERT(? USING utf8mb4)) LIMIT 0,1";
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

                        // Allow default password (welcome123) for parent accounts
                        if (!$verify && $password === 'welcome123') {
                            $verify = true;
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
                            sendResponse(false, "Incorrect password", null, 401);
                        }
                    } else if (preg_match('/^(p-|p_|parent[-_]?)(.+)$/i', $username, $matches)) {
                        // Dynamic parent lookup by student reg no prefix
                        $std_reg = trim($matches[2]);
                        $s_stmt = $db->prepare("SELECT id, username, full_name FROM users WHERE (LOWER(CONVERT(username USING utf8mb4)) = LOWER(CONVERT(:reg USING utf8mb4))) LIMIT 1");
                        $s_stmt->execute([':reg' => $std_reg]);
                        $s_row = $s_stmt->fetch(PDO::FETCH_ASSOC);

                        if (!$s_row) {
                            $s_stmt2 = $db->prepare("SELECT user_id as id, reg_no as username, full_name FROM profile WHERE (LOWER(CONVERT(reg_no USING utf8mb4)) = LOWER(CONVERT(:reg USING utf8mb4))) LIMIT 1");
                            $s_stmt2->execute([':reg' => $std_reg]);
                            $s_row = $s_stmt2->fetch(PDO::FETCH_ASSOC);
                        }

                        if (!$s_row) {
                            $s_stmt3 = $db->prepare("SELECT 0 as id, roll_number as username, student_name as full_name FROM vstudy_payments WHERE (LOWER(CONVERT(roll_number USING utf8mb4)) = LOWER(CONVERT(:reg USING utf8mb4))) LIMIT 1");
                            $s_stmt3->execute([':reg' => $std_reg]);
                            $s_row = $s_stmt3->fetch(PDO::FETCH_ASSOC);
                        }

                        if ($s_row) {
                            if ($password === 'welcome123') {
                                $p_id = "p-" . strtolower($s_row['username']);
                                $hash = password_hash('welcome123', PASSWORD_BCRYPT);
                                $insP = $db->prepare("INSERT INTO parent_users (parent_id, password) VALUES (?, ?) ON DUPLICATE KEY UPDATE password = VALUES(password)");
                                $insP->execute([$p_id, $hash]);

                                $insM = $db->prepare("INSERT IGNORE INTO parent_student_map (parent_id, student_id) VALUES (?, ?)");
                                $insM->execute([$p_id, $s_row['username']]);

                                $user_data = [
                                    "id" => $s_row['id'],
                                    "username" => $p_id,
                                    "register_no" => $p_id,
                                    "full_name" => "Parent of " . $s_row['full_name'],
                                    "role" => 'parent',
                                    "profile_pic" => "",
                                    "linked_student_id" => $s_row['id'],
                                    "linked_student_username" => $s_row['username'],
                                    "linked_student_name" => $s_row['full_name']
                                ];
                                sendResponse(true, "Parent Login successful", $user_data);
                            } else {
                                sendResponse(false, "Incorrect password", null, 401);
                            }
                        } else {
                            sendResponse(false, "Enter valid username", null, 401);
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
                        sendResponse(false, "Enter valid username", null, 401);
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
