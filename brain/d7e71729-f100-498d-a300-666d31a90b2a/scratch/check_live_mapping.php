<?php
// Check what LIVE mapping_staff has for Vaigai floors
$url = 'https://vstay.saveetha.com/api/mappings/location_mappings/read.php';
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_TIMEOUT, 15);
$res = curl_exec($ch);
curl_close($ch);

$data = json_decode($res, true);
echo "=== LIVE mapping_staff / location_mappings ===\n";
if (isset($data['data']) && is_array($data['data'])) {
    foreach ($data['data'] as $row) {
        $hostel = $row['hostel_name'] ?? $row['hostelName'] ?? '';
        $floor  = $row['floor_name'] ?? $row['floorName'] ?? '';
        $name   = $row['name'] ?? $row['staffName'] ?? '';
        $role   = $row['role'] ?? '';
        if (stripos($hostel, 'Vaigai') !== false) {
            echo "  Floor: $floor | Warden: $name | Role: $role\n";
        }
    }
} else {
    echo "Raw response:\n";
    echo substr($res, 0, 3000) . "\n";
}

// Also check via rooms_groups_details endpoint
echo "\n=== LIVE rooms_groups_details for Vaigai Second Floor ===\n";
$url2 = 'https://vstay.saveetha.com/api/rooms/get_rooms.php?hostel_name=Vaigai+Hostel';
$ch2 = curl_init($url2);
curl_setopt($ch2, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch2, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch2, CURLOPT_TIMEOUT, 15);
$res2 = curl_exec($ch2);
curl_close($ch2);

$data2 = json_decode($res2, true);
if (is_array($data2)) {
    $items = $data2['data'] ?? $data2['rooms'] ?? $data2;
    if (is_array($items)) {
        $printed = [];
        foreach ($items as $r) {
            $grp = $r['group_name'] ?? $r['groupName'] ?? '';
            $wn  = $r['warden_name'] ?? $r['wardenName'] ?? '';
            $key = $grp . '|' . $wn;
            if (stripos($grp, 'Second') !== false && !isset($printed[$key])) {
                echo "  Group: $grp | Warden: $wn\n";
                $printed[$key] = true;
            }
        }
    }
} else {
    echo substr($res2, 0, 1000) . "\n";
}
