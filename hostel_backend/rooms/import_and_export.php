<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once '../config/database.php';
require_once '../config/api_config.php';

try {
    $database = new Database();
    $db = $database->getConnection();
    if (!$db) {
        throw new Exception("Could not connect to database.");
    }

    // 1. Perform Location Import from External API
    $apiUrl = 'https://360.saveetha.com/api/external/get-locations-vstay.php';
    
    function callExternalApi($url) {
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 30);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'X-API-Key: ' . VSTAAY_API_KEY,
            'X-Tunnel-Skip-Anti-Spam-Page: true'
        ]);
        $response = curl_exec($ch);
        $error = curl_error($ch);
        curl_close($ch);
        if ($error) {
            throw new Exception("CURL Error: " . $error);
        }
        return json_decode($response, true);
    }
    
    $groupsData = callExternalApi($apiUrl . '?search=Hostel');
    if (isset($groupsData['success']) && $groupsData['success']) {
        $groups = $groupsData['data']['items'] ?? [];
        
        // Explicitly append SCON Ponni building (T09) if not returned by search=Hostel
        $hasT09 = false;
        foreach ($groups as $g) {
            if (($g['group_code'] ?? '') === 'T09') {
                $hasT09 = true;
                break;
            }
        }
        if (!$hasT09) {
            $groups[] = [
                'group_name' => 'SCON Ponni building',
                'group_code' => 'T09',
                'group_status' => 'Active'
            ];
        }

        // Explicitly append Stunners Den (P10) if not returned by search=Hostel
        $hasP10 = false;
        foreach ($groups as $g) {
            if (($g['group_code'] ?? '') === 'P10') {
                $hasP10 = true;
                break;
            }
        }
        if (!$hasP10) {
            $groups[] = [
                'group_name' => 'Stunners Den Boys Hosptel',
                'group_code' => 'P10',
                'group_status' => 'Active'
            ];
        }
        
        $allowedBuildings = ['T09', 'T10', 'T12', 'T14', 'T19', 'T22', 'T30', 'T32', 'P05', 'P10'];
        
        foreach ($groups as $group) {
            $groupCode = $group['group_code'] ?? '';
            if ($groupCode === 'P05' || $groupCode === 'T05') {
                continue;
            }
            $normalizedGroupCode = str_replace('-', '', $groupCode);
            
            if (!in_array($normalizedGroupCode, $allowedBuildings)) {
                continue;
            }
            
            $locData = callExternalApi($apiUrl . '?group_code=' . urlencode($groupCode));
            $locations = $locData['data']['items'] ?? [];
            
            foreach ($locations as $location) {
                $locationName = $location['location_name'] ?? '';
                $locationCode = $location['location_code'] ?? '';
                
                if (empty($locationName) || empty($locationCode)) {
                    continue;
                }
                
                $normalizedCode = str_replace('=', '-', $locationCode);
                $parts = explode('-', $normalizedCode);
                $floorIdx = -1;
                for ($i = 0; $i < count($parts); $i++) {
                    if (preg_match('/^F\d+$/i', $parts[$i])) {
                        $floorIdx = $i;
                        break;
                    }
                }
                
                if ($floorIdx !== -1) {
                    $buildingCode = implode('-', array_slice($parts, 0, $floorIdx));
                    $floorCode = $parts[$floorIdx];
                    $wingCode = isset($parts[$floorIdx + 1]) ? $parts[$floorIdx + 1] : 'N/A';
                    $roomCode = isset($parts[$floorIdx + 2]) ? $parts[$floorIdx + 2] : 'N/A';
                } else {
                    $buildingCode = isset($parts[0]) ? $parts[0] : 'N/A';
                    $floorCode    = isset($parts[1]) ? $parts[1] : 'N/A';
                    $wingCode     = isset($parts[2]) ? $parts[2] : 'N/A';
                    $roomCode     = isset($parts[3]) ? $parts[3] : 'N/A';
                }
                
                if ($roomCode === 'N/A' || empty($roomCode)) {
                    continue;
                }
                
                $normalizedBuildingCode = str_replace('-', '', $buildingCode);
                if (!in_array($normalizedBuildingCode, $allowedBuildings)) {
                    continue;
                }
                
                // Use the actual API group code as the building code
                $finalBuildingCode = $groupCode;
                
                if ($finalBuildingCode === 'P-05') {
                    $locationName = 'Radiance Inn';
                } elseif ($finalBuildingCode === 'P05') {
                    $locationName = 'Max Fax';
                } elseif ($finalBuildingCode === 'P10') {
                    $locationName = 'Stunners Den';
                }

                // Keep original location_code exactly as returned by API (no prefix remapping)
                $locationCode = str_replace('=', '-', $locationCode);
                

                $isRoom = false;
                $hasRoomKeyword = (stripos($locationName, 'ROOM') !== false);
                $hasRCodePattern = preg_match('/^R\d+/i', $roomCode);
                
                if ($hasRoomKeyword || $hasRCodePattern) {
                    $isRoom = true;
                }
                
                if ($isRoom) {
                    $nonRoomKeywords = ['CANTEEN', 'OFFICE', 'LIBRARY', 'HALL', 'STORE', 'GYM', 'RECEPTION', 'WAITING', 'LAUNDRY'];
                    foreach ($nonRoomKeywords as $kw) {
                        if (stripos($locationName, $kw) !== false) {
                            $isRoom = false;
                            break;
                        }
                    }
                }
                
                if (!$isRoom) {
                    continue;
                }
                
                $floorNo = $floorCode;
                switch (strtoupper($floorCode)) {
                    case 'F00': $floorNo = 'Ground'; break;
                    case 'F01': $floorNo = 'First'; break;
                    case 'F02': $floorNo = 'Second'; break;
                    case 'F03': $floorNo = 'Third'; break;
                    case 'F04': $floorNo = 'Fourth'; break;
                    case 'F05': $floorNo = 'Fifth'; break;
                    case 'F06': $floorNo = 'Sixth'; break;
                    case 'F07': $floorNo = 'Seventh'; break;
                    case 'F08': $floorNo = 'Eighth'; break;
                    case 'F09': $floorNo = 'Ninth'; break;
                    case 'F10': $floorNo = 'Tenth'; break;
                    case 'F11': $floorNo = 'Eleventh'; break;
                    case 'F12': $floorNo = 'Twelfth'; break;
                    case 'F13': $floorNo = 'Thirteenth'; break;
                    case 'F14': $floorNo = 'Fourteenth'; break;
                    case 'F15': $floorNo = 'Fifteenth'; break;
                }
                
                $blockNo = $wingCode;
                $roomNo = $roomCode;
                
                $roomCapacity = 0;
                if (strpos($locationName, '8 IN 1') !== false) {
                    $roomCapacity = 8;
                } elseif (strpos($locationName, '6 IN 1') !== false) {
                    $roomCapacity = 6;
                } elseif (strpos($locationName, '4 IN 1') !== false) {
                    $roomCapacity = 4;
                } elseif (strpos($locationName, '2 IN 1') !== false) {
                    $roomCapacity = 2;
                }
                
                // Check for existing room primarily by room_code (physical identifier)
                $checkSql = "SELECT id, room_code FROM room_master WHERE room_code = ? OR (building_code = ? AND floor_no = ? AND block_no = ? AND room_no = ?)";
                $checkStmt = $db->prepare($checkSql);
                $checkStmt->execute([$locationCode, $finalBuildingCode, $floorNo, $blockNo, $roomNo]);
                $existing = $checkStmt->fetch();
                
                if ($existing) {
                    // Update location_name or room_code if missing
                    $updateSql = "UPDATE room_master SET location_name = ?, room_code = COALESCE(NULLIF(room_code, ''), ?) WHERE id = ?";
                    $updateStmt = $db->prepare($updateSql);
                    $updateStmt->execute([$locationName, $locationCode, $existing['id']]);
                    continue;
                }
                
                $sql = "INSERT INTO room_master (location_name, building_code, floor_no, block_no, room_no, room_code, room_type, room_capacity) 
                        VALUES (?, ?, ?, ?, ?, ?, 'Not Assigned', ?)";
                $stmt = $db->prepare($sql);
                $stmt->execute([$locationName, $finalBuildingCode, $floorNo, $blockNo, $roomNo, $locationCode, $roomCapacity]);
            }
        }
    }

    // 2. Query updated database and output as downloadable CSV response
    $exportSql = "SELECT * FROM room_master ORDER BY building_code, floor_no, block_no, room_no";
    $exportStmt = $db->query($exportSql);
    $exportRooms = $exportStmt->fetchAll(PDO::FETCH_ASSOC);

    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=room_master_export.csv');
    
    $output = fopen('php://output', 'w');
    fprintf($output, chr(0xEF).chr(0xBB).chr(0xBF));
    fputcsv($output, ['Hostel Name', 'Room Code', 'Room Type', 'Capacity']);

    function cleanHostelNameImportAndExport($rawName) {
        $hostelMapping = [
            'KAVERI' => 'Kaveri Hostel',
            'VAIGAI' => 'Vaigai Hostel',
            'KRISHNA' => 'Krishna Hostel',
            'KRISHAN' => 'Krishna Hostel',
            'NOYYAL' => 'Noyyal Hostel',
            'PONNI' => 'Ponni Hostel',
            'SIRUVANI' => 'Siruvani Hostel',
            'PORUNAI' => 'Porunai Hostel (4F - 8F )',
            'PALAR' => 'Palar Hostel',
            'ALLIED' => 'Allied Health Sciences',
            'RADIANTS' => 'Radiance Inn',
            'STUNNER' => 'Stunners Den',
        ];
        $upperName = strtoupper($rawName);
        foreach ($hostelMapping as $key => $value) {
            if (strpos($upperName, $key) !== false) {
                return $value;
            }
        }
        return $rawName;
    }

    foreach ($exportRooms as $row) {
        fputcsv($output, [
            cleanHostelNameImportAndExport($row['location_name'] ?? ''),
            $row['room_code'] ?? '',
            $row['room_type'] ?? 'Not Assigned',
            $row['room_capacity'] ?? '0'
        ]);
    }
    
    fclose($output);
    
    // Also save it locally in the uploads folder for back-up / volume mount sync
    try {
        $csvFile = __DIR__ . '/../uploads/room_master_export.csv';
        if (!file_exists(__DIR__ . '/../uploads')) {
            mkdir(__DIR__ . '/../uploads', 0777, true);
        }
        $backupOutput = fopen($csvFile, 'w');
        if ($backupOutput) {
            fprintf($backupOutput, chr(0xEF).chr(0xBB).chr(0xBF));
            fputcsv($backupOutput, ['Hostel Name', 'Room Code', 'Room Type', 'Capacity']);
            foreach ($exportRooms as $row) {
                fputcsv($backupOutput, [
                    cleanHostelNameImportAndExport($row['location_name'] ?? ''),
                    $row['room_code'] ?? '',
                    $row['room_type'] ?? 'Not Assigned',
                    $row['room_capacity'] ?? '0'
                ]);
            }
            fclose($backupOutput);
        }
    } catch (Exception $ex) {}
    
    exit(0);

} catch (Exception $e) {
    header('Content-Type: text/html');
    echo "<h3>Import and Export Error: " . htmlspecialchars($e->getMessage()) . "</h3>";
}
?>
