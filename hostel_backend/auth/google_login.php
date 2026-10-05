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
require_once __DIR__ . '/../utils/vstudy_sync_helper.php';

$database = new Database();
$db = $database->getConnection();

$raw_input = file_get_contents("php://input");
$data = json_decode($raw_input);

$id_token = $data->id_token ?? $_POST['id_token'] ?? $data->token ?? $_POST['token'] ?? null;
$access_token = $data->access_token ?? $_POST['access_token'] ?? null;
$email = null;

if ($id_token || $access_token) {
    if ($id_token) {
        $url = "https://oauth2.googleapis.com/tokeninfo?id_token=" . urlencode($id_token);
    } else {
        $url = "https://oauth2.googleapis.com/tokeninfo?access_token=" . urlencode($access_token);
    }

    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_TIMEOUT, 15);
    $response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($http_code !== 200) {
        sendResponse(false, "Invalid Google Token (verification failed)", null, 401);
        exit();
    }

    $token_data = json_decode($response, true);
    if (!$token_data || !isset($token_data['email'])) {
        sendResponse(false, "Failed to parse Google Token data", null, 401);
        exit();
    }

    // Verify audience starts with our project client ID prefix
    // For id_token it is 'aud', for access_token it is 'audience' or 'issued_to'
    $aud = $token_data['aud'] ?? $token_data['audience'] ?? $token_data['issued_to'] ?? '';
    if (strpos($aud, "907286443175-") !== 0) {
        sendResponse(false, "Google Client ID mismatch", null, 401);
        exit();
    }

    // Verify email is verified
    $email_verified = $token_data['email_verified'] ?? $token_data['verified_email'] ?? 'false';
    if ($email_verified !== 'true' && $email_verified !== true) {
        sendResponse(false, "Google email address is not verified", null, 401);
        exit();
    }

    $email = trim($token_data['email']);
} else {
    sendResponse(false, "Authentication requires a valid Google ID token or Access Token.", null, 401);
    exit();
}

$email = trim($email);
error_log("GOOGLE_LOGIN_EMAIL: '" . $email . "'");

