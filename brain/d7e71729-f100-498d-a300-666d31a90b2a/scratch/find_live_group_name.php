<?php
// Find the EXACT group_name and warden_name for room T32-F02-W0-R16 on the live server
// We do this via a custom diagnostic endpoint

// Try the live location mappings to see all Vaigai groups
$url = 'https://vstay.saveetha.com/api/mappings/location_mappings/read.php';
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_TIMEOUT, 15);
$res = curl_exec($ch);
curl_close($ch);

$data = json_decode($res, true);
echo "=== ALL Vaigai groups on live (location_mappings) ===\n";
foreach ($data['data'] ?? [] as $row) {
    if (stripos($row['hostel_name'] ?? '', 'Vaigai') !== false) {
        $zoneName = $row['zone_name'] ?? $row['floor_name'] ?? '';
        $staff = $row['staff'] ?? [];
        $wardenName = '';
        foreach ($staff as $s) {
            if (strtolower($s['role'] ?? '') === 'warden') {
                $wardenName = $s['name'];
                break;
            }
        }
        echo "  zone_name/group_name: [$zoneName] | warden: [$wardenName]\n";
    }
}

// Also get actual rooms_groups_details data from live via the room info endpoint  
echo "\n=== Checking live get_user_data rooms_groups_details join result ===\n";
$url2 = 'https://vstay.saveetha.com/api/get_user_data.php?id=4173&role=student';
$ch2 = curl_init($url2);
curl_setopt($ch2, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch2, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch2, CURLOPT_TIMEOUT, 10);
$res2 = curl_exec($ch2);
curl_close($ch2);
$d = json_decode($res2, true)['data'] ?? [];
echo "group_name (from rooms_groups_details JOIN): [" . ($d['group_name'] ?? '') . "]\n";
echo "floor_name: [" . ($d['floor_name'] ?? '') . "]\n";
echo "warden from live API: [" . ($d['warden'] ?? '') . "]\n";
echo "room_no: [" . ($d['room_no'] ?? '') . "]\n";
