<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') exit(0);

require_once '../config/api_config.php';
header('Content-Type: application/json');

$ch = curl_init('https://vstudy.saveetha.com/api/hostel-settings/availability/external');
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'x-client-id: ' . VSTUDY_CLIENT_ID,
    'x-client-secret: ' . VSTUDY_CLIENT_SECRET
]);
$res = curl_exec($ch);
curl_close($ch);

$data = json_decode($res, true);
if (!$data || !isset($data['success']) || !$data['success']) {
    echo json_encode(['success' => false, 'message' => 'Failed to fetch from external API']);
    exit;
}

$summary = [];
foreach ($data['data'] as $room) {
    $h = $room['hostelName'];
    if (!isset($summary[$h])) {
        $summary[$h] = 0;
    }
    $summary[$h]++;
}

echo json_encode(['success' => true, 'data' => $summary]);