try {
    if ($db === null) {
        sendResponse(false, "Database connection failed", null, 500);
        exit();
    }

    // 1. Search in users table strictly by email in database
    $query = "SELECT u.id, u.full_name, u.username as register_no, u.role, u.conduct, u.conduct_remarks, u.Status, u.HostelType, u.RoomType as u_room_type,
                     p.personal_phone as phone, p.room_allocation, p.institution, p.hostel_name as profile_hostel, p.address, p.dob, COALESCE(NULLIF(p.profile_pic, ''), NULLIF(u.profileimage, ''), '') as profile_pic,
                     p.valid_from, p.valid_to, u.biometric_id, COALESCE(p.warden, rgd.warden_name) as warden,
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
              WHERE LOWER(TRIM(u.email)) = LOWER(TRIM(:email)) LIMIT 0,1";

    $stmt = $db->prepare($query);
    $stmt->bindParam(':email', $email);
    $stmt->execute();

    if ($stmt->rowCount() > 0) {
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        // Role strictly comes from the database row
        $userRole = strtolower(trim($row['role'] ?? ''));
        if ($userRole === 'super_admin') {
            $row['role'] = 'super_admin';
            $row['Status'] = 'Active';
        } else if ($userRole === 'developer') {
            $row['role'] = 'developer';
            $row['Status'] = 'Active';
        }

        if (isset($row['Status']) && (strtolower($row['Status']) == 'inactive' || $row['Status'] == '0') && $row['role'] !== 'admin' && $row['role'] !== 'super_admin') {
            logAudit($row['id'], $row['register_no'], $row['role'], 'LOGIN_FAILED', 'Authentication', null, [
                'registration_no' => $row['register_no'],
                'timestamp' => date('Y-m-d H:i:s'),
                'ip_address' => getClientIp(),
                'source' => 'Google Login',
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
        if ($userRole === 'super_admin') {
            $final_role = 'super_admin';
        } else if ($userRole === 'developer') {
            $final_role = 'developer';
        } else if (!in_array(strtolower($row['role']), ['student', 'parent', 'admin'])) {
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

        // Resolve available_roles for dual-role access ONLY if explicitly assigned multiple roles in mapping_staff
        $available_roles = [strtolower($final_role)];
        if ($final_role === 'super_admin') {
            $available_roles = ['super_admin'];
        } else if ($final_role === 'developer') {
            $available_roles = ['developer'];
        } else if (in_array(strtolower($final_role), ['warden', 'maintenance', 'security', 'it', 'staff'])) {
            $bio_check = trim($row['register_no']);
            
            $mapRolesStmt = $db->prepare("SELECT DISTINCT LOWER(TRIM(role)) FROM mapping_staff WHERE (staff_bio_id = :bio OR username = :uname) AND role IS NOT NULL AND role != ''");
            $mapRolesStmt->execute([':bio' => $bio_check, ':uname' => $bio_check]);
            $assignedRoles = $mapRolesStmt->fetchAll(PDO::FETCH_COLUMN);

            foreach ($assignedRoles as $ar) {
                $cleanRole = strtolower(trim($ar));
                if (in_array($cleanRole, ['warden', 'maintenance', 'security', 'it']) && !in_array($cleanRole, $available_roles)) {
                    $available_roles[] = $cleanRole;
                }
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
            "valid_from" => (!empty($row['valid_from']) && $row['valid_from'] != '0000-00-00') ? $row['valid_from'] : null,
            "valid_to" => (!empty($row['valid_to']) && $row['valid_to'] != '0000-00-00') ? $row['valid_to'] : null,
            "renewal_date" => (!empty($row['renewal_date']) && $row['renewal_date'] != '0000-00-00') ? $row['renewal_date'] : (!empty($row['valid_to']) && $row['valid_to'] != '0000-00-00' ? $row['valid_to'] : null),
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
            "check_in_date" => $row['valid_from'],
            "renewal_date" => $row['valid_to'],
            "hostel_type" => $row['HostelType'] ?? 'Boys',
            "token" => generateJWT($row['id'], $row['register_no'], $final_role)
        ];

        // Attach Temporary Stay details ONLY for guests or temporary stay accounts
        try {
            $isTempUser = ($final_role === 'guest' || strpos($row['register_no'], 'TEMP_') === 0 || strpos($row['register_no'], 'TEMP-') === 0);
            if ($isTempUser && !empty($email)) {
                $stmtTsr = $db->prepare("SELECT * FROM temporary_stay_requests WHERE LOWER(email) = LOWER(:email) ORDER BY id DESC LIMIT 1");
                $stmtTsr->execute([':email' => $email]);
                $tsrRow = $stmtTsr->fetch(PDO::FETCH_ASSOC);
                if ($tsrRow) {
                    if (!empty($tsrRow['hold_expires_at']) && $tsrRow['hold_status'] === 'held') {
                        $rem = strtotime($tsrRow['hold_expires_at']) - time();
                        $tsrRow['hold_remaining_seconds'] = max(0, $rem);
                    }
                    $user_data['temporary_stay_request'] = $tsrRow;
                    $user_data['role'] = 'guest';
                    if (!empty($tsrRow['room_no']) && ($user_data['room_no'] === 'N/A' || empty($user_data['room_no']))) {
                        $user_data['room_no'] = $tsrRow['room_no'];
                        $user_data['room_code'] = $tsrRow['room_code'] ?? $tsrRow['room_no'];
                        $user_data['room_allocation'] = $tsrRow['room_no'];
                    }
                    if (!empty($tsrRow['hostel_name']) && ($user_data['hostel_name'] === 'N/A' || empty($user_data['hostel_name']))) {
                        $user_data['hostel_name'] = $tsrRow['hostel_name'];
                    }
                    if (!empty($tsrRow['amount'])) {
                        $user_data['total_fee'] = (float)$tsrRow['amount'];
                        $user_data['room_amount'] = (float)$tsrRow['amount'];
                        $user_data['renew_amount'] = (float)$tsrRow['amount'];
                    }
                    if (!empty($tsrRow['warden_name'])) {
                        $user_data['warden'] = $tsrRow['warden_name'];
                    }
                    if (!empty($tsrRow['from_date'])) {
                        $user_data['valid_from'] = $tsrRow['from_date'];
                        $user_data['check_in_date'] = $tsrRow['from_date'];
                    }
                    if (!empty($tsrRow['to_date'])) {
                        $user_data['valid_to'] = $tsrRow['to_date'];
                        $user_data['renewal_date'] = $tsrRow['to_date'];
                        $nowDay = strtotime(date('Y-m-d'));
                        $toDay = strtotime($tsrRow['to_date']);
                        $calcDays = (int)(($toDay - $nowDay) / 86400);
                        $user_data['remaining_days'] = $calcDays > 0 ? $calcDays : (int)($tsrRow['duration_value'] ?? 1);
                    }
                }
            }
        } catch (Exception $eTsr) {}
        
        logActivity($row['id'], $row['register_no'], $final_role, 'LOGIN', 'users', null, ['login_time' => date('Y-m-d H:i:s')]);
        logAudit($row['id'], $row['register_no'], $final_role, 'LOGIN_SUCCESS', 'Authentication', null, [
            'registration_no' => $row['register_no'],
            'timestamp' => date('Y-m-d H:i:s'),
            'ip_address' => getClientIp(),
            'source' => 'Google Login'
        ]);
        sendResponse(true, "Login successful", $user_data);
        exit();
    }

    // 2. Search in staff_users table
    $stmtStaff = $db->prepare("SELECT * FROM staff_users WHERE email = :email LIMIT 0,1");
    $stmtStaff->bindParam(':email', $email);
    $stmtStaff->execute();

    if ($stmtStaff->rowCount() > 0) {
        $staffRow = $stmtStaff->fetch(PDO::FETCH_ASSOC);
        if ($staffRow['is_active'] != 1) {
            sendResponse(false, "Your account is inactive.", null, 403);
            exit();
        }

        // Check if they have a mapped role in mapping_staff
        $mappedRoleStmt = $db->prepare("SELECT role FROM mapping_staff WHERE staff_bio_id = :bio_id OR username = :username");
        $mappedRoleStmt->execute([':bio_id' => $staffRow['bio_id'], ':username' => $staffRow['bio_id']]);
        $mappedRoles = $mappedRoleStmt->fetchAll(PDO::COLUMN_META); // Wait, mapping_staff role is fetchAll(PDO::FETCH_COLUMN)
        
        $mappedRoleStmt = $db->prepare("SELECT role FROM mapping_staff WHERE staff_bio_id = :bio_id OR username = :username");
        $mappedRoleStmt->execute([':bio_id' => $staffRow['bio_id'], ':username' => $staffRow['bio_id']]);
        $mappedRoles = $mappedRoleStmt->fetchAll(PDO::FETCH_COLUMN);

        $final_role = strtolower($staffRow['role']);
        if (!empty($mappedRoles)) {
            $roles_lower = array_map('strtolower', $mappedRoles);
            if (in_array('it_department', $roles_lower) || in_array('it', $roles_lower)) {
                $final_role = 'it_department';
            } elseif (in_array('warden', $roles_lower)) {
                $final_role = 'warden';
            } elseif (in_array('security', $roles_lower)) {
                $final_role = 'security';
            } elseif (in_array('maintenance', $roles_lower)) {
                $final_role = 'maintenance';
            } else {
                $final_role = $roles_lower[0];
            }
        }

        $user_data = [
            "id" => $staffRow['id'],
            "username" => $staffRow['bio_id'],
            "full_name" => $staffRow['name'],
            "register_no" => $staffRow['bio_id'],
            "phone" => $staffRow['phone'] ?? '',
            "role" => $final_role,
            "token" => generateJWT($staffRow['id'], $staffRow['bio_id'], $final_role)
        ];
        
        logAudit($staffRow['id'], $staffRow['bio_id'], $final_role, 'LOGIN_SUCCESS', 'Authentication', null, [
            'registration_no' => $staffRow['bio_id'],
            'timestamp' => date('Y-m-d H:i:s'),
            'ip_address' => getClientIp(),
            'source' => 'Google Staff Login'
        ]);
        sendResponse(true, "Login successful", $user_data);
        exit();
    }

    // 3. Search in vstudy_payments table (auto-student creation if paid but has no user account)
    $stmtPay = $db->prepare("SELECT * FROM vstudy_payments WHERE email = :email LIMIT 0,1");
    $stmtPay->bindParam(':email', $email);
    $stmtPay->execute();

    if ($stmtPay->rowCount() > 0) {
        $payRow = $stmtPay->fetch(PDO::FETCH_ASSOC);
        $roll_number = $payRow['roll_number'];

        // Check if user already exists under this roll_number (username)
        $checkUserStmt = $db->prepare("SELECT id FROM users WHERE username = :username LIMIT 0,1");
        $checkUserStmt->execute([':username' => $roll_number]);

        if ($checkUserStmt->rowCount() > 0) {
            $existingUser = $checkUserStmt->fetch(PDO::FETCH_ASSOC);
            $userId = $existingUser['id'];

            // Update their email in users
            $updateUserEmailStmt = $db->prepare("UPDATE users SET email = :email WHERE id = :id");
            $updateUserEmailStmt->execute([':email' => $email, ':id' => $userId]);

            // Update their email in profile if profile exists
            $updateProfileEmailStmt = $db->prepare("UPDATE profile SET email = :email WHERE user_id = :user_id");
            $updateProfileEmailStmt->execute([':email' => $email, ':user_id' => $userId]);

            // Fetch updated user details
            $stmt = $db->prepare($query);
            $stmt->bindParam(':email', $email);
            $stmt->execute();
            if ($stmt->rowCount() > 0) {
                $row = $stmt->fetch(PDO::FETCH_ASSOC);
            } else {
                sendResponse(false, "User mapping failed after sync", null, 500);
                exit();
            }

            // Construct user_data and return success response
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
                "warden"           => $row['warden'] ?? '',
                "group_name"       => $row['floor_name'] ?? $row['group_name'] ?? '',
                "floor_name"       => $row['floor_name'] ?? $row['group_name'] ?? '',
                "room_no"          => $row['hr_room_no'] ?? 'N/A',
                "room_code"        => $row['room_code'] ?? $row['room_allocation'] ?? 'N/A',
                "block"            => $row['block'] ?? 'N/A',
                "wing"             => (!empty($row['floor_name']) && !empty($row['wing_name'])) ? ($row['floor_name'] . ' - ' . $row['wing_name']) : 'N/A',
                "room_type"        => $row['room_type'] ?? 'N/A',
                "room_facility"    => $row['room_facility'] ?? 'NON AC',
                "room_bath_attached" => $row['room_bath_attached'] ?? 'No',
                "check_in_date"    => $row['valid_from'] ?? '0000-00-00',
                "renewal_date"     => $row['valid_to'] ?? '0000-00-00',
                "hostel_type"      => $row['HostelType'] ?? 'Boys',
                "token"            => generateJWT($row['id'], $row['register_no'], $row['role'])
            ];

            logActivity($row['id'], $row['register_no'], $row['role'], 'LOGIN', 'users', null, ['login_time' => date('Y-m-d H:i:s')]);
            logAudit($row['id'], $row['register_no'], $row['role'], 'LOGIN_SUCCESS', 'Authentication', null, [
                'registration_no' => $row['register_no'],
                'timestamp' => date('Y-m-d H:i:s'),
                'ip_address' => getClientIp(),
                'source' => 'Google Login Sync Update'
            ]);
            sendResponse(true, "Login successful", $user_data);
            exit();
        }

        // Create Student User
        $hashedPassword = password_hash('welcome123', PASSWORD_BCRYPT);
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
            'source' => 'Google Auto-Student Created'
        ];

        logAudit($newUserId, $payRow['roll_number'], 'student', 'AUTO_STUDENT_CREATED', 'Google Login Sync', null, $logMeta);
        logAudit($newUserId, $payRow['roll_number'], 'student', 'FIRST_STUDENT_LOGIN', 'Google Login Sync', null, $logMeta);
        logAudit($newUserId, $payRow['roll_number'], 'student', 'LOGIN_SUCCESS', 'Google Login Sync', null, $logMeta);
        logActivity($newUserId, $payRow['roll_number'], 'student', 'LOGIN', 'users', null, ['login_time' => date('Y-m-d H:i:s')]);

        // Fetch newly created user information
        $stmt = $db->prepare($query);
        $stmt->bindParam(':email', $email);
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
            "valid_from"       => (!empty($row['valid_from']) && $row['valid_from'] != '0000-00-00') ? $row['valid_from'] : null,
            "valid_to"         => (!empty($row['valid_to']) && $row['valid_to'] != '0000-00-00') ? $row['valid_to'] : null,
            "renewal_date"     => (!empty($row['renewal_date']) && $row['renewal_date'] != '0000-00-00') ? $row['renewal_date'] : (!empty($row['valid_to']) && $row['valid_to'] != '0000-00-00' ? $row['valid_to'] : null),
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
    }

    // 3.5. On-Demand Live API Sync Fallback
    // If not found in local DB, attempt a live fetch directly from external VStudy APIs
    if (syncStudentOnDemand($email, $db)) {
        // Try querying users table again after live sync
        $stmt = $db->prepare($query);
        $stmt->bindParam(':email', $email);
        $stmt->execute();

        if ($stmt->rowCount() > 0) {
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            $room_no = $row['hr_room_no'] ?? $row['room_allocation'] ?? 'N/A';
            $block = $row['block'] ?? 'N/A';
            $hostel = $row['room_hostel'] ?? $row['profile_hostel'] ?? 'N/A';

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
                "hostel_name"      => $hostel,
                "room_allocation"  => $row['room_allocation'] ?? 'N/A',
                "profile_pic"      => $row['profile_pic'],
                "valid_from"       => $row['valid_from'] ?? '0000-00-00',
                "valid_to"         => $row['valid_to'] ?? '0000-00-00',
                "conduct"          => $row['conduct'] ?? 'Good',
                "conduct_remarks"  => $row['conduct_remarks'] ?? '',
                "biometric_id"     => $row['biometric_id'],
                "warden"           => $row['warden'] ?? '',
                "group_name"       => $row['floor_name'] ?? $row['group_name'] ?? '',
                "floor_name"       => $row['floor_name'] ?? $row['group_name'] ?? '',
                "room_no"          => $room_no,
                "room_code"        => $row['room_code'] ?? $row['room_allocation'] ?? 'N/A',
                "block"            => $block,
                "wing"             => (!empty($row['floor_name']) && !empty($row['wing_name'])) ? ($row['floor_name'] . ' - ' . $row['wing_name']) : 'N/A',
                "room_type"        => $row['room_type'] ?? 'N/A',
                "room_facility"    => $row['room_facility'] ?? 'NON AC',
                "room_bath_attached" => $row['room_bath_attached'] ?? 'No',
                "check_in_date"    => $row['valid_from'] ?? '0000-00-00',
                "renewal_date"     => $row['valid_to'] ?? '0000-00-00',
                "hostel_type"      => $row['HostelType'] ?? 'Boys',
                "token"            => generateJWT($row['id'], $row['register_no'], $row['role'])
            ];

            logActivity($row['id'], $row['register_no'], $row['role'], 'LOGIN', 'users', null, ['login_time' => date('Y-m-d H:i:s')]);
            logAudit($row['id'], $row['register_no'], $row['role'], 'LOGIN_SUCCESS', 'Authentication', null, [
                'registration_no' => $row['register_no'],
                'timestamp' => date('Y-m-d H:i:s'),
                'ip_address' => getClientIp(),
                'source' => 'Google Login On-Demand Sync'
            ]);
            sendResponse(true, "Login successful", $user_data);
            exit();
        }
    }

    // 3.8. Search in temporary_stay_requests (Guest / Short Stay resident)
    $stmtTsrOnly = $db->prepare("SELECT * FROM temporary_stay_requests WHERE LOWER(email) = LOWER(:email) ORDER BY id DESC LIMIT 1");
    $stmtTsrOnly->execute([':email' => $email]);
    if ($stmtTsrOnly->rowCount() > 0) {
        $tsr = $stmtTsrOnly->fetch(PDO::FETCH_ASSOC);

        $reqId = $tsr['request_id'];
        $fullName = !empty($tsr['full_name']) ? $tsr['full_name'] : 'Guest Resident';
        $phone = $tsr['phone'] ?? '';
        $gender = $tsr['gender'] ?? 'Male';
        $genderType = (stripos($gender, 'female') !== false || stripos($tsr['hostel_name'], 'girls') !== false) ? 'Girls' : 'Boys';
        $hostel = $tsr['hostel_name'] ?? 'Temporary Hostel';
        $roomType = $tsr['room_type'] ?? 'Standard Room';
        $roomNo = $tsr['room_no'] ?? 'Pending Allocation';
        $fromDate = $tsr['from_date'] ?? date('Y-m-d');
        $toDate = $tsr['to_date'] ?? date('Y-m-d', strtotime('+3 days'));
        $dummyPass = password_hash('welcome123', PASSWORD_BCRYPT);

        // Check or create user in users table
        $checkUser = $db->prepare("SELECT id, username FROM users WHERE LOWER(email) = LOWER(?) LIMIT 1");
        $checkUser->execute([$email]);
        $existingU = $checkUser->fetch(PDO::FETCH_ASSOC);

        if ($existingU) {
            $existingUid = $existingU['id'];
            $reqId = $existingU['username'];
        } else {
            $insU = $db->prepare("INSERT INTO users (
                username, password, full_name, email, role, phone_number, HostelName, HostelType, RoomType, RoomId, Status, is_active, Gender, Academic, IsBiometric
            ) VALUES (
                :username, :password, :full_name, :email, 'guest', :phone, :hostel_name, :hostel_type, :room_type, :room_id, 'active', 1, :gender, 'Temporary Stay', 'No'
            )");
            $insU->execute([
                ':username' => $reqId,
                ':password' => $dummyPass,
                ':full_name' => $fullName,
                ':email' => $email,
                ':phone' => $phone,
                ':hostel_name' => $hostel,
                ':hostel_type' => $genderType,
                ':room_type' => $roomType,
                ':room_id' => $roomNo,
                ':gender' => $gender
            ]);
            $existingUid = $db->lastInsertId();

            $insP = $db->prepare("INSERT INTO profile (
                user_id, reg_no, full_name, email, personal_phone, hostel_name, room_allocation, valid_from, valid_to, profile_pic
            ) VALUES (
                :user_id, :reg_no, :full_name, :email, :phone, :hostel_name, :room_no, :valid_from, :valid_to, 'profile.png'
            )");
            $insP->execute([
                ':user_id' => $existingUid,
                ':reg_no' => $reqId,
                ':full_name' => $fullName,
                ':email' => $email,
                ':phone' => $phone,
                ':hostel_name' => $hostel,
                ':room_no' => $roomNo,
                ':valid_from' => $fromDate,
                ':valid_to' => $toDate
            ]);
        }

        if (!empty($tsr['hold_expires_at']) && $tsr['hold_status'] === 'held') {
            $rem = strtotime($tsr['hold_expires_at']) - time();
            $tsr['hold_remaining_seconds'] = max(0, $rem);
        }

        $nowDay = strtotime(date('Y-m-d'));
        $toDay = strtotime($toDate);
        $calcDays = (int)(($toDay - $nowDay) / 86400);
        $remDays = $calcDays > 0 ? $calcDays : (int)($tsr['duration_value'] ?? 1);

        $user_data = [
            "id" => $existingUid,
            "username" => $reqId,
            "full_name" => $fullName,
            "register_no" => $reqId,
            "phone" => $phone,
            "email" => $email,
            "dob" => "2000-01-01",
            "address" => "Temporary Stay Resident",
            "role" => "guest",
            "institution" => "Saveetha Institute of Medical and Technical Sciences",
            "hostel_name" => $hostel,
            "room_allocation" => $roomNo,
            "profile_pic" => "profile.png",
            "valid_from" => $fromDate,
            "valid_to" => $toDate,
            "conduct" => "Good",
            "conduct_remarks" => "",
            "biometric_id" => "N/A",
            "warden" => $tsr['warden_name'] ?? "",
            "group_name" => "",
            "floor_name" => "",
            "room_no" => $roomNo,
            "room_code" => $tsr['room_code'] ?? $roomNo,
            "block" => "N/A",
            "wing" => "N/A",
            "room_type" => $roomType,
            "room_facility" => "Standard",
            "room_bath_attached" => "No",
            "room_amount" => (float)($tsr['amount'] ?? 0),
            "room_food" => 0,
            "room_caution" => 0,
            "total_fee" => (float)($tsr['amount'] ?? 0),
            "renew_amount" => (float)($tsr['amount'] ?? 0),
            "check_in_date" => $fromDate,
            "renewal_date" => $toDate,
            "remaining_days" => $remDays,
            "hostel_type" => $genderType,
            "temporary_stay_request" => $tsr,
            "token" => generateJWT($existingUid, $reqId, 'guest')
        ];

        logActivity($existingUid, $reqId, 'guest', 'LOGIN', 'users', null, ['login_time' => date('Y-m-d H:i:s')]);
        logAudit($existingUid, $reqId, 'guest', 'LOGIN_SUCCESS', 'Authentication', null, [
            'registration_no' => $reqId,
            'timestamp' => date('Y-m-d H:i:s'),
            'ip_address' => getClientIp(),
            'source' => 'Google Temporary Stay Login'
        ]);

        sendResponse(true, "Login successful", $user_data);
        exit();
    }

    // 3.8. Search in parent_users table (Parent Google Login)
    $parent_query = "SELECT p.*, s.full_name as student_name, s.username as student_username, s.id as std_id
                     FROM parent_users p
                     LEFT JOIN parent_student_map psm ON (CONVERT(p.parent_id USING utf8mb4) = CONVERT(psm.parent_id USING utf8mb4))
                     LEFT JOIN users s ON (CONVERT(psm.student_id USING utf8mb4) = CONVERT(s.username USING utf8mb4))
                     WHERE LOWER(CONVERT(COALESCE(p.email, '') USING utf8mb4)) = LOWER(CONVERT(:email USING utf8mb4)) LIMIT 0,1";
    $p_stmt = $db->prepare($parent_query);
    $p_stmt->bindParam(':email', $email);
    $p_stmt->execute();

    if ($p_stmt->rowCount() > 0) {
        $p_row = $p_stmt->fetch(PDO::FETCH_ASSOC);

        $parent_name = !empty($p_row['name']) ? $p_row['name'] : ("Parent of " . ($p_row['student_name'] ?? 'Student'));

        $user_data = [
            "id" => $p_row['id'],
            "username" => $p_row['parent_id'],
            "register_no" => $p_row['parent_id'],
            "full_name" => $parent_name,
            "phone" => $p_row['contact'] ?? '',
            "email" => $p_row['email'] ?? $email,
            "role" => 'parent',
            "profile_pic" => "",
            "linked_student_id" => $p_row['std_id'],
            "linked_student_username" => $p_row['student_username'],
            "linked_student_name" => $p_row['student_name'],
            "token" => generateJWT($p_row['id'], $p_row['parent_id'], 'parent')
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
            'source' => 'Google Parent Login'
        ]);
        sendResponse(true, "Parent Login successful", $user_data);
        exit();
    }

    // 4. Not found anywhere

    logAudit(null, $email, 'student', 'LOGIN_FAILED', 'Authentication', null, [
        'registration_no' => $email,
        'timestamp' => date('Y-m-d H:i:s'),
        'ip_address' => getClientIp(),
        'source' => 'Google Login',
        'reason' => 'Email not found'
    ]);
    sendResponse(false, "No VStay account was found for this email. Use email which u have used to pay the hostel fee.", null, 404);
} catch (Exception $e) {
    sendResponse(false, "Server error: " . $e->getMessage(), null, 500);
}
?>
