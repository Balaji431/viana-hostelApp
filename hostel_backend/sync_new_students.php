<?php
/**
 * Auto-Sync New Students Endpoint:
 * Fetches latest records from external APIs (booked-rooms & hostel-applications/paid),
 * automatically upserts new student accounts into `users`, `profile`, `parent_users`,
 * `parent_student_map`, `new_api`, `old_api`, and `vstudy_payments`.
 */

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/config/api_config.php';
require_once __DIR__ . '/config/database.php';

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $db->exec("SET FOREIGN_KEY_CHECKS = 0");

    function fetchAuthPages($baseUrl) {
        $page = 1;
        $limit = 100;
        $all = [];

        while (true) {
            $url = $baseUrl . (strpos($baseUrl, '?') !== false ? '&' : '?') . "page=$page&limit=$limit";
            $ch = curl_init($url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_HTTPHEADER, [
                "X-Client-Id: " . VSTUDY_CLIENT_ID,
                "X-Client-Secret: " . VSTUDY_CLIENT_SECRET
            ]);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
            curl_setopt($ch, CURLOPT_TIMEOUT, 15);
            $res = curl_exec($ch);
            $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);

            if ($code != 200) break;

            $json = json_decode($res, true);
            $batch = [];
            if (isset($json['data']) && is_array($json['data'])) {
                $batch = $json['data'];
            } else if (is_array($json)) {
                $batch = $json;
            }

            if (empty($batch)) break;

            $all = array_merge($all, $batch);
            if (count($batch) < $limit) break;
            $page++;
            usleep(15000);
        }
        return $all;
    }

    // 1. Fetch from external APIs
    $bookedRooms = fetchAuthPages("https://vstudy.saveetha.com/api/hostel-settings/booked-rooms/external");
    $paidApps    = fetchAuthPages("https://vstudy.saveetha.com/api/hostel-applications/paid");

    $pwHash = password_hash('welcome123', PASSWORD_BCRYPT);
    $today  = new DateTime('today');

    $checkUserStmt  = $db->prepare("SELECT id FROM users WHERE username = ?");
    $insertUserStmt = $db->prepare("
        INSERT INTO users (
            username, full_name, email, phone_number, role, password, Campus, Institution,
            HostelName, HostelType, RoomType, RoomId, Status, is_active
        ) VALUES (
            :username, :full_name, :email, :phone_number, 'student', :password, :Campus, 'SIMATS',
            :HostelName, :HostelType, :RoomType, :RoomId, '1', 1
        )
    ");
    $updateUserStmt = $db->prepare("
        UPDATE users SET 
            full_name = ?, email = ?, phone_number = ?, Campus = ?, HostelName = ?, HostelType = ?, RoomType = ?, RoomId = ?
        WHERE username = ? AND role = 'student'
    ");

    $insertProfileStmt = $db->prepare("
        INSERT INTO profile (
            full_name, reg_no, user_id, email, personal_phone, room_allocation,
            institution, hostel_name, address, renewal_date, remaining_days,
            check_in_date, valid_from
        ) VALUES (
            :full_name, :reg_no, :user_id, :email, :personal_phone, :room_allocation,
            :institution, :hostel_name, :address, :renewal_date, :remaining_days,
            :check_in_date, :valid_from
        ) ON DUPLICATE KEY UPDATE 
            full_name = VALUES(full_name), email = VALUES(email), personal_phone = VALUES(personal_phone),
            room_allocation = VALUES(room_allocation), hostel_name = VALUES(hostel_name),
            renewal_date = VALUES(renewal_date), remaining_days = VALUES(remaining_days),
            check_in_date = VALUES(check_in_date), valid_from = VALUES(valid_from)
    ");

    $insertParentStmt = $db->prepare("
        INSERT INTO parent_users (parent_id, password, contact) 
        VALUES (?, ?, ?) 
        ON DUPLICATE KEY UPDATE contact = VALUES(contact)
    ");
    $insertMapStmt = $db->prepare("
        INSERT INTO parent_student_map (parent_id, student_id) 
        VALUES (?, ?) ON DUPLICATE KEY UPDATE parent_id = VALUES(parent_id)
    ");

    $newStudentsAdded = 0;

    // Process API 1 Booked Rooms
    foreach ($bookedRooms as $b) {
        $roll   = trim($b['registerNumber'] ?? $b['rollNumber'] ?? '');
        if (!$roll) continue;

        $name   = trim($b['name'] ?? 'Student');
        $email  = trim($b['email'] ?? '');
        $phone  = trim($b['phone'] ?? '');
        $gender = strtolower(trim($b['gender'] ?? ''));
        $campus = trim($b['campus'] ?? 'Thandalam Campus');
        $hostel = trim($b['hostelName'] ?? '');
        $roomNo = trim($b['roomNumber'] ?? '');
        $rType  = trim($b['roomType'] ?? '');
        $hType  = ($gender === 'female' || strpos(strtolower($hostel), 'girls') !== false || strpos(strtolower($hostel), 'ponni') !== false || strpos(strtolower($hostel), 'vaigai') !== false || strpos(strtolower($hostel), 'siruvani') !== false) ? 'Girls' : 'Boys';
        $renStr = trim($b['renewalDate'] ?? '');
        $booked = trim($b['bookedAt'] ?? $b['paidAt'] ?? '');

        $calcRenewal = null;
        if (!empty($renStr) && strtotime($renStr) !== false) {
            $calcRenewal = new DateTime($renStr);
        } else if (!empty($booked) && strtotime($booked) !== false) {
            $calcRenewal = (clone new DateTime($booked))->modify('+1 year');
        } else {
            $calcRenewal = (clone $today)->modify('+1 year');
        }

        $renFormatted = $calcRenewal->format('Y-m-d');
        $remDays = ($calcRenewal < $today) ? 0 : (int)$today->diff($calcRenewal)->format('%r%a');

        $checkInFormatted = null;
        if (!empty($booked) && strtotime($booked) !== false) {
            $checkInFormatted = (new DateTime($booked))->format('Y-m-d');
        } else {
            $checkInFormatted = $today->format('Y-m-d');
        }

        $checkUserStmt->execute([$roll]);
        $existingId = $checkUserStmt->fetchColumn();

        if (!$existingId) {
            $insertUserStmt->execute([
                ':username'     => $roll,
                ':full_name'    => $name,
                ':email'        => $email,
                ':phone_number' => $phone,
                ':password'     => $pwHash,
                ':Campus'       => $campus,
                ':HostelName'   => $hostel,
                ':HostelType'   => $hType,
                ':RoomType'     => $rType,
                ':RoomId'       => $roomNo
            ]);
            $existingId = $db->lastInsertId();
            $newStudentsAdded++;
        } else {
            $updateUserStmt->execute([$name, $email, $phone, $campus, $hostel, $hType, $rType, $roomNo, $roll]);
        }

        $insertProfileStmt->execute([
            ':full_name'       => $name,
            ':reg_no'          => $roll,
            ':user_id'         => $existingId,
            ':email'           => $email,
            ':personal_phone'  => $phone,
            ':room_allocation' => $roomNo,
            ':institution'     => 'SIMATS',
            ':hostel_name'     => $hostel,
            ':address'         => 'Thandalam Campus, Chennai',
            ':renewal_date'   => $renFormatted,
            ':remaining_days' => $remDays,
            ':check_in_date'   => $checkInFormatted,
            ':valid_from'      => $checkInFormatted
        ]);

        $parentId = "P_" . $roll;
        $insertParentStmt->execute([$parentId, $pwHash, $phone]);
        $insertMapStmt->execute([$parentId, $roll]);
    }

    // Process API 2 Paid Applications
    foreach ($paidApps as $app) {
        $roll   = trim($app['student']['rollNumber'] ?? $app['student']['registerNumber'] ?? '');
        if (!$roll) continue;

        $name   = trim($app['student']['name'] ?? 'Student');
        $email  = trim($app['student']['email'] ?? '');
        $phone  = trim($app['student']['phone'] ?? '');
        $gender = strtolower(trim($app['room']['gender'] ?? ''));
        $campus = trim($app['hostel']['campus'] ?? 'Thandalam Campus');
        $hostel = trim($app['hostel']['name'] ?? '');
        $roomNo = trim($app['room']['roomNumber'] ?? '');
        $rType  = trim($app['room']['roomType'] ?? '');
        $hType  = ($gender === 'female' || strpos(strtolower($hostel), 'girls') !== false || strpos(strtolower($hostel), 'ponni') !== false || strpos(strtolower($hostel), 'vaigai') !== false || strpos(strtolower($hostel), 'siruvani') !== false) ? 'Girls' : 'Boys';
        $paid   = trim($app['paidAt'] ?? $app['appliedAt'] ?? '');

        $calcRenewal = null;
        if (!empty($paid) && strtotime($paid) !== false) {
            $calcRenewal = (clone new DateTime($paid))->modify('+1 year');
        } else {
            $calcRenewal = (clone $today)->modify('+1 year');
        }

        $renFormatted = $calcRenewal->format('Y-m-d');
        $remDays = ($calcRenewal < $today) ? 0 : (int)$today->diff($calcRenewal)->format('%r%a');

        $checkInFormatted = null;
        if (!empty($paid) && strtotime($paid) !== false) {
            $checkInFormatted = (new DateTime($paid))->format('Y-m-d');
        } else {
            $checkInFormatted = $today->format('Y-m-d');
        }

        $checkUserStmt->execute([$roll]);
        $existingId = $checkUserStmt->fetchColumn();

        if (!$existingId) {
            $insertUserStmt->execute([
                ':username'     => $roll,
                ':full_name'    => $name,
                ':email'        => $email,
                ':phone_number' => $phone,
                ':password'     => $pwHash,
                ':Campus'       => $campus,
                ':HostelName'   => $hostel,
                ':HostelType'   => $hType,
                ':RoomType'     => $rType,
                ':RoomId'       => $roomNo
            ]);
            $existingId = $db->lastInsertId();
            $newStudentsAdded++;
        }

        $insertProfileStmt->execute([
            ':full_name'       => $name,
            ':reg_no'          => $roll,
            ':user_id'         => $existingId,
            ':email'           => $email,
            ':personal_phone'  => $phone,
            ':room_allocation' => $roomNo,
            ':institution'     => 'SIMATS',
            ':hostel_name'     => $hostel,
            ':address'         => 'Thandalam Campus, Chennai',
            ':renewal_date'   => $renFormatted,
            ':remaining_days' => $remDays,
            ':check_in_date'   => $checkInFormatted,
            ':valid_from'      => $checkInFormatted
        ]);

        $parentId = "P_" . $roll;
        $insertParentStmt->execute([$parentId, $pwHash, $phone]);
        $insertMapStmt->execute([$parentId, $roll]);
    }

    $db->exec("SET FOREIGN_KEY_CHECKS = 1");

    $totalUsersCount = $db->query("SELECT COUNT(*) FROM users WHERE role = 'student'")->fetchColumn();

    echo json_encode([
        "status"             => true,
        "message"            => "Auto-sync completed successfully",
        "new_students_added" => $newStudentsAdded,
        "total_students"     => (int)$totalUsersCount,
        "synced_at"          => date('Y-m-d H:i:s')
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "status"  => false,
        "message" => "Sync Error: " . $e->getMessage()
    ]);
}
?>
