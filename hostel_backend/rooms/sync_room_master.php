<?php
/**
 * sync_room_master.php
 *
 * Daily cron job to sync both room_master and rooms_groups_details tables with live external API:
 * - physical-rooms/external returns: roomNumber, hostelRoomId, totalBeds,
 *   occupiedBeds, assignedPending, availableBeds, roomType, groupId, groupName, wardenUserId, wardenName etc.
 * - local allocation_requests adds any locally tracked pending allocations (≤ 3 day window)
 * - auto-expire payment_pending allocations past their deadline
 * - auto-insert any missing physical rooms into room_master AND rooms_groups_details
 *
 * Cron schedule (daily midnight):
 * 0 0 * * * root /usr/local/bin/php /var/www/html/rooms/sync_room_master.php >> /var/log/cron_room_sync.log 2>&1
 */

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/api_config.php';

header('Content-Type: application/json');

function log_sync($msg) {
    echo '[' . date('Y-m-d H:i:s') . '] ' . $msg . PHP_EOL;
}

/**
 * Normalize a room code key for exact/fuzzy room matching.
 * Strips hyphens, spaces, letter O in W0, and bed suffixes.
 */
function normKey($str) {
    if (empty($str)) return '';
    $s = strtoupper(trim($str));
    $s = preg_replace('/W[-_\s]*O(?=\d)/', 'W0', $s);
    $s = preg_replace('/[-_\s]+(BED|B|SLOT)?\s*\d+$/i', '', $s);
    $s = preg_replace('/[^A-Z0-9]/', '', $s);
    return $s;
}

function extractCapacity($roomTypeName) {
    $upper = strtoupper(trim($roomTypeName ?? ''));
    if (preg_match('/(\d+)\s*IN\s*1/', $upper, $m)) return (int)$m[1];
    if (strpos($upper, 'DOUBLE') !== false) return 2;
    if (strpos($upper, 'SINGLE') !== false) return 1;
    return 1;
}

function fetchVStudyPages($baseUrl) {
    $page  = 1;
    $limit = 100;
    $all   = [];

    while (true) {
        $sep = strpos($baseUrl, '?') !== false ? '&' : '?';
        $url = $baseUrl . $sep . "page=$page&limit=$limit";

        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 30);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'x-client-id: '     . VSTUDY_CLIENT_ID,
            'x-client-secret: ' . VSTUDY_CLIENT_SECRET,
            'Accept: application/json',
        ]);
        $res  = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err  = curl_error($ch);
        curl_close($ch);

        if ($err || $code !== 200) {
            log_sync("API error (HTTP $code) for $url: $err");
            break;
        }

        $json  = json_decode($res, true);
        $batch = [];
        if (isset($json['data']) && is_array($json['data'])) {
            $batch = $json['data'];
        } elseif (is_array($json)) {
            $batch = $json;
        }

        if (empty($batch)) break;

        $all = array_merge($all, $batch);
        if (count($batch) < $limit) break;

        $page++;
        usleep(20000);
    }

    return $all;
}

function parseRoomCodeParts($roomNum) {
    $parts = explode('-', $roomNum);
    $building = ''; $floor = ''; $block = ''; $roomNo = '';
    if (count($parts) >= 5) {
        $building = $parts[0] . '-' . $parts[1];
        $floor    = $parts[2];
        $block    = $parts[3];
        $roomNo   = implode('-', array_slice($parts, 4));
    } elseif (count($parts) == 4) {
        $building = $parts[0];
        $floor    = $parts[1];
        $block    = $parts[2];
        $roomNo   = $parts[3];
    } else {
        $roomNo   = $roomNum;
    }
    return [
        'building_code' => $building,
        'floor_no'      => $floor,
        'block_no'      => $block,
        'room_no'       => $roomNo
    ];
}

