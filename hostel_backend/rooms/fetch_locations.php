<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json");
// Enable gzip output compression — reduces 319KB → ~35KB on the wire
if (extension_loaded('zlib') && !ob_get_level()) {
    ob_start('ob_gzhandler');
}

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once '../config/api_config.php';

$apiUrl = 'https://360.saveetha.com/api/external/get-locations-vstay.php';
// Use uploads/ which is mounted as a Docker volume — survives container rebuilds!
$cacheFile    = __DIR__ . '/../uploads/cache_locations.json';
$cacheLifetime = 3600; // 1 hour in seconds


// 1. Caching Check
if (!isset($_GET['force_refresh']) && file_exists($cacheFile) && (time() - filemtime($cacheFile)) < $cacheLifetime) {
    $cacheData = file_get_contents($cacheFile);
    if ($cacheData !== false) {
        $decoded = json_decode($cacheData, true);
        if ($decoded !== null) {
            // Self-healing check: if cache contains any unwanted P04 (Max Fax) or T05 (Allied Health) codes, force refresh
            $hasUnwanted = false;
            foreach ($decoded as $item) {
                $code = $item['location_code'] ?? '';
                if (strpos($code, 'P04-') !== false || strpos($code, 'T05-') !== false) {
                    $hasUnwanted = true;
                    break;
                }
            }
            
            if (!$hasUnwanted) {
                echo json_encode([
                    "status" => "success",
                    "success" => true,
                    "data" => $decoded,
                    "cached" => true,
                    "cache_time" => date('Y-m-d H:i:s', filemtime($cacheFile))
                ]);
                exit(0);
            } else {
                // Delete stale cache to trigger a fresh filtered fetch
                @unlink($cacheFile);
            }
        }
    }
}

function debugLog($msg) {
    $logFile = __DIR__ . '/../uploads/fetch_debug.log';
    $timestamp = date('Y-m-d H:i:s');
    file_put_contents($logFile, "[$timestamp] $msg\n", FILE_APPEND);
    if (isset($_GET['debug'])) {
        echo "[$timestamp] $msg\n";
        flush();
        if (ob_get_level()) {
            ob_flush();
        }
    }
}

function callExternalApi($url) {
    debugLog("callExternalApi: Start fetching URL: " . $url);
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 10);
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
        debugLog("callExternalApi: Error occurred: " . $error);
        throw new Exception("CURL Error: " . $error);
    }
    debugLog("callExternalApi: Successfully fetched URL. Response length: " . strlen($response));
    return json_decode($response, true);
}

function callExternalApiParallel($urls) {
    debugLog("callExternalApiParallel: Starting parallel fetch for " . count($urls) . " URLs: " . implode(', ', array_keys($urls)));
    $mh = curl_multi_init();
    $handles = [];
    
    foreach ($urls as $key => $url) {
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'X-API-Key: ' . VSTAAY_API_KEY,
            'X-Tunnel-Skip-Anti-Spam-Page: true'
        ]);
        curl_multi_add_handle($mh, $ch);
        $handles[$key] = $ch;
    }
    
    $running = null;
    do {
        curl_multi_exec($mh, $running);
        curl_multi_select($mh);
    } while ($running > 0);
    
    $results = [];
    foreach ($handles as $key => $ch) {
        $response = curl_multi_getcontent($ch);
        $results[$key] = json_decode($response, true);
        curl_multi_remove_handle($mh, $ch);
        curl_close($ch);
    }
    
    curl_multi_close($mh);
    debugLog("callExternalApiParallel: Completed parallel fetch.");
    return $results;
}

try {
    debugLog("main: Starting fetch_locations.php execution");
    // 1. Fetch groups list (Building list)
    $groupsData = callExternalApi($apiUrl . '?search=Hostel');
    if (!isset($groupsData['success']) || !$groupsData['success']) {
        throw new Exception("Failed to fetch groups list: " . ($groupsData['message'] ?? 'Unknown error'));
    }
    
    $groups = $groupsData['data']['items'] ?? [];
    debugLog("main: Fetched " . count($groups) . " groups");
    
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
    $filtered = [];
    
    // Construct parallel fetch URLs
    $urls = [];
    $allowedGroups = [];
    foreach ($groups as $group) {
        $groupCode = $group['group_code'] ?? '';
        if ($groupCode === 'P05' || $groupCode === 'T05') {
            continue;
        }
        $normalizedGroupCode = str_replace('-', '', $groupCode);
        
        if (in_array($normalizedGroupCode, $allowedBuildings)) {
            $urls[$groupCode] = $apiUrl . '?group_code=' . urlencode($groupCode);
            $allowedGroups[$groupCode] = $normalizedGroupCode;
        }
    }
    
    // 2. Fetch locations in parallel
    debugLog("main: Starting parallel fetch for " . count($urls) . " URLs");
    $parallelResults = callExternalApiParallel($urls);
    debugLog("main: Finished parallel fetch");
    
    foreach ($parallelResults as $groupCode => $locData) {
        $normalizedBuildingCode = $allowedGroups[$groupCode];
        $locations = $locData['data']['items'] ?? [];
        debugLog("main: Processing group $groupCode, locations count: " . count($locations));
        
        foreach ($locations as $location) {
            $name = $location['location_name'] ?? '';
            $code = $location['location_code'] ?? '';
            
            if (empty($name) || empty($code)) {
                continue;
            }
            
            // Parse parts
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
            
            // Normalize building code
            $buildingCodeClean = str_replace('-', '', $buildingCode);
            if (!in_array($buildingCodeClean, $allowedBuildings)) {
                continue;
            }
            
            // Use the actual API group code as the building code
            $finalBuildingCode = $groupCode;
            
            // Override location_name using finalBuildingCode
            if ($finalBuildingCode === 'P-05') {
                $location['location_name'] = 'Radiance Inn';
                $name = 'Radiance Inn';
            } elseif ($finalBuildingCode === 'P05') {
                $location['location_name'] = 'Max Fax';
                $name = 'Max Fax';
            } elseif ($finalBuildingCode === 'P10') {
                $location['location_name'] = 'Stunners Den';
                $name = 'Stunners Den';
            }

            // Keep original location_code exactly as returned by API (no prefix remapping)
            // Just normalize '=' separators to '-'
            $location['location_code'] = $normalizedCode;
            
            if ($roomCode === 'N/A' || empty($roomCode)) {
                continue;
            }
            
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
                $filtered[$location['location_code']] = $location;
            }
        }
    }
    
    // Convert associative array back to indexed array to preserve JSON list format
    $filtered = array_values($filtered);
    
    // Save to Cache
    debugLog("main: Saving " . count($filtered) . " rooms to cache: " . $cacheFile);
    file_put_contents($cacheFile, json_encode($filtered));
    debugLog("main: Saved cache successfully");
    
    echo json_encode([
        "status" => "success",
        "success" => true,
        "data" => $filtered,
        "cached" => false
    ]);
    
} catch (Exception $e) {
    debugLog("main: Exception occurred: " . $e->getMessage());
    // Fallback to cached content on error (resilient design)
    if (file_exists($cacheFile)) {
        $cacheData = file_get_contents($cacheFile);
        if ($cacheData !== false) {
            $decoded = json_decode($cacheData, true);
            if ($decoded !== null) {
                echo json_encode([
                    "status" => "success",
                    "success" => true,
                    "data" => $decoded,
                    "cached" => true,
                    "fallback" => true,
                    "message" => "External API error: " . $e->getMessage(),
                    "cache_time" => date('Y-m-d H:i:s', filemtime($cacheFile))
                ]);
                exit(0);
            }
        }
    }
    
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
