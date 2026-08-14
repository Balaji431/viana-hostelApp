<?php
/**
 * clean_sync_booked_rooms.php
 *
 * One-shot clean sync endpoint:
 * 1. Fetches ALL students from booked-rooms/external API (source of truth)
 * 2. Deletes any student in users/profile NOT in that API
 * 3. Upserts users + profiles with correct RoomId, HostelName, RoomType from API
 * 4. Assigns correct warden via rooms_groups_details lookup per room
 * 5. Rebuilds new_api table (truncate + re-insert from API)
 * 6. Recomputes occupied_beds / available_beds in room_master & rooms_groups_details
 *
 * Run once via: http://localhost/hostelapp/hostel_backend/clean_sync_booked_rooms.php
 * or CLI: php clean_sync_booked_rooms.php
 */

set_time_limit(300);
ini_set('memory_limit', '512M');

header('Content-Type: application/json; charset=UTF-8');
header('Access-Control-Allow-Origin: *');

require_once __DIR__ . '/config/database.php';
require_once __DIR__ . '/config/api_config.php';

$log = [];
$errors = [];

function logMsg($msg, &$log) {
    $line = '[' . date('H:i:s') . '] ' . $msg;
    $log[] = $line;
    // Also flush to output buffer for real-time progress in browser
    if (ob_get_level()) {
        echo $line . "\n";
        ob_flush();
        flush();
    }
}

// ─────────────────────────────────────────────
// STEP 0: Connect to DB
// ─────────────────────────────────────────────
try {
    $db = (new Database())->getConnection();
    if (!$db) throw new Exception("DB connection failed");
} catch (Exception $e) {
    echo json_encode(["success" => false, "error" => $e->getMessage()]);
    exit(1);
}

logMsg("DB connected.", $log);

// ─────────────────────────────────────────────
// STEP 1: Fetch all records from booked-rooms/external API
// ─────────────────────────────────────────────
function fetchAllBookedRooms() {
    $page  = 1;
    $limit = 100;
    $all   = [];

    while (true) {
        $url = "https://vstudy.saveetha.com/api/hostel-settings/booked-rooms/external?page=$page&limit=$limit";
        $ch  = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 20,
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_HTTPHEADER     => [
                'X-Client-Id: '     . VSTUDY_CLIENT_ID,
                'X-Client-Secret: ' . VSTUDY_CLIENT_SECRET,
                'Accept: application/json',
            ],
        ]);
        $res  = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($code !== 200 || !$res) break;

        $json  = json_decode($res, true);
        $batch = $json['data'] ?? [];
        if (empty($batch)) break;

        $all = array_merge($all, $batch);
        if (count($batch) < $limit) break;
        $page++;
        usleep(20000); // 20ms rate limit
    }
    return $all;
}

logMsg("Fetching booked-rooms/external API (all pages)...", $log);
$bookedRooms = fetchAllBookedRooms();
$totalFromApi = count($bookedRooms);
logMsg("Total records fetched from API: $totalFromApi", $log);

if ($totalFromApi === 0) {
    echo json_encode(["success" => false, "error" => "API returned 0 records. Aborting to protect data."]);
    exit(1);
}

// Deduplicate by registerNumber — keep the latest bookedAt
$apiStudents = []; // keyed by registerNumber
foreach ($bookedRooms as $b) {
    $reg = trim($b['registerNumber'] ?? $b['register_number'] ?? '');
    if (!$reg) continue;

    if (!isset($apiStudents[$reg])) {
        $apiStudents[$reg] = $b;
    } else {
        // Keep the latest bookedAt
        $existingAt = strtotime($apiStudents[$reg]['bookedAt'] ?? 0);
        $newAt      = strtotime($b['bookedAt'] ?? 0);
        if ($newAt > $existingAt) {
            $apiStudents[$reg] = $b;
        }
    }
}

$validRegNos  = array_keys($apiStudents);
$uniqueCount  = count($validRegNos);
logMsg("Unique register numbers from API (deduped): $uniqueCount", $log);

