<?php
/**
 * generate_wing_mappings.php
 *
 * Populates location_mappings and mapping_staff based directly on the live room-groups API:
 * https://vstudy.saveetha.com/api/hostel-settings/room-groups/external
 *
 * Maps wardens directly to their entire group/floor (e.g. "Noyyal Hostel Sixth Floor")
 * without splitting by individual wing codes separately.
 */

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/api_config.php';

function fetchVStudyPages($baseUrl) {
    $page = 1; $limit = 100; $all = [];
    while (true) {
        $sep = strpos($baseUrl, '?') !== false ? '&' : '?';
        $url = $baseUrl . $sep . "page=$page&limit=$limit";
        $ch  = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 30);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'x-client-id: ' . VSTUDY_CLIENT_ID,
            'x-client-secret: ' . VSTUDY_CLIENT_SECRET,
            'Accept: application/json',
        ]);
        $res  = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($code !== 200) break;
        $json  = json_decode($res, true);
        $batch = isset($json['data']) ? $json['data'] : (is_array($json) ? $json : []);
        if (empty($batch)) break;
        $all = array_merge($all, $batch);
        if (count($batch) < $limit) break;
        $page++; usleep(20000);
    }
    return $all;
}

try {
    echo "Starting automated floor/group-level mapping generation from room-groups API...\n";

    // 1. Fetch hostel ID map from hostel_type
    $database = new Database();
    $pdo = $database->getConnection();

    $hostelMap = [];
    $hStmt = $pdo->query("SELECT id, hostel_name FROM hostel_type");
    while ($h = $hStmt->fetch(PDO::FETCH_ASSOC)) {
        $hostelMap[trim(strtolower($h['hostel_name']))] = $h['id'];
    }

    // 2. Fetch room groups from external API
    $roomGroups = fetchVStudyPages('https://vstudy.saveetha.com/api/hostel-settings/room-groups/external');
    echo "Received " . count($roomGroups) . " room groups from API.\n";

    // 3. Clear existing location_mappings & mapping_staff
    $pdo->exec("DELETE FROM mapping_staff");
    $pdo->exec("DELETE FROM location_mappings");
    $pdo->exec("ALTER TABLE location_mappings AUTO_INCREMENT = 1");
    $pdo->exec("ALTER TABLE mapping_staff AUTO_INCREMENT = 1");

    $pdo->beginTransaction();

    $insertMappingStmt = $pdo->prepare("
        INSERT INTO location_mappings (hostel_id, zone_id, sub_zone_id, created_at, updated_at)
        VALUES (?, ?, ?, NOW(), NOW())
    ");

    $insertStaffStmt = $pdo->prepare("
        INSERT INTO mapping_staff (mapping_id, name, role, phone, username, staff_bio_id, hostel_name, floor_name, wing_name)
        VALUES (?, ?, 'Warden', ?, ?, ?, ?, ?, ?)
    ");

    $wardenDetailsStmt = $pdo->prepare("
        SELECT username, phone_number FROM users WHERE (full_name = ? OR username = ?) AND role = 'warden' LIMIT 1
    ");

    $countCreated = 0;
    foreach ($roomGroups as $rg) {
        $groupName = trim($rg['name'] ?? '');
        $wName     = trim($rg['wardenName'] ?? '');
        $wBioId    = trim($rg['wardenBioId'] ?? $rg['wardenUserId'] ?? '');

        if (empty($groupName)) continue;

        // Parse hostel_name from groupName (e.g. "Noyyal Hostel Sixth Floor" -> "Noyyal Hostel")
        $hostelName = 'Saveetha Hostel';
        if (preg_match('/^(.*?Hostel)/i', $groupName, $m)) {
            $hostelName = trim($m[1]);
        } elseif (preg_match('/^(Stunners Den)/i', $groupName, $m)) {
            $hostelName = 'Stunners Den';
        } else {
            // fallback: first two words
            $words = explode(' ', $groupName);
            if (count($words) >= 2) {
                $hostelName = $words[0] . ' ' . $words[1];
            }
        }

        // Determine hostel_id from hostelMap
        $hId = 1;
        $hLower = strtolower($hostelName);
        foreach ($hostelMap as $hKey => $idVal) {
            $cleanKey = preg_replace('/\s*hostel\s*/i', '', $hKey);
            $cleanH   = preg_replace('/\s*hostel\s*/i', '', $hLower);
            if (strpos($cleanH, $cleanKey) !== false || strpos($cleanKey, $cleanH) !== false) {
                $hId = $idVal;
                break;
            }
        }

        // Insert into location_mappings (zone_id = entire groupName e.g. "Noyyal Hostel Sixth Floor", sub_zone_id = "All")
        $insertMappingStmt->execute([$hId, $groupName, 'All']);
        $mappingId = $pdo->lastInsertId();
        $countCreated++;

        // Determine warden details
        if (empty($wName)) $wName = "Manoj A";
        if (empty($wBioId)) $wBioId = "20018";

        $phone = "8072768337";
        $username = $wBioId;

        // Check if user has updated phone in users table
        $wardenDetailsStmt->execute([$wName, $wBioId]);
        $uRow = $wardenDetailsStmt->fetch(PDO::FETCH_ASSOC);
        if ($uRow) {
            if (!empty($uRow['phone_number'])) $phone = $uRow['phone_number'];
            if (!empty($uRow['username'])) $username = $uRow['username'];
        }

        // Insert into mapping_staff (no wing separation: floor_name = groupName, wing_name = 'All')
        $insertStaffStmt->execute([
            $mappingId,
            $wName,
            $phone,
            $username,
            $wBioId,
            $hostelName,
            $groupName,
            'All'
        ]);

        echo "  [MAPPED] $groupName => Warden: $wName (BioID: $wBioId)\n";
    }

    $pdo->commit();
    echo "SUCCESS: Created $countCreated room-group warden mappings directly from live API!\n";

} catch (Exception $e) {
    if (isset($pdo) && $pdo->inTransaction()) $pdo->rollBack();
    echo "ERROR: " . $e->getMessage() . "\n";
}
