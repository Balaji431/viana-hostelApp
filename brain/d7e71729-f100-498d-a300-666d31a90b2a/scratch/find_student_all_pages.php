<?php
require_once __DIR__ . '/../../../hostel_backend/config/api_config.php';

// Paginate through ALL pages to find student 192511250
function fetchAllPages($baseUrl, $headers) {
    $page = 1;
    $limit = 100;
    $all = [];
    while (true) {
        $url = $baseUrl . "?page=$page&limit=$limit";
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_TIMEOUT, 30);
        $res = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($code != 200) break;
        $json = json_decode($res, true);
        $batch = $json['data'] ?? $json ?? [];
        if (!is_array($batch) || empty($batch)) break;
        $all = array_merge($all, $batch);
        if (count($batch) < $limit) break;
        $page++;
        usleep(15000);
    }
    return $all;
}

$headers = [
    "X-Client-Id: " . VSTUDY_CLIENT_ID,
    "X-Client-Secret: " . VSTUDY_CLIENT_SECRET
];

echo "=== Fetching ALL booked rooms (all pages) ===\n";
$bookedRooms = fetchAllPages('https://vstudy.saveetha.com/api/hostel-settings/booked-rooms/external', $headers);
echo "Total: " . count($bookedRooms) . "\n";

$found = false;
foreach ($bookedRooms as $b) {
    $roll = trim($b['registerNumber'] ?? $b['rollNumber'] ?? '');
    if ($roll === '192511250') {
        echo "\n=== student 192511250 FOUND in booked-rooms ===\n";
        print_r($b);
        $found = true;
    }
}
if (!$found) echo "NOT found in booked-rooms.\n";

echo "\n=== Fetching ALL paid apps (all pages) ===\n";
$paidApps = fetchAllPages('https://vstudy.saveetha.com/api/hostel-applications/paid', $headers);
echo "Total: " . count($paidApps) . "\n";

$found2 = false;
foreach ($paidApps as $app) {
    $roll = trim($app['student']['rollNumber'] ?? $app['student']['registerNumber'] ?? '');
    if ($roll === '192511250') {
        echo "\n=== student 192511250 FOUND in paid-apps ===\n";
        print_r($app);
        $found2 = true;
    }
}
if (!$found2) echo "NOT found in paid apps.\n";
