<?php
require_once 'hostel_backend/config/api_config.php';

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

try {
    $groupsData = callExternalApi($apiUrl . '?search=hostel');
    $groups = $groupsData['data']['items'] ?? [];
    $allowedBuildings = ['T09', 'T10', 'T12', 'T14', 'T22', 'T30', 'T32'];
    
    echo "Groups list:\n";
    $totalFilteredRooms = 0;
    $uniqueRooms = [];
    foreach ($groups as $group) {
        $groupCode = $group['group_code'] ?? '';
        $normalized = str_replace('-', '', $groupCode);
        $allowed = in_array($normalized, $allowedBuildings) ? "ALLOWED" : "EXCLUDED";
        
        $locData = callExternalApi($apiUrl . '?group_code=' . urlencode($groupCode));
        $locations = $locData['data']['items'] ?? [];
        
        $roomCount = 0;
        $roomFilteredCount = 0;
        foreach ($locations as $loc) {
            $name = $loc['location_name'] ?? '';
            $code = $loc['location_code'] ?? '';
            $roomCount++;
            
            // Check if it's a room according to our logic
            $normalizedCode = str_replace('=', '-', $code);
            $parts = explode('-', $normalizedCode);
            $floorIdx = -1;
            for ($i = 0; $i < count($parts); $i++) {
                if (preg_match('/^F\d+$/i', $parts[$i])) {
                    $floorIdx = $i;
                    break;
                }
            }
            if ($floorIdx !== -1) {
                $roomCode = isset($parts[$floorIdx + 2]) ? $parts[$floorIdx + 2] : 'N/A';
            } else {
                $roomCode = isset($parts[3]) ? $parts[3] : 'N/A';
            }
            
            if ($roomCode !== 'N/A' && !empty($roomCode)) {
                $isRoom = false;
                $hasRoomKeyword = (stripos($name, 'ROOM') !== false);
                $hasRCodePattern = preg_match('/^R\d+/i', $roomCode);
                if ($hasRoomKeyword || $hasRCodePattern) {
                    $isRoom = true;
                }
                if ($isRoom) {
                    $nonRoomKeywords = ['CANTEEN', 'OFFICE', 'LIBRARY', 'HALL', 'STORE', 'GYM', 'RECEPTION', 'WAITING', 'LAUNDRY'];
                    foreach ($nonRoomKeywords as $kw) {
                        if (stripos($name, $kw) !== false) {
                            $isRoom = false;
                            break;
                        }
                    }
                }
                if ($isRoom) {
                    $roomFilteredCount++;
                    $uniqueRooms[$name] = true;
                }
            }
        }
        
        echo "- {$group['group_name']} ($groupCode) [Normalized: $normalized] [$allowed]: Total items: $roomCount, Rooms: $roomFilteredCount\n";
        if (in_array($normalized, $allowedBuildings)) {
            $totalFilteredRooms += $roomFilteredCount;
        }
    }
    echo "Total room items across allowed groups (with potential duplicates): $totalFilteredRooms\n";
    echo "Total unique rooms by location name: " . count($uniqueRooms) . "\n";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