// ─────────────────────────────────────────────
// STEP 2: Snapshot BEFORE counts
// ─────────────────────────────────────────────
$beforeStudentCount  = (int)$db->query("SELECT COUNT(*) FROM users WHERE role='student'")->fetchColumn();
$beforeProfileCount  = (int)$db->query("SELECT COUNT(*) FROM profile")->fetchColumn();
$beforeNewApiCount   = (int)$db->query("SELECT COUNT(*) FROM new_api")->fetchColumn();
logMsg("BEFORE — users(students): $beforeStudentCount | profile: $beforeProfileCount | new_api: $beforeNewApiCount", $log);

// ─────────────────────────────────────────────
// STEP 3: Delete students NOT in API
// ─────────────────────────────────────────────
logMsg("Identifying students to DELETE (not in API)...", $log);

// Fetch all current student usernames
$currentStudents = $db->query("SELECT id, username FROM users WHERE role='student'")->fetchAll(PDO::FETCH_ASSOC);
$validSet        = array_flip($validRegNos); // for O(1) lookup

$toDeleteIds       = [];
$toDeleteUsernames = [];
foreach ($currentStudents as $s) {
    $uname = trim($s['username']);
    if (!isset($validSet[$uname])) {
        $toDeleteIds[]       = (int)$s['id'];
        $toDeleteUsernames[] = $uname;
    }
}

$deleteCount = count($toDeleteIds);
logMsg("Students to delete: $deleteCount", $log);

$db->exec("SET FOREIGN_KEY_CHECKS=0");

if ($deleteCount > 0) {
    // Delete in batches of 500 to avoid huge IN clauses
    $batches = array_chunk($toDeleteIds, 500);
    foreach ($batches as $batch) {
        $placeholders = implode(',', array_fill(0, count($batch), '?'));

        // Delete from profile by user_id
        $stmtP = $db->prepare("DELETE FROM profile WHERE user_id IN ($placeholders)");
        $stmtP->execute($batch);

        // Delete parent_student_map by student_id (stored as username)
        $regBatch = [];
        foreach ($batch as $id) {
            // find username
            foreach ($currentStudents as $s) {
                if ((int)$s['id'] === $id) {
                    $regBatch[] = $s['username'];
                    break;
                }
            }
        }
        if (!empty($regBatch)) {
            $rph = implode(',', array_fill(0, count($regBatch), '?'));
            $stmtParent = $db->prepare("DELETE FROM parent_student_map WHERE student_id IN ($rph)");
            $stmtParent->execute($regBatch);

            $stmtParentUser = $db->prepare("DELETE FROM parent_users WHERE parent_id IN (" . implode(',', array_fill(0, count($regBatch), '?')) . ")");
            // parent_id is stored as "P_<regNo>"
            $parentIds = array_map(fn($r) => "P_$r", $regBatch);
            $stmtPU = $db->prepare("DELETE FROM parent_users WHERE parent_id IN ($rph)");
            // Use parent_id column
            $stmtPUv2 = $db->prepare("DELETE FROM parent_users WHERE REPLACE(parent_id, 'P_', '') IN ($rph)");
            $stmtPUv2->execute($regBatch);
        }

        // Delete from users
        $stmtU = $db->prepare("DELETE FROM users WHERE id IN ($placeholders) AND role='student'");
        $stmtU->execute($batch);
    }
    logMsg("Deleted $deleteCount student accounts not in API.", $log);
} else {
    logMsg("No students to delete — all current students are in the API.", $log);
}

// ─────────────────────────────────────────────
// STEP 4: Pre-build warden lookup map from rooms_groups_details
// ─────────────────────────────────────────────
logMsg("Building warden lookup map from rooms_groups_details...", $log);

