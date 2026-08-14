<?php
require_once __DIR__ . '/../config/api_config.php';

/**
 * Perform an on-demand live fetch from VStudy external APIs
 * when a student attempts to log in but is not yet stored in the local DB.
 */
function syncStudentOnDemand($email, $db) {
    $email = trim(strtolower($email));
    $rollFromEmail = explode('@', $email)[0];
    
    // External APIs to check (recent pages)
    $apis = [
        "https://vstudy.saveetha.com/api/hostel-settings/booked-rooms/external",
        "https://vstudy.saveetha.com/api/hostel-applications/paid"
    ];
    
    $foundRecord = null;
    $recordType = '';

    foreach ($apis as $baseUrl) {
        for ($page = 1; $page <= 5; $page++) {
            $url = $baseUrl . "?page=$page&limit=100";
            $ch = curl_init($url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_HTTPHEADER, [
                "X-Client-Id: " . VSTUDY_CLIENT_ID,
                "X-Client-Secret: " . VSTUDY_CLIENT_SECRET
            ]);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
            curl_setopt($ch, CURLOPT_TIMEOUT, 10);
            $res = curl_exec($ch);
            $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);

            if ($code !== 200) break;

            $json = json_decode($res, true);
            $batch = isset($json['data']) && is_array($json['data']) ? $json['data'] : (is_array($json) ? $json : []);

            if (empty($batch)) break;

            foreach ($batch as $item) {
                $student = $item['student'] ?? $item;
                $itemEmail = strtolower(trim($student['email'] ?? $item['email'] ?? ''));
                $itemRoll  = strtolower(trim($student['rollNumber'] ?? $student['registerNumber'] ?? $item['registerNumber'] ?? $item['rollNumber'] ?? ''));

                if (($itemEmail && $itemEmail === $email) || ($itemRoll && $itemRoll === $rollFromEmail)) {
                    if (!$foundRecord || !empty($item['roomNumber']) || !empty($item['room']['roomNumber'])) {
                        $foundRecord = $item;
                        $recordType = strpos($baseUrl, 'booked-rooms') !== false ? 'booked' : 'paid';
                        if (!empty($item['roomNumber']) || !empty($item['room']['roomNumber'])) {
                            break 2;
                        }
                    }
                }
            }
        }
    }

    if (!$foundRecord) {
        return false;
    }

    // Extract student details
    $student = $foundRecord['student'] ?? $foundRecord;
    $hostel  = $foundRecord['hostel'] ?? $foundRecord;
    $room    = $foundRecord['room'] ?? $foundRecord;
    $fees    = $foundRecord['fees'] ?? [];

    $roll       = trim($student['rollNumber'] ?? $student['registerNumber'] ?? $foundRecord['registerNumber'] ?? $foundRecord['rollNumber'] ?? $rollFromEmail);
    $name       = trim($student['name'] ?? $foundRecord['name'] ?? 'Student');
    $userEmail  = trim($student['email'] ?? $foundRecord['email'] ?? $email);
    $phone      = trim($student['phone'] ?? $foundRecord['phone'] ?? '');
    $gender     = strtolower(trim($room['gender'] ?? $foundRecord['gender'] ?? 'female'));
    $campus     = trim($hostel['campus'] ?? $foundRecord['campus'] ?? 'Thandalam Campus');
    $hostelName = trim($hostel['name'] ?? $foundRecord['hostelName'] ?? '');
    $rawRoomNo  = trim($room['roomNumber'] ?? $foundRecord['roomNumber'] ?? '');
    // Clean spaces and normalize room format e.g. "T-32 F02- W0-R16" -> "T32-F02-W0-R16"
    $roomNo     = preg_replace('/-+/', '-', str_replace([' - ', '- ', ' ', 'T-32'], ['-', '-', '', 'T32'], $rawRoomNo));
    $roomType   = trim($room['roomType'] ?? $foundRecord['roomType'] ?? '');
    $hType      = ($gender === 'female' || strpos(strtolower($hostelName), 'girls') !== false || strpos(strtolower($hostelName), 'vaigai') !== false) ? 'Girls' : 'Boys';
    $paidDate   = trim($foundRecord['paidAt'] ?? $foundRecord['bookedAt'] ?? date('Y-m-d H:i:s'));

    $pwHash = password_hash('welcome123', PASSWORD_BCRYPT);
    $today  = new DateTime('today');
    $calcRenewal = (clone $today)->modify('+1 year');
    $renFormatted = $calcRenewal->format('Y-m-d');
    $checkInFormatted = (new DateTime($paidDate))->format('Y-m-d');

    // 1. Insert into vstudy_payments
    $stmtPay = $db->prepare("
        INSERT INTO vstudy_payments (
            student_name, roll_number, email, gender, academic_year, campus,
            hostel_preference, hostel_name, payment_status, application_status, paid_date, paid_amount
        ) VALUES (
            :name, :roll, :email, :gender, '1st Year', :campus,
            :room_type, :hostel_name, 'Paid', 'Application Verified', :paid_date, :paid_amount
        ) ON DUPLICATE KEY UPDATE
            student_name = VALUES(student_name), email = VALUES(email), paid_date = VALUES(paid_date)
    ");
    $stmtPay->execute([
        ':name'        => $name,
        ':roll'        => $roll,
        ':email'       => $userEmail,
        ':gender'      => ucfirst($gender),
        ':campus'      => $campus,
        ':room_type'   => $roomType,
        ':hostel_name' => $hostelName,
        ':paid_date'   => $checkInFormatted,
        ':paid_amount' => $fees['total'] ?? 0
    ]);

    // 2. Insert into users table if missing
    $checkUserStmt  = $db->prepare("SELECT id FROM users WHERE username = ? OR email = ?");
    $checkUserStmt->execute([$roll, $userEmail]);
    $existingId = $checkUserStmt->fetchColumn();

    if (!$existingId) {
        $insertUserStmt = $db->prepare("
            INSERT INTO users (
                username, full_name, email, phone_number, role, password, Campus, Institution,
                HostelName, HostelType, RoomType, RoomId, Status, is_active
            ) VALUES (
                :username, :full_name, :email, :phone_number, 'student', :password, :Campus, 'SIMATS',
                :HostelName, :HostelType, :RoomType, :RoomId, '1', 1
            )
        ");
        $insertUserStmt->execute([
            ':username'     => $roll,
            ':full_name'    => $name,
            ':email'        => $userEmail,
            ':phone_number' => $phone,
            ':password'     => $pwHash,
            ':Campus'       => $campus,
            ':HostelName'   => $hostelName,
            ':HostelType'   => $hType,
            ':RoomType'     => $roomType,
            ':RoomId'       => $roomNo
        ]);
        $existingId = $db->lastInsertId();
    } else {
        $updateUserStmt = $db->prepare("
            UPDATE users SET 
                full_name = ?, email = ?, phone_number = ?, Campus = ?, HostelName = ?, HostelType = ?, RoomType = ?, RoomId = ?
            WHERE id = ?
        ");
        $updateUserStmt->execute([$name, $userEmail, $phone, $campus, $hostelName, $hType, $roomType, $roomNo, $existingId]);
    }

    // 2.5. Resolve warden dynamically based on room number & hostel
    $assignedWarden = null;
    if (!empty($roomNo)) {
        $wStmt = $db->prepare("
            SELECT warden_name 
            FROM rooms_groups_details 
            WHERE (room_number = :rn OR REPLACE(REPLACE(TRIM(room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(:rn2), ' ', ''), '-', ''))
              AND warden_name IS NOT NULL AND warden_name != ''
            LIMIT 1
        ");
        $wStmt->execute([':rn' => $roomNo, ':rn2' => $roomNo]);
        $assignedWarden = $wStmt->fetchColumn();
    }

    if (empty($assignedWarden) && !empty($hostelName)) {
        $mStmt = $db->prepare("
            SELECT name FROM mapping_staff 
            WHERE LOWER(role) = 'warden' AND (LOWER(hostel_name) = LOWER(:hn) OR LOWER(:hn2) LIKE CONCAT('%', LOWER(hostel_name), '%')) 
            ORDER BY id ASC LIMIT 1
        ");
        $mStmt->execute([':hn' => $hostelName, ':hn2' => $hostelName]);
        $assignedWarden = $mStmt->fetchColumn();
    }

    // 3. Insert into profile
    $insertProfileStmt = $db->prepare("
        INSERT INTO profile (
            full_name, reg_no, user_id, email, personal_phone, room_allocation, warden,
            institution, hostel_name, address, renewal_date, remaining_days,
            check_in_date, valid_from
        ) VALUES (
            :full_name, :reg_no, :user_id, :email, :personal_phone, :room_allocation, :warden,
            :institution, :hostel_name, :address, :renewal_date, :remaining_days,
            :check_in_date, :valid_from
        ) ON DUPLICATE KEY UPDATE 
            full_name = VALUES(full_name), email = VALUES(email), personal_phone = VALUES(personal_phone),
            room_allocation = VALUES(room_allocation), 
            warden = COALESCE(NULLIF(VALUES(warden),''), warden), 
            hostel_name = VALUES(hostel_name),
            renewal_date = VALUES(renewal_date), remaining_days = VALUES(remaining_days),
            check_in_date = VALUES(check_in_date), valid_from = VALUES(valid_from)
    ");
    $insertProfileStmt->execute([
        ':full_name'       => $name,
        ':reg_no'          => $roll,
        ':user_id'         => $existingId,
        ':email'           => $userEmail,
        ':personal_phone'  => $phone,
        ':room_allocation' => $roomNo,
        ':warden'          => $assignedWarden,
        ':institution'     => 'SIMATS',
        ':hostel_name'     => $hostelName,
        ':address'         => 'Thandalam Campus, Chennai',
        ':renewal_date'   => $renFormatted,
        ':remaining_days' => 365,
        ':check_in_date'   => $checkInFormatted,
        ':valid_from'      => $checkInFormatted
    ]);

    // 4. Insert into parent tables
    $parentId = "P_" . $roll;
    $insertParentStmt = $db->prepare("
        INSERT INTO parent_users (parent_id, password, contact) 
        VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE contact = VALUES(contact)
    ");
    $insertParentStmt->execute([$parentId, $pwHash, $phone]);

    $insertMapStmt = $db->prepare("
        INSERT INTO parent_student_map (parent_id, student_id) 
        VALUES (?, ?) ON DUPLICATE KEY UPDATE parent_id = VALUES(parent_id)
    ");
    $insertMapStmt->execute([$parentId, $roll]);

    return true;
}
