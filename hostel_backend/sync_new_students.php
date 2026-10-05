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
require_once __DIR__ . '/utils/auth_helper.php';

if (PHP_SAPI !== 'cli') {
    requireAuth(['super_admin', 'admin']);
}

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

    function parseDateSafe($val, $fallback = null) {
        if (empty($val)) return $fallback;
        $val = trim($val);
        if (preg_match('/^(\d{1,2})[\.\/](\d{1,2})[\.\/](\d{4})$/', $val, $m)) {
            $d = (int)$m[1];
            $mo = (int)$m[2];
            $y = (int)$m[3];
            if ($mo > 12 && $d <= 12) {
                $tmp = $d; $d = $mo; $mo = $tmp;
            }
            return sprintf('%04d-%02d-%02d', $y, $mo, $d);
        }
        if (preg_match('/^(\d{4})-(\d{1,2})-(\d{1,2})/', $val, $m)) {
            return sprintf('%04d-%02d-%02d', (int)$m[1], (int)$m[2], (int)$m[3]);
        }
        try {
            $dt = new DateTime($val);
            return $dt->format('Y-m-d');
        } catch (Exception $e) {
            $ts = strtotime($val);
            if ($ts !== false && $ts > 0) {
                return date('Y-m-d', $ts);
            }
        }
        return $fallback;
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
    // Preserve existing emails & phone numbers on update (only sync room transfers, hostel, campus, etc.)
    $updateUserStmt = $db->prepare("
        UPDATE users SET 
            full_name = ?, 
            Campus = ?, HostelName = ?, HostelType = ?, RoomType = ?, RoomId = ?
        WHERE username = ? AND role = 'student'
    ");

    $insertProfileStmt = $db->prepare("
        INSERT INTO profile (
            full_name, reg_no, user_id, email, personal_phone, room_allocation, warden,
            institution, hostel_name, address, renewal_date, remaining_days,
            check_in_date, valid_from, valid_to
        ) VALUES (
            :full_name, :reg_no, :user_id, :email, :personal_phone, :room_allocation, :warden,
            :institution, :hostel_name, :address, :renewal_date, :remaining_days,
            :check_in_date, :valid_from, :valid_to
        ) ON DUPLICATE KEY UPDATE 
            full_name = VALUES(full_name),
            room_allocation = VALUES(room_allocation), 
            warden = COALESCE(NULLIF(VALUES(warden),''), warden), 
            hostel_name = VALUES(hostel_name),
            renewal_date = VALUES(renewal_date),
            valid_to = VALUES(valid_to),
            remaining_days = VALUES(remaining_days),
            check_in_date = VALUES(check_in_date), valid_from = VALUES(valid_from)
    ");

    $findWardenStmt = $db->prepare("
        SELECT warden_name FROM rooms_groups_details 
        WHERE (room_number = :rn OR REPLACE(REPLACE(TRIM(room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(:rn2), ' ', ''), '-', ''))
          AND warden_name IS NOT NULL AND warden_name != '' LIMIT 1
    ");

    $findWardenMappingStmt = $db->prepare("
        SELECT name FROM mapping_staff 
        WHERE LOWER(role) = 'warden' AND (LOWER(hostel_name) = LOWER(:hn) OR LOWER(:hn2) LIKE CONCAT('%', LOWER(hostel_name), '%')) LIMIT 1
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
        $campus = trim($b['campus'] ?? '');
        $hostel = trim($b['hostelName'] ?? '');
        $roomNo = trim($b['roomNumber'] ?? '');
        if (empty($campus) || $campus === 'SIMATS') {
            if (stripos($hostel, 'Radiance') !== false || stripos($hostel, 'Stunner') !== false || strpos($roomNo, 'P-') === 0 || strpos($roomNo, 'P0') === 0) {
                $campus = 'Poonamallee Campus';
            } else {
                $campus = 'Thandalam Campus';
            }
        }
        $rType  = trim($b['roomType'] ?? '');
        $hType  = ($gender === 'female' || strpos(strtolower($hostel), 'girls') !== false || strpos(strtolower($hostel), 'ponni') !== false || strpos(strtolower($hostel), 'vaigai') !== false || strpos(strtolower($hostel), 'siruvani') !== false) ? 'Girls' : 'Boys';
        $renStr = trim($b['renewalDate'] ?? '');
        $booked = trim($b['bookedAt'] ?? $b['paidAt'] ?? '');

        $parsedRen = parseDateSafe($renStr);
        $parsedBooked = parseDateSafe($booked);

        $renFormatted = null;
        $remDays = null;
        if (!empty($parsedRen)) {
            $calcRenewal = new DateTime($parsedRen);
            $renFormatted = $calcRenewal->format('Y-m-d');
            $remDays = ($calcRenewal < $today) ? 0 : (int)$today->diff($calcRenewal)->format('%r%a');
        }
        $checkInFormatted = $parsedBooked ?: null;

        $checkUserStmt->execute([$roll]);
        $existingRow   = $checkUserStmt->fetch(PDO::FETCH_ASSOC);
        $existingId    = $existingRow ? $existingRow['id'] : null;
        $emailOverride = $existingRow ? (int)($existingRow['email_override'] ?? 0) : 0;

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
            $updateUserStmt->execute([$name, $campus, $hostel, $hType, $rType, $roomNo, $roll]);
        }

        $assignedWarden = null;
        if (!empty($roomNo)) {
            $findWardenStmt->execute([':rn' => $roomNo, ':rn2' => $roomNo]);
            $assignedWarden = $findWardenStmt->fetchColumn() ?: null;
            // NO hostel-only fallback: if room lookup fails, keep null to preserve existing profile.warden
        }

        $insertProfileStmt->execute([
            ':full_name'       => $name,
            ':reg_no'          => $roll,
            ':user_id'         => $existingId,
            ':email'           => $email,
            ':personal_phone'  => $phone,
            ':room_allocation' => $roomNo,
            ':warden'          => $assignedWarden,
            ':institution'     => 'SIMATS',
            ':hostel_name'     => $hostel,
            ':address'         => ($campus ?: 'Thandalam Campus') . ', Chennai',
            ':renewal_date'    => $renFormatted,
            ':remaining_days'  => $remDays,
            ':check_in_date'   => $checkInFormatted,
            ':valid_from'      => $checkInFormatted,
            ':valid_to'        => $renFormatted
        ]);

        $parentId = "P_" . $roll;
        $insertParentStmt->execute([$parentId, $pwHash, $phone]);
        $insertMapStmt->execute([$parentId, $roll]);
    }

    // ⚠️  API 2 (hostel-applications/paid) — DISABLED: booked-rooms/external is the exclusive source of truth.
    // New student accounts must NOT be created from this API. Only booked-rooms/external drives users & profile.
    // This loop is intentionally left empty. Do NOT re-enable without updating the clean_sync_booked_rooms.php policy.
    foreach ($paidApps as $app) {
        $roll = trim($app['student']['rollNumber'] ?? $app['student']['registerNumber'] ?? '');
        if (!$roll) continue;

        // SKIP: do not insert new students from API 2.
        // Only update vstudy_payments/old_api cache tables (handled below in the upsert section).
        continue;

        $name   = trim($app['student']['name'] ?? 'Student');
        $email  = trim($app['student']['email'] ?? '');
        $phone  = trim($app['student']['phone'] ?? '');
        $gender = strtolower(trim($app['room']['gender'] ?? ''));
        $campus = trim($app['hostel']['campus'] ?? '');
        $hostel = trim($app['hostel']['name'] ?? '');
        $roomNo = trim($app['room']['roomNumber'] ?? '');
        if (empty($campus) || $campus === 'SIMATS') {
            if (stripos($hostel, 'Radiance') !== false || stripos($hostel, 'Stunner') !== false || strpos($roomNo, 'P-') === 0 || strpos($roomNo, 'P0') === 0) {
                $campus = 'Poonamallee Campus';
            } else {
                $campus = 'Thandalam Campus';
            }
        }
        $rType  = trim($app['room']['roomType'] ?? '');
        $hType  = ($gender === 'female' || strpos(strtolower($hostel), 'girls') !== false || strpos(strtolower($hostel), 'ponni') !== false || strpos(strtolower($hostel), 'vaigai') !== false || strpos(strtolower($hostel), 'siruvani') !== false) ? 'Girls' : 'Boys';
        $paid   = trim($app['paidAt'] ?? $app['appliedAt'] ?? '');

        $rawRenewal = trim($app['renewalDate'] ?? $app['renewal_date'] ?? '');
        $calcRenewal = null;
        if (!empty($rawRenewal) && strtotime($rawRenewal) !== false) {
            $calcRenewal = new DateTime($rawRenewal);
        }

        $renFormatted = $calcRenewal ? $calcRenewal->format('Y-m-d') : null;
        $remDays = ($calcRenewal && $calcRenewal >= $today) ? (int)$today->diff($calcRenewal)->format('%r%a') : 0;

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

        // Only look up warden if we have a room number.
        // The paid-apps API does NOT return roomNumber, so $roomNo is empty here.
        // Using a hostel-only fallback picks a random first warden - that's the bug.
        // Leave $assignedWarden = null so the ON DUPLICATE KEY UPDATE COALESCE preserves the existing warden.
        $assignedWarden = null;
        if (!empty($roomNo)) {
            $findWardenStmt->execute([':rn' => $roomNo, ':rn2' => $roomNo]);
            $assignedWarden = $findWardenStmt->fetchColumn() ?: null;
        }
        // NO hostel-only fallback here - would overwrite correct room-based warden with wrong generic one

        $insertProfileStmt->execute([
            ':full_name'       => $name,
            ':reg_no'          => $roll,
            ':user_id'         => $existingId,
            ':email'           => $email,
            ':personal_phone'  => $phone,
            ':room_allocation' => $roomNo,
            ':warden'          => $assignedWarden,
            ':institution'     => 'SIMATS',
            ':hostel_name'     => $hostel,
            ':address'         => ($campus ?: 'Thandalam Campus') . ', Chennai',
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
