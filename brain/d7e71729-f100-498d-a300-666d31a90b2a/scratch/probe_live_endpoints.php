<?php
// Try to find the correct live endpoint for location mappings and rooms
$endpoints = [
    'https://vstay.saveetha.com/api/mappings/location_mappings/read.php',
    'https://vstay.saveetha.com/api/rooms/sync_room_master.php',
    'https://vstay.saveetha.com/api/rooms/get_room_groups.php',
    'https://vstay.saveetha.com/api/admin/get_mappings.php',
];

foreach ($endpoints as $url) {
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_TIMEOUT, 10);
    $res = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    echo "[$code] $url\n";
    if ($code == 200) {
        echo substr($res, 0, 500) . "\n\n";
    }
}

// Try to call the live sync to see if it outputs log
echo "\n=== Calling live sync_room_master.php ===\n";
$ch = curl_init('https://vstay.saveetha.com/api/rooms/sync_room_master.php');
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_TIMEOUT, 30);
$res = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);
echo "HTTP $code | Response: " . substr($res, 0, 1000) . "\n";
