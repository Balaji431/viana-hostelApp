<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');

if (($_SERVER['REQUEST_METHOD'] ?? '') == 'OPTIONS') {
    exit(0);
}

require_once __DIR__ . '/../config/api_config.php';
header('Content-Type: application/json');

if (!isset($_GET['hostel_name'])) {
    echo json_encode(['success' => false, 'message' => 'Hostel name is required']);
    exit;
}
$hostel_name = $_GET['hostel_name'];

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

$filtered_data = [];
foreach ($data['data'] as $room) {
    $api_name = strtolower(trim($room['hostelName']));
    $req_name = strtolower(trim($hostel_name));
    
    // Try exact match first
    $match = ($api_name === $req_name);
    
    // Try: request is "Noyyal", api has "Noyyal Hostel" → strip " hostel"
    if (!$match) {
        $api_stripped = preg_replace('/\s*hostel\s*$/i', '', $api_name);
        $req_stripped = preg_replace('/\s*hostel\s*$/i', '', $req_name);
        $match = ($api_stripped === $req_stripped);
    }
    
    // Try starts-with (e.g. "Porunai" matches "Porunai Hostel (4F - 8F )")
    if (!$match) {
        $match = (strpos($api_name, $req_name) === 0 || strpos($req_name, $api_name) === 0);
    }
    
    if ($match) {
        $filtered_data[] = [
            'id' => $room['id'],
            'room_type' => $room['roomType'],
            'hostel_fee' => $room['amount'],
            'food_fee' => $room['food'],
            'caution_deposit' => $room['cautionDeposit'] ?? 0,
            'occupancy' => $room['occupancy'] ?? '',
            'facility_description' => $room['description'] ?? ''
        ];
    }
}

echo json_encode(['success' => true, 'data' => array_values($filtered_data)]);
