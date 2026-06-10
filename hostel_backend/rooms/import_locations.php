<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once '../config/database.php';
require_once '../config/api_config.php';

try {
    $database = new Database();
    $db = $database->getConnection();

    // Fetch locations from external API
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
    
    // 1. Fetch groups list
    $groupsData = callExternalApi($apiUrl . '?search=hostel');
    if (!isset($groupsData['success']) || !$groupsData['success']) {
        throw new Exception("Failed to fetch groups list: " . ($groupsData['message'] ?? 'Unknown error'));
    }
    
    $groups = $groupsData['data']['items'] ?? [];
    $allowedBuildings = ['T09', 'T10', 'T12', 'T14', 'T19', 'T22', 'T30', 'T32', 'P05'];
    
    $imported = 0;
    $duplicates = 0;
    
    foreach ($groups as $group) {
        $groupCode = $group['group_code'] ?? '';
        $normalizedGroupCode = str_replace('-', '', $groupCode);
        
        if (!in_array($normalizedGroupCode, $allowedBuildings)) {
            continue;
        }
        
        // 2. Fetch locations for this allowed group
        $locData = callExternalApi($apiUrl . '?group_code=' . urlencode($groupCode));
        $locations = $locData['data']['items'] ?? [];
        
        foreach ($locations as $location) {
            $locationName = $location['location_name'] ?? '';
            $locationCode = $location['location_code'] ?? '';
            
            if (empty($locationName) || empty($locationCode)) {
                continue;
            }
            
            // Robust parsing logic to split location_code (e.g. "T12-F03-WB1-R06" or "T05-F08-WA=R01")
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
            
            // Only import locations that are actual rooms (have room numbers and are not "N/A")
            if ($roomCode === 'N/A' || empty($roomCode)) {
                continue;
            }
            
            // Normalize building code
            $normalizedBuildingCode = str_replace('-', '', $buildingCode);
            if (!in_array($normalizedBuildingCode, $allowedBuildings)) {
                continue;
            }
            
            // For Krishna Hostel, use "T-30" as building code, otherwise use the normalized code (T12, T22, T32, etc.)
            $finalBuildingCode = ($normalizedBuildingCode === 'T30') ? 'T-30' : $normalizedBuildingCode;
            
            // Override location_name for Radiants INN (P-05)
            if ($normalizedBuildingCode === 'P05') {
                $locationName = 'Radiants INN Ladies Hostel Building';
            }
            
            // Skip non-rooms by checking if location name contains ROOM or code has Rxx
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
            
            // Normalize floor
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
            
            // Extract capacity from location name
            $roomCapacity = 0; // Default (was 4)
            if (strpos($locationName, '8 IN 1') !== false) {
                $roomCapacity = 8;
            } elseif (strpos($locationName, '6 IN 1') !== false) {
                $roomCapacity = 6;
            } elseif (strpos($locationName, '4 IN 1') !== false) {
                $roomCapacity = 4;
            } elseif (strpos($locationName, '2 IN 1') !== false) {
                $roomCapacity = 2;
            }
            
            // Check for duplicate
            $checkSql = "SELECT id, room_code FROM room_master WHERE location_name = ? AND building_code = ? AND floor_no = ? AND block_no = ? AND room_no = ?";
            $checkStmt = $db->prepare($checkSql);
            $checkStmt->execute([$locationName, $finalBuildingCode, $floorNo, $blockNo, $roomNo]);
            $existing = $checkStmt->fetch();
            
            if ($existing) {
                // If it exists but doesn't have a room_code, update it!
                if (empty($existing['room_code'])) {
                    $updateSql = "UPDATE room_master SET room_code = ? WHERE id = ?";
                    $updateStmt = $db->prepare($updateSql);
                    $updateStmt->execute([$locationCode, $existing['id']]);
                }
                $duplicates++;
                continue;
            }
            
            // Insert with default room_type = 'Not Assigned' and extracted capacity
            $sql = "INSERT INTO room_master (location_name, building_code, floor_no, block_no, room_no, room_code, room_type, room_capacity) 
                    VALUES (?, ?, ?, ?, ?, ?, 'Not Assigned', ?)";
            $stmt = $db->prepare($sql);
            $stmt->execute([$locationName, $finalBuildingCode, $floorNo, $blockNo, $roomNo, $locationCode, $roomCapacity]);
            $imported++;
        }
    }
    
    echo json_encode([
        "status" => "success",
        "success" => true,
        "message" => "Import completed",
        "imported" => $imported,
        "duplicates" => $duplicates
    ]);
    
} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
