<?php
// Fetch ALL live location mappings and find Vaigai Second Floor
$url = 'https://vstay.saveetha.com/api/mappings/location_mappings/read.php';
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_TIMEOUT, 30);
$res = curl_exec($ch);
curl_close($ch);

$data = json_decode($res, true);
echo "=== LIVE location_mappings - Vaigai Hostel Floors ===\n";

if (isset($data['data']) && is_array($data['data'])) {
    foreach ($data['data'] as $row) {
        $hostel = $row['hostel_name'] ?? '';
        $floor  = $row['zone_name'] ?? $row['floor_name'] ?? '';
        $staff  = $row['staff'] ?? [];
        
        if (stripos($hostel, 'Vaigai') !== false) {
            echo "\nFloor: $floor\n";
            foreach ($staff as $s) {
                echo "  Staff: {$s['name']} | Role: {$s['role']} | Floor: {$s['floor_name']}\n";
            }
        }
    }
}