$rgdRows = $db->query("
    SELECT room_number, warden_name, group_name, hostel_name, group_id
    FROM rooms_groups_details
    WHERE room_number IS NOT NULL AND room_number != ''
")->fetchAll(PDO::FETCH_ASSOC);

// Normalize key function
function normKey($s) {
    $s = strtoupper(trim((string)$s));
    $s = preg_replace('/W[-_\s]*O(?=\d)/i', 'W0', $s);
    $s = preg_replace('/[-_\s]+(BED|B|SLOT)?\s*\d+$/i', '', $s);
    $s = preg_replace('/[^A-Z0-9]/', '', $s);
    return $s;
}

$wardenByRoom    = []; // exact room_number => warden_name
$wardenByNormKey = []; // normalised key   => warden_name
$groupByRoom     = [];
$hostelByRoom    = [];

foreach ($rgdRows as $r) {
    $rn  = $r['room_number'];
    $key = normKey($rn);
    $wardenByRoom[$rn]    = $r['warden_name'];
    $wardenByNormKey[$key] = $r['warden_name'];
    $groupByRoom[$rn]     = $r['group_name'];
    $hostelByRoom[$rn]    = $r['hostel_name'];
}

function lookupWarden($roomNo, $wardenByRoom, $wardenByNormKey) {
    if (!$roomNo) return null;
    if (isset($wardenByRoom[$roomNo])) return $wardenByRoom[$roomNo];
    $key = normKey($roomNo);
    return $wardenByNormKey[$key] ?? null;
}

logMsg("Warden lookup map built: " . count($wardenByRoom) . " rooms.", $log);

// ─────────────────────────────────────────────
// STEP 5: Upsert users + profile from API
// ─────────────────────────────────────────────
logMsg("Upserting users and profiles from API...", $log);

$today   = new DateTime('today', new DateTimeZone('Asia/Kolkata'));
$pwHash  = password_hash('welcome123', PASSWORD_BCRYPT);

$checkUserStmt = $db->prepare("SELECT id FROM users WHERE username = ?");

$insertUserStmt = $db->prepare("
    INSERT INTO users (
        username, full_name, email, phone_number, role, password,
        Campus, Institution, HostelName, HostelType, RoomType, RoomId,
        Status, is_active, source
    ) VALUES (
        :username, :full_name, :email, :phone_number, 'student', :password,
        :Campus, 'SIMATS', :HostelName, :HostelType, :RoomType, :RoomId,
        '1', 1, 'booked_rooms_api'
    )
");

$updateUserStmt = $db->prepare("
    UPDATE users SET
        full_name    = ?,
        email        = ?,
        phone_number = ?,
        Campus       = ?,
        HostelName   = ?,
        HostelType   = ?,
        RoomType     = ?,
        RoomId       = ?,
        source       = 'booked_rooms_api',
        Status       = '1',
        is_active    = 1
    WHERE username = ? AND role = 'student'
");

$insertProfileStmt = $db->prepare("
    INSERT INTO profile (
        full_name, reg_no, user_id, email, personal_phone,
        room_allocation, warden, institution, hostel_name, address,
        renewal_date, remaining_days, check_in_date, valid_from
    ) VALUES (
        :full_name, :reg_no, :user_id, :email, :personal_phone,
        :room_allocation, :warden, 'SIMATS', :hostel_name, 'Thandalam Campus, Chennai',
        :renewal_date, :remaining_days, :check_in_date, :valid_from
    ) ON DUPLICATE KEY UPDATE
        full_name      = VALUES(full_name),
        email          = VALUES(email),
        personal_phone = VALUES(personal_phone),
        room_allocation = VALUES(room_allocation),
        warden         = CASE WHEN VALUES(warden) IS NOT NULL AND VALUES(warden) != '' THEN VALUES(warden) ELSE warden END,
        hostel_name    = VALUES(hostel_name),
        renewal_date   = VALUES(renewal_date),
        remaining_days = VALUES(remaining_days),
        check_in_date  = VALUES(check_in_date),
        valid_from     = VALUES(valid_from)
");

$newInserted = 0;
$updated     = 0;
$profilesUpserted = 0;

foreach ($apiStudents as $reg => $b) {
    $name   = trim($b['name'] ?? 'Student');
    $email  = trim($b['email'] ?? '');
    $phone  = trim($b['phone'] ?? '');
    $gender = strtolower(trim($b['gender'] ?? ''));
    $campus = trim($b['campus'] ?? 'Thandalam Campus');
    $hostel = trim($b['hostelName'] ?? '');
    $roomNo = trim($b['roomNumber'] ?? '');
    $rType  = trim($b['roomType'] ?? '');
    $renStr = trim($b['renewalDate'] ?? '');
    $booked = trim($b['bookedAt'] ?? '');

    $hType  = (
        $gender === 'female' ||
        stripos($hostel, 'girls') !== false ||
        stripos($hostel, 'ponni') !== false ||
        stripos($hostel, 'vaigai') !== false ||
        stripos($hostel, 'siruvani') !== false
    ) ? 'Girls' : 'Boys';

    // Calculate renewal date
    if (!empty($renStr) && strtotime($renStr) !== false) {
        $calcRenewal = new DateTime($renStr);
    } elseif (!empty($booked) && strtotime($booked) !== false) {
        $calcRenewal = (clone new DateTime($booked))->modify('+1 year');
    } else {
        $calcRenewal = (clone $today)->modify('+1 year');
    }
    $renFormatted = $calcRenewal->format('Y-m-d');
    $remDays      = ($calcRenewal < $today) ? 0 : (int)$today->diff($calcRenewal)->format('%r%a');

    $checkInFormatted = (!empty($booked) && strtotime($booked) !== false)
        ? (new DateTime($booked))->format('Y-m-d')
        : $today->format('Y-m-d');

    // Look up warden from rooms_groups_details
    $assignedWarden = lookupWarden($roomNo, $wardenByRoom, $wardenByNormKey);

    // Upsert user
    $checkUserStmt->execute([$reg]);
    $userId = $checkUserStmt->fetchColumn();

    if (!$userId) {
        $insertUserStmt->execute([
            ':username'     => $reg,
            ':full_name'    => $name,
            ':email'        => $email,
            ':phone_number' => $phone,
            ':password'     => $pwHash,
            ':Campus'       => $campus,
            ':HostelName'   => $hostel,
            ':HostelType'   => $hType,
            ':RoomType'     => $rType,
            ':RoomId'       => $roomNo,
        ]);
        $userId = $db->lastInsertId();
        $newInserted++;
    } else {
        $updateUserStmt->execute([
            $name, $email, $phone, $campus, $hostel, $hType, $rType, $roomNo, $reg
        ]);
        $updated++;
    }

    // Upsert profile
    $insertProfileStmt->execute([
        ':full_name'       => $name,
        ':reg_no'          => $reg,
        ':user_id'         => $userId,
        ':email'           => $email,
        ':personal_phone'  => $phone,
        ':room_allocation' => $roomNo,
        ':warden'          => $assignedWarden,
        ':hostel_name'     => $hostel,
        ':renewal_date'    => $renFormatted,
        ':remaining_days'  => $remDays,
        ':check_in_date'   => $checkInFormatted,
        ':valid_from'      => $checkInFormatted,
    ]);
    $profilesUpserted++;
}

logMsg("Users inserted: $newInserted | Updated: $updated | Profiles upserted: $profilesUpserted", $log);

// ─────────────────────────────────────────────
// STEP 6: Delete orphaned profiles (user_id not in students)
// ─────────────────────────────────────────────
$orphanProfilesDeleted = $db->exec("
    DELETE p FROM profile p
    LEFT JOIN users u ON p.user_id = u.id
    WHERE u.id IS NULL
");
logMsg("Orphaned profiles deleted: $orphanProfilesDeleted", $log);

// ─────────────────────────────────────────────
// STEP 7: Rebuild new_api table from API data
// ─────────────────────────────────────────────
logMsg("Rebuilding new_api table (truncate + re-insert)...", $log);

$db->exec("TRUNCATE TABLE new_api");

$insertNewApi = $db->prepare("
    INSERT INTO new_api (
        booking_id, register_number, student_name, email, phone, gender,
        booker_type, hostel_name, campus, room_number, room_type,
        monthly_fee, deduction_status, status, renewal_date,
        check_in, check_out, booked_at
    ) VALUES (
        :booking_id, :register_number, :student_name, :email, :phone, :gender,
        :booker_type, :hostel_name, :campus, :room_number, :room_type,
        :monthly_fee, :deduction_status, :status, :renewal_date,
        :check_in, :check_out, :booked_at
    )
");

foreach ($bookedRooms as $b) {
    $reg = trim($b['registerNumber'] ?? $b['register_number'] ?? '');
    if (!$reg) continue;

    $insertNewApi->execute([
        ':booking_id'       => $b['bookingId'] ?? '',
        ':register_number'  => $reg,
        ':student_name'     => $b['name'] ?? '',
        ':email'            => $b['email'] ?? '',
        ':phone'            => $b['phone'] ?? '',
        ':gender'           => $b['gender'] ?? '',
        ':booker_type'      => $b['bookerType'] ?? 'STUDENT',
        ':hostel_name'      => $b['hostelName'] ?? '',
        ':campus'           => $b['campus'] ?? '',
        ':room_number'      => $b['roomNumber'] ?? '',
        ':room_type'        => $b['roomType'] ?? '',
        ':monthly_fee'      => is_numeric($b['monthlyFee'] ?? '') ? (float)$b['monthlyFee'] : 0,
        ':deduction_status' => $b['deductionStatus'] ?? '',
        ':status'           => $b['status'] ?? '',
        ':renewal_date'     => $b['renewalDate'] ?? '',
        ':check_in'         => $b['checkIn'] ?? '',
        ':check_out'        => $b['checkOut'] ?? '',
        ':booked_at'        => $b['bookedAt'] ?? '',
    ]);
}

$newApiCount = (int)$db->query("SELECT COUNT(*) FROM new_api")->fetchColumn();
logMsg("new_api rebuilt: $newApiCount rows inserted.", $log);

// ─────────────────────────────────────────────
// STEP 8: Recompute occupied_beds / available_beds in room_master
// ─────────────────────────────────────────────
logMsg("Recomputing room occupancy in room_master...", $log);

// Build occupancy count: count students per RoomId
$occupancyRaw = $db->query("
    SELECT RoomId, COUNT(*) as cnt
    FROM users
    WHERE role = 'student'
      AND RoomId IS NOT NULL AND TRIM(RoomId) != '' AND RoomId != '0'
    GROUP BY RoomId
")->fetchAll(PDO::FETCH_ASSOC);

// Build occupancy map: normalized key => count
$occupancyMap = [];
foreach ($occupancyRaw as $row) {
    $key = normKey($row['RoomId']);
    $occupancyMap[$key] = ($occupancyMap[$key] ?? 0) + (int)$row['cnt'];
}

// Fetch all room_master rows
$rmRows = $db->query("SELECT id, room_code, total_beds FROM room_master")->fetchAll(PDO::FETCH_ASSOC);
$updateRmStmt = $db->prepare("
    UPDATE room_master
    SET occupied_beds   = ?,
        available_beds  = GREATEST(0, total_beds - ?),
        assigned_pending = 0,
        updated_at      = NOW()
    WHERE id = ?
");

$rmUpdated = 0;
foreach ($rmRows as $rm) {
    $key   = normKey($rm['room_code']);
    $occ   = $occupancyMap[$key] ?? 0;
    $total = (int)($rm['total_beds'] ?? 1);
    $avail = max(0, $total - $occ);
    $updateRmStmt->execute([$occ, $occ, $rm['id']]);
    $rmUpdated++;
}

logMsg("room_master updated: $rmUpdated rooms recomputed.", $log);

// ─────────────────────────────────────────────
// STEP 9: Recompute occupied_beds / available_beds in rooms_groups_details
// ─────────────────────────────────────────────
logMsg("Recomputing room occupancy in rooms_groups_details...", $log);

$rgdAll = $db->query("SELECT s_no, room_number, total_beds FROM rooms_groups_details")->fetchAll(PDO::FETCH_ASSOC);
$updateRgdStmt = $db->prepare("
    UPDATE rooms_groups_details
    SET occupied_beds   = ?,
        available_beds  = GREATEST(0, total_beds - ?),
        assigned_pending = 0,
        updated_at      = NOW()
    WHERE s_no = ?
");

$rgdUpdated = 0;
foreach ($rgdAll as $r) {
    $key   = normKey($r['room_number']);
    $occ   = $occupancyMap[$key] ?? 0;
    $updateRgdStmt->execute([$occ, $occ, $r['s_no']]);
    $rgdUpdated++;
}

logMsg("rooms_groups_details updated: $rgdUpdated rows recomputed.", $log);

$db->exec("SET FOREIGN_KEY_CHECKS=1");

// ─────────────────────────────────────────────
// STEP 10: Snapshot AFTER counts
// ─────────────────────────────────────────────
$afterStudentCount  = (int)$db->query("SELECT COUNT(*) FROM users WHERE role='student'")->fetchColumn();
$afterProfileCount  = (int)$db->query("SELECT COUNT(*) FROM profile")->fetchColumn();
$afterNewApiCount   = (int)$db->query("SELECT COUNT(*) FROM new_api")->fetchColumn();
$allocatedStudents  = (int)$db->query("
    SELECT COUNT(*) FROM users WHERE role='student'
    AND RoomId IS NOT NULL AND TRIM(RoomId) != '' AND RoomId != '0'
")->fetchColumn();
$profilesWithRoom   = (int)$db->query("
    SELECT COUNT(*) FROM profile
    WHERE room_allocation IS NOT NULL AND TRIM(room_allocation) != ''
")->fetchColumn();
$profilesWithWarden = (int)$db->query("
    SELECT COUNT(*) FROM profile
    WHERE warden IS NOT NULL AND TRIM(warden) != ''
")->fetchColumn();

logMsg("AFTER — users(students): $afterStudentCount | profile: $afterProfileCount | new_api: $afterNewApiCount", $log);
logMsg("Students with RoomId: $allocatedStudents | Profiles with room_allocation: $profilesWithRoom | Profiles with warden: $profilesWithWarden", $log);
logMsg("Clean sync COMPLETE.", $log);

// ─────────────────────────────────────────────
// OUTPUT
// ─────────────────────────────────────────────
echo json_encode([
    "success"      => true,
    "message"      => "Clean sync completed — students now exactly match booked-rooms/external API.",
    "api_total"    => $totalFromApi,
    "api_unique"   => $uniqueCount,
    "before" => [
        "users_students" => $beforeStudentCount,
        "profile"        => $beforeProfileCount,
        "new_api"        => $beforeNewApiCount,
    ],
    "deleted_students"    => $deleteCount,
    "inserted_students"   => $newInserted,
    "updated_students"    => $updated,
    "profiles_upserted"   => $profilesUpserted,
    "orphan_profiles_del" => $orphanProfilesDeleted,
    "after" => [
        "users_students"        => $afterStudentCount,
        "profile"               => $afterProfileCount,
        "new_api"               => $afterNewApiCount,
        "students_with_room"    => $allocatedStudents,
        "profiles_with_room"    => $profilesWithRoom,
        "profiles_with_warden"  => $profilesWithWarden,
    ],
    "room_master_updated"  => $rmUpdated,
    "rooms_groups_updated" => $rgdUpdated,
    "log"                  => $log,
], JSON_PRETTY_PRINT);
