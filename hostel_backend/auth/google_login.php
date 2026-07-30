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
    // Fallback email for testing
    $email = $data->email ?? $_POST['email'] ?? $_GET['email'] ?? null;
}

if (!$email) {
    sendResponse(false, "ID token, Access Token or Email is required", null, 400);
    exit();
}

$email = trim($email);

try {
    if ($db === null) {
        sendResponse(false, "Database connection failed", null, 500);
        exit();
    }

    // 1. Search in users table (Warden / Student / Admin)
    $query = "SELECT u.id, u.full_name, u.username as register_no, u.role, u.conduct, u.conduct_remarks, u.Status, u.HostelType,
                     p.personal_phone as phone, p.room_allocation, p.institution, p.hostel_name as profile_hostel, p.address, p.dob, p.profile_pic,
                     p.valid_from, p.valid_to, u.biometric_id,
                     rgd.room_number as hr_room_no, rgd.hostel_name as block, rgd.group_name as floor_name, '' as wing_name, rgd.hostel_name as room_hostel, rgd.room_type as room_type,
                     '' as room_facility, '' as room_bath_attached, rgd.room_number as room_code
              FROM users u
              LEFT JOIN profile p ON u.username = p.reg_no
              LEFT JOIN rooms_groups_details rgd ON (rgd.room_number = p.room_allocation)
              WHERE u.email = :email LIMIT 0,1";

    $stmt = $db->prepare($query);
    $stmt->bindParam(':email', $email);
    $stmt->execute();

    if ($stmt->rowCount() > 0) {
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if (isset($row['Status']) && (strtolower($row['Status']) == 'inactive' || $row['Status'] == '0') && $row['role'] !== 'admin') {
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

        $user_data = [
            "id" => $row['id'],
            "username" => $row['register_no'],
            "full_name" => $row['full_name'],
            "register_no" => $row['register_no'],
            "phone" => $row['phone'],
            "dob" => $row['dob'],
            "address" => $row['address'],
            "role" => $final_role,
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
            "room_code" => $row['room_code'] ?? $row['room_allocation'] ?? 'N/A',
            "block" => $block,
            "wing" => $wing,
            "room_type" => $row['room_type'],
            "room_facility" => $row['room_facility'] ?? 'NON AC',
            "room_bath_attached" => $row['room_bath_attached'] ?? 'No',
            "check_in_date" => $row['valid_from'],
            "renewal_date" => $row['valid_to'],
            "hostel_type" => $row['HostelType'] ?? 'Boys',
            "token" => generateJWT($row['id'], $row['register_no'], $final_role)
        ];
        
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
            if (in_array('warden', $roles_lower)) {
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
    }

    // 4. Not found anywhere
    logAudit(null, $email, 'student', 'LOGIN_FAILED', 'Authentication', null, [
        'registration_no' => $email,
        'timestamp' => date('Y-m-d H:i:s'),
        'ip_address' => getClientIp(),
        'source' => 'Google Login',
        'reason' => 'Email not found'
    ]);
    sendResponse(false, "Email not found. Please contact administration.", null, 404);
} catch (Exception $e) {
    sendResponse(false, "Server error: " . $e->getMessage(), null, 500);
}
?>
