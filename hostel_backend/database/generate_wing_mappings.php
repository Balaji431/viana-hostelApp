<?php
require_once __DIR__ . '/../config/database.php';

try {
    echo "Starting automated wing-level mapping generation...\n";

    // 1. Fetch hostel ID map from hostel_type
    $hostelMap = [];
    $hStmt = $pdo->query("SELECT id, hostel_name FROM hostel_type");
    while ($h = $hStmt->fetch(PDO::FETCH_ASSOC)) {
        $hostelMap[trim(strtolower($h['hostel_name']))] = $h['id'];
    }

    // 2. Fetch distinct hostel, floor (group_name), warden info, and room_number list from rooms_groups_details
    $rgStmt = $pdo->query("
        SELECT hostel_name, group_name, warden_name, warden_user_id, room_number
        FROM rooms_groups_details
        WHERE room_number IS NOT NULL AND room_number != ''
    ");

    $wingData = []; // [hostel_name][floor_name][wing_code] => ['warden_name' => ..., 'warden_user_id' => ..., 'room_count' => ...]

    while ($row = $rgStmt->fetch(PDO::FETCH_ASSOC)) {
        $hName = trim($row['hostel_name'] ?? '');
        $gName = trim($row['group_name'] ?? '');
        $rNum  = trim($row['room_number'] ?? '');
        $wName = trim($row['warden_name'] ?? '');
        $wUser = trim($row['warden_user_id'] ?? '');

        if (empty($hName) || empty($gName)) continue;

        // Parse floor label cleanly (e.g., "Kaveri Ground Floor" -> "Ground" or keep "Ground")
        // Extract wing code from room_number (e.g. T12-F00-WA1-R01 -> WA1, or P-05-F00-W0-R06 -> W0)
        $parts = explode('-', $rNum);
        $wingCode = 'W0';
        if (count($parts) >= 4) {
            $wingCode = trim($parts[2]);
        } elseif (count($parts) == 3) {
            $wingCode = trim($parts[1]);
        }

        // Simplify floor name for zone_id (e.g. "Kaveri Ground Floor" -> "Ground" or keep "Kaveri Ground Floor")
        // Standardize floor_name
        $floorClean = $gName;
        if (preg_match('/(ground|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\s*floor/i', $gName, $m)) {
            $floorClean = ucfirst(strtolower($m[1]));
        }

        $key = "$hName|$floorClean|$wingCode";
        if (!isset($wingData[$key])) {
            $wingData[$key] = [
                'hostel_name'    => $hName,
                'floor_name'     => $floorClean,
                'raw_group_name' => $gName,
                'wing_code'      => $wingCode,
                'warden_name'    => $wName,
                'warden_user_id' => $wUser,
                'room_count'     => 0
            ];
        }
        $wingData[$key]['room_count']++;

        if (!empty($wName) && empty($wingData[$key]['warden_name'])) {
            $wingData[$key]['warden_name'] = $wName;
            $wingData[$key]['warden_user_id'] = $wUser;
        }
    }

    // 3. Helper to look up warden phone & username/bio_id
    $wardenDetailsStmt = $pdo->prepare("
        SELECT username, phone_number FROM users WHERE full_name = ? AND role = 'warden' LIMIT 1
    ");
    $staffUserDetailsStmt = $pdo->prepare("
        SELECT bio_id, phone FROM staff_users WHERE name = ? LIMIT 1
    ");

    // Clear obsolete location_mappings & mapping_staff
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

    $countCreated = 0;
    foreach ($wingData as $item) {
        $hName = $item['hostel_name'];
        $fName = $item['floor_name'];
        $wCode = $item['wing_code'];
        $wName = $item['warden_name'];

        // Determine hostel_id
        $hId = 1;
        $hLower = strtolower($hName);
        foreach ($hostelMap as $hKey => $idVal) {
            if (strpos($hLower, preg_replace('/\s*hostel\s*/i', '', $hKey)) !== false || strpos($hKey, preg_replace('/\s*hostel\s*/i', '', $hLower)) !== false) {
                $hId = $idVal;
                break;
            }
        }

        // Insert into location_mappings
        $insertMappingStmt->execute([$hId, $fName, $wCode]);
        $mappingId = $pdo->lastInsertId();
        $countCreated++;

        // Determine Warden details
        if (empty($wName)) {
            $wName = "Manoj A";
        }

        $phone = "8072768337";
        $username = "20018";

        // Query users table for real warden phone & bio_id
        $wardenDetailsStmt->execute([$wName]);
        $uRow = $wardenDetailsStmt->fetch(PDO::FETCH_ASSOC);
        if ($uRow) {
            if (!empty($uRow['phone_number'])) $phone = $uRow['phone_number'];
            if (!empty($uRow['username'])) $username = $uRow['username'];
        } else {
            $staffUserDetailsStmt->execute([$wName]);
            $sRow = $staffUserDetailsStmt->fetch(PDO::FETCH_ASSOC);
            if ($sRow) {
                if (!empty($sRow['phone'])) $phone = $sRow['phone'];
                if (!empty($sRow['bio_id'])) $username = $sRow['bio_id'];
            }
        }

        // Insert into mapping_staff
        $insertStaffStmt->execute([
            $mappingId,
            $wName,
            $phone,
            $username,
            $username,
            $hName,
            $fName,
            $wCode
        ]);
    }

    $pdo->commit();
    echo "SUCCESS: Created $countCreated distinct wing-level mappings across all hostels!\n";

} catch (Exception $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    echo "ERROR: " . $e->getMessage() . "\n";
}
?>
