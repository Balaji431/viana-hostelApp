<?php
// Check what the LIVE rooms_groups_details actually has for room T32-F02-W0-R16
// by reading it via the live API response path (not profile)

$url = 'https://vstay.saveetha.com/api/get_user_data.php?id=4173&role=student';
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_TIMEOUT, 10);
$res = curl_exec($ch);
curl_close($ch);

$d = json_decode($res, true)['data'] ?? [];
echo "Live API warden: [" . ($d['warden'] ?? '') . "]\n";
echo "Live API room_allocation: [" . ($d['room_allocation'] ?? '') . "]\n";
echo "Live API room_no: [" . ($d['room_no'] ?? '') . "]\n";
echo "Live API floor_name: [" . ($d['floor_name'] ?? '') . "]\n";
echo "\nFull response:\n$res\n";