try {
    $database = new Database();
    $db = $database->getConnection();
    if (!$db) throw new Exception("Database connection failed");

    log_sync("=== sync_room_master.php started ===");

    // -----------------------------------------------------------------------
    // STEP 1: Expire payment_pending allocations past their deadline
    // -----------------------------------------------------------------------
    log_sync("Step 1: Expiring overdue payment_pending allocations...");
    $expireStmt = $db->prepare("
        UPDATE allocation_requests
        SET status = 'payment_expired', request_status = 'cancelled'
        WHERE status = 'payment_pending'
          AND payment_deadline IS NOT NULL
          AND payment_deadline < NOW()
    ");
    $expireStmt->execute();
    $expiredCount = $expireStmt->rowCount();
    log_sync("  Expired: $expiredCount allocation(s).");

    // -----------------------------------------------------------------------
    // STEP 2: Fetch physical-rooms/external
    // -----------------------------------------------------------------------
    log_sync("Step 2: Fetching physical-rooms from external API...");
    $physicalRooms = fetchVStudyPages('https://vstudy.saveetha.com/api/hostel-settings/physical-rooms/external');
    log_sync("  Received " . count($physicalRooms) . " physical room records.");

    // Map strictly by normKey(roomNumber) to prevent non-unique hostelRoomId cross-over
    $physByRoomNum = [];

    foreach ($physicalRooms as $pr) {
        $roomNum     = trim($pr['roomNumber']   ?? '');
        $hostelRoomId= trim($pr['hostelRoomId'] ?? $pr['id'] ?? '');
        $rType       = trim($pr['roomType']     ?? '');

        if (empty($roomNum)) continue;

        $data = [
            'id'               => $pr['id']               ?? $hostelRoomId,
            'hostel_id'        => $pr['hostelId']         ?? '',
            'hostel_name'      => trim($pr['hostelName']  ?? ''),
            'campus'           => trim($pr['campus']      ?? ''),
            'hostel_room_id'   => $hostelRoomId,
            'room_type'        => $rType,
            'room_number'      => $roomNum,
            'occupancy'        => (int)($pr['occupancy']       ?? $pr['totalBeds'] ?? extractCapacity($rType)),
            'total_beds'       => (int)($pr['totalBeds']       ?? $pr['total_beds'] ?? extractCapacity($rType)),
            'occupied_beds'    => (int)($pr['occupiedBeds']    ?? $pr['occupied_beds']    ?? 0),
            'assigned_pending' => (int)($pr['assignedPending'] ?? $pr['assigned_pending'] ?? 0),
            'available_beds'   => (int)($pr['availableBeds']   ?? $pr['available_beds']   ?? 0),
            'gender'           => trim($pr['gender']           ?? 'Male'),
            'active'           => isset($pr['active']) ? (int)$pr['active'] : 1,
            'amount'           => (float)($pr['amount']        ?? 0),
            'food'             => (float)($pr['food']          ?? 0),
            'caution_deposit'  => (float)($pr['cautionDeposit'] ?? 0),
            'group_id'         => $pr['groupId']          ?? '',
            'group_name'       => $pr['groupName']        ?? '',
            'warden_user_id'   => $pr['wardenUserId']     ?? '',
            'warden_name'      => $pr['wardenName']       ?? '',
            'raw_room_number'  => $roomNum,
        ];

        $physByRoomNum[normKey($roomNum)] = $data;
    }
    log_sync("  Built physByRoomNum: " . count($physByRoomNum) . " unique room keys.");

    // -----------------------------------------------------------------------
    // STEP 3: Count local pending allocations within the 3-day payment window
    // -----------------------------------------------------------------------
    log_sync("Step 3: Counting local assigned_pending from allocation_requests...");
    $pendingStmt = $db->query("
        SELECT ar.selected_room_id, COUNT(*) AS cnt
        FROM allocation_requests ar
        WHERE ar.status = 'payment_pending'
          AND ar.payment_deadline IS NOT NULL
          AND ar.payment_deadline > NOW()
          AND ar.payment_deadline <= DATE_ADD(NOW(), INTERVAL 3 DAY)
        GROUP BY ar.selected_room_id
    ");
    $pendingByRoomId = [];
    if ($pendingStmt) {
        while ($row = $pendingStmt->fetch(PDO::FETCH_ASSOC)) {
            $pendingByRoomId[(int)$row['selected_room_id']] = (int)$row['cnt'];
        }
    }

    // -----------------------------------------------------------------------
    // STEP 4: Update room_master AND rooms_groups_details tables
    // -----------------------------------------------------------------------
    log_sync("Step 4: Updating room_master AND rooms_groups_details...");

    // 4A: Sync room_master
    $allRoomsStmt = $db->query("SELECT id, room_code, room_type, total_beds FROM room_master");
    $allRooms     = $allRoomsStmt->fetchAll(PDO::FETCH_ASSOC);

    $updateRmStmt = $db->prepare("
        UPDATE room_master
        SET total_beds       = ?,
            occupied_beds    = ?,
            assigned_pending = ?,
            available_beds   = ?
        WHERE id = ?
    ");

    $matchedCount   = 0;
    $matchedApiKeys = [];

    foreach ($allRooms as $room) {
        $rid          = (int)$room['id'];
        $rType        = $room['room_type'] ?? '';
        $rCode        = $room['room_code'] ?? '';
        $kCode        = normKey($rCode);
        $localPending = $pendingByRoomId[$rid] ?? 0;

        $apiData = $physByRoomNum[$kCode] ?? null;

        if ($apiData !== null) {
            $totalBeds       = $apiData['total_beds']       > 0 ? $apiData['total_beds']       : max(1, extractCapacity($rType));
            $occupiedBeds    = $apiData['occupied_beds'];
            $assignedPending = $apiData['assigned_pending'] + $localPending;
            $availableBeds   = max(0, $totalBeds - $occupiedBeds - $assignedPending);
            $matchedCount++;
            $matchedApiKeys[$kCode] = true;
        } else {
            $curTotal        = (int)($room['total_beds'] ?? 0);
            $totalBeds       = $curTotal > 0 ? $curTotal : extractCapacity($rType);
            $occupiedBeds    = 0;
            $assignedPending = $localPending;
            $availableBeds   = max(0, $totalBeds - $occupiedBeds - $assignedPending);
        }

        $updateRmStmt->execute([$totalBeds, $occupiedBeds, $assignedPending, $availableBeds, $rid]);
    }
    log_sync("  Updated room_master table ($matchedCount matched).");

    // 4B: Sync rooms_groups_details
    $allRgStmt = $db->query("SELECT s_no, room_number, room_type FROM rooms_groups_details");
    $allRgRooms = $allRgStmt->fetchAll(PDO::FETCH_ASSOC);

    $updateRgStmt = $db->prepare("
        UPDATE rooms_groups_details
        SET total_beds       = ?,
            occupied_beds    = ?,
            assigned_pending = ?,
            available_beds   = ?,
            group_id         = ?,
            group_name       = ?,
            warden_user_id   = ?,
            warden_name      = ?
        WHERE s_no = ?
    ");

    $rgMatchedCount = 0;
    foreach ($allRgRooms as $rg) {
        $sNo    = (int)$rg['s_no'];
        $rNum   = $rg['room_number'] ?? '';
        $kNum   = normKey($rNum);
        $apiData= $physByRoomNum[$kNum] ?? null;

        if ($apiData !== null) {
            $totalBeds       = $apiData['total_beds'];
            $occupiedBeds    = $apiData['occupied_beds'];
            $assignedPending = $apiData['assigned_pending'];
            $availableBeds   = max(0, $totalBeds - $occupiedBeds - $assignedPending);

            $updateRgStmt->execute([
                $totalBeds,
                $occupiedBeds,
                $assignedPending,
                $availableBeds,
                $apiData['group_id'],
                $apiData['group_name'],
                $apiData['warden_user_id'],
                $apiData['warden_name'],
                $sNo
            ]);
            $rgMatchedCount++;
            $matchedApiKeys[$kNum] = true;
        }
    }
    log_sync("  Updated rooms_groups_details table ($rgMatchedCount rows matched and updated).");

    // 4C: Map wardens in rooms_groups_details from mapping_staff based on exact group_name match only.
    //     Using EXACT match prevents wrong wardens bleeding across floors via LIKE partial matches.
    $wardenSyncRows = $db->exec("
        UPDATE rooms_groups_details rgd
        JOIN (
            SELECT floor_name, name, staff_bio_id, username
            FROM mapping_staff
            WHERE LOWER(role) LIKE '%warden%'
            ORDER BY id ASC
        ) ms ON LOWER(TRIM(ms.floor_name)) = LOWER(TRIM(rgd.group_name))
        SET 
            rgd.warden_name = ms.name,
            rgd.warden_bio_id = COALESCE(ms.staff_bio_id, ms.username),
            rgd.warden_user_id = COALESCE(ms.staff_bio_id, ms.username)
    ");
    log_sync("  Synced warden details in rooms_groups_details from mapping_staff ($wardenSyncRows rows updated).");

    // 4D: Auto-create missing student profiles and sync profile.room_allocation & profile.warden
    $db->exec("
        INSERT INTO profile (full_name, reg_no, user_id, email, personal_phone, room_allocation, institution, hostel_name)
        SELECT 
            u.full_name, u.username, u.id, u.email, u.phone_number,
            COALESCE(NULLIF(u.RoomId, ''), 'unallocated'),
            COALESCE(NULLIF(u.Institution, ''), 'SIMATS'),
            COALESCE(NULLIF(u.HostelName, ''), 'Hostel')
        FROM users u
        LEFT JOIN profile p ON TRIM(u.username) = TRIM(p.reg_no)
        WHERE LOWER(u.role) IN ('student', 'user') AND p.reg_no IS NULL
    ");

    $db->exec("
        UPDATE profile p
        JOIN users u ON TRIM(p.reg_no) = TRIM(u.username)
        SET p.room_allocation = u.RoomId
        WHERE (p.room_allocation IS NULL OR TRIM(p.room_allocation) = '' OR LOWER(TRIM(p.room_allocation)) = 'unallocated')
          AND u.RoomId IS NOT NULL AND TRIM(u.RoomId) != '' AND LOWER(TRIM(u.RoomId)) != 'unallocated'
    ");

    // Only set profile.warden when it is currently NULL or empty.
    // NEVER overwrite an existing warden value via sync — manual corrections must be preserved.
    // The API (get_user_data.php) always live-reads from rooms_groups_details as the source of truth.
    $db->exec("
        UPDATE profile p
        JOIN rooms_groups_details rgd ON (
            TRIM(p.room_allocation) = TRIM(rgd.room_number)
            OR REPLACE(REPLACE(TRIM(p.room_allocation), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(rgd.room_number), ' ', ''), '-', '')
        )
        SET p.warden = rgd.warden_name
        WHERE (p.warden IS NULL OR TRIM(p.warden) = '')
          AND rgd.warden_name IS NOT NULL AND TRIM(rgd.warden_name) != ''
    ");
    log_sync("  Synced student profiles, room allocations, and wardens into profile table.");

    // -----------------------------------------------------------------------
    // STEP 5: Auto-insert missing API rooms into BOTH room_master AND rooms_groups_details
    // -----------------------------------------------------------------------
    log_sync("Step 5: Checking for missing API rooms to auto-insert...");

    $insertRmStmt = $db->prepare("
        INSERT INTO room_master (
            location_name, building_code, floor_no, block_no, room_no, room_code,
            hostel_room_id, room_type, occupancy, room_capacity, total_beds,
            occupied_beds, assigned_pending, available_beds, gender, amount,
            food, caution_deposit, active
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ");

    $insertRgStmt = $db->prepare("
        INSERT INTO rooms_groups_details (
            id, hostel_id, hostel_name, campus, hostel_room_id, room_type, room_number,
            occupancy, total_beds, occupied_beds, assigned_pending, available_beds,
            gender, active, amount, food, caution_deposit, group_id, group_name,
            warden_user_id, warden_name
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ");

    $insertedCount = 0;
    foreach ($physicalRooms as $pr) {
        $roomNum     = trim($pr['roomNumber']   ?? '');
        $hostelRoomId= trim($pr['hostelRoomId'] ?? $pr['id'] ?? '');
        $kNum        = normKey($roomNum);

        if (!empty($roomNum) && empty($matchedApiKeys[$kNum])) {
            $rType     = trim($pr['roomType'] ?? '');
            $capacity  = (int)($pr['totalBeds'] ?? $pr['total_beds'] ?? extractCapacity($rType));
            if ($capacity <= 0) $capacity = 1;
            $occ       = (int)($pr['occupiedBeds'] ?? 0);
            $pending   = (int)($pr['assignedPending'] ?? 0);
            $avail     = max(0, $capacity - $occ - $pending);
            $parts     = parseRoomCodeParts($roomNum);

            // Insert into room_master
            $insertRmStmt->execute([
                trim($pr['hostelName'] ?? 'Saveetha Hostel'),
                $parts['building_code'],
                $parts['floor_no'],
                $parts['block_no'],
                $parts['room_no'],
                $roomNum,
                $hostelRoomId,
                $rType,
                $capacity,
                $capacity,
                $capacity,
                $occ,
                $pending,
                $avail,
                trim($pr['gender'] ?? 'Male'),
                (float)($pr['amount'] ?? 0),
                (float)($pr['food'] ?? 0),
                (float)($pr['cautionDeposit'] ?? 0),
                isset($pr['active']) ? (int)$pr['active'] : 1
            ]);

            // Insert into rooms_groups_details
            $insertRgStmt->execute([
                $pr['id'] ?? $hostelRoomId,
                $pr['hostelId'] ?? '',
                trim($pr['hostelName'] ?? 'Saveetha Hostel'),
                trim($pr['campus'] ?? 'Thandalam Campus'),
                $hostelRoomId,
                $rType,
                $roomNum,
                $capacity,
                $capacity,
                $occ,
                $pending,
                $avail,
                trim($pr['gender'] ?? 'Male'),
                isset($pr['active']) ? (int)$pr['active'] : 1,
                (float)($pr['amount'] ?? 0),
                (float)($pr['food'] ?? 0),
                (float)($pr['cautionDeposit'] ?? 0),
                $pr['groupId'] ?? '',
                $pr['groupName'] ?? '',
                $pr['wardenUserId'] ?? '',
                $pr['wardenName'] ?? ''
            ]);

            $insertedCount++;
            $matchedApiKeys[$kNum] = true;
            log_sync("  [INSERTED] Room $roomNum into room_master & rooms_groups_details");
        }
    }

    log_sync("  Auto-inserted $insertedCount missing rooms into both tables.");
    log_sync("=== sync_room_master.php completed successfully ===");

    $result = [
        'status'                 => 'success',
        'physical_rooms'         => count($physicalRooms),
        'room_master_matched'    => $matchedCount,
        'rooms_groups_matched'   => $rgMatchedCount,
        'rooms_inserted'         => $insertedCount,
        'local_pending'          => count($pendingByRoomId),
        'expired'                => $expiredCount,
        'ran_at'                 => date('Y-m-d H:i:s'),
    ];
    echo json_encode($result, JSON_PRETTY_PRINT);

} catch (Exception $e) {
    log_sync("FATAL ERROR: " . $e->getMessage());
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
