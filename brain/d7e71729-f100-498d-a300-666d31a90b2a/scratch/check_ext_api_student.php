<?php
require_once __DIR__ . '/../../../hostel_backend/config/api_config.php';

// Fetch booked rooms from external API and find student 192511250
$url = 'https://vstudy.saveetha.com/api/hostel-settings/booked-rooms/external?page=1&limit=500';
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    "X-Client-Id: " . VSTUDY_CLIENT_ID,
    "X-Client-Secret: " . VSTUDY_CLIENT_SECRET
]);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_TIMEOUT, 30);
$res = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

echo "HTTP $code\n";
$data = json_decode($res, true);
$items = $data['data'] ?? $data ?? [];

echo "Total booked rooms: " . count($items) . "\n\n";

// Find our student
foreach ($items as $b) {
    $roll = trim($b['registerNumber'] ?? $b['rollNumber'] ?? '');
    if ($roll === '192511250') {
        echo "=== FOUND student 192511250 in booked-rooms ===\n";
        print_r($b);
        echo "\nroomNumber field: [" . ($b['roomNumber'] ?? 'NOT SET') . "]\n";
        echo "hostelName field: [" . ($b['hostelName'] ?? 'NOT SET') . "]\n";
        echo "group_name field: [" . ($b['group_name'] ?? $b['groupName'] ?? 'NOT SET') . "]\n";
    }
}

// Also check paid apps
echo "\n=== Checking paid applications ===\n";
$url2 = 'https://vstudy.saveetha.com/api/hostel-applications/paid?page=1&limit=500';
$ch2 = curl_init($url2);
curl_setopt($ch2, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch2, CURLOPT_HTTPHEADER, [
    "X-Client-Id: " . VSTUDY_CLIENT_ID,
    "X-Client-Secret: " . VSTUDY_CLIENT_SECRET
]);
curl_setopt($ch2, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch2, CURLOPT_TIMEOUT, 30);
$res2 = curl_exec($ch2);
$code2 = curl_getinfo($ch2, CURLINFO_HTTP_CODE);
curl_close($ch2);

echo "HTTP $code2\n";
$data2 = json_decode($res2, true);
$items2 = $data2['data'] ?? $data2 ?? [];
echo "Total paid apps: " . count($items2) . "\n";

foreach ($items2 as $app) {
    $roll = trim($app['student']['rollNumber'] ?? $app['student']['registerNumber'] ?? '');
    if ($roll === '192511250') {
        echo "=== FOUND student 192511250 in paid apps ===\n";
        print_r($app);
        echo "\nroomNumber: [" . ($app['room']['roomNumber'] ?? 'NOT SET') . "]\n";
        echo "hostelName: [" . ($app['hostel']['name'] ?? 'NOT SET') . "]\n";
        echo "group_name: [" . ($app['room']['group_name'] ?? $app['room']['groupName'] ?? 'NOT SET') . "]\n";
    }
}
