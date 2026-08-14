<?php
// Check what warden_name rooms_groups_details has for Room T32-F02-W0-R16 on LIVE
// by looking at the live student API
$url = 'https://vstay.saveetha.com/api/get_user_data.php?id=4173&role=student';
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_TIMEOUT, 10);
$res = curl_exec($ch);
curl_close($ch);
$data = json_decode($res, true);
echo "=== LIVE get_user_data for Gurikani Amrutha ===\n";
echo "warden: "   . ($data['data']['warden']     ?? 'N/A') . "\n";
echo "floor_name: ". ($data['data']['floor_name'] ?? 'N/A') . "\n";
echo "room_no: "  . ($data['data']['room_no']    ?? 'N/A') . "\n";
echo "room_code: ". ($data['data']['room_code']  ?? 'N/A') . "\n";
echo "\nFull data:\n";
print_r($data['data'] ?? []);
