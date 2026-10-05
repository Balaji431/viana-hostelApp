<?php
/**
 * get_room_pricing.php
 * Fetches dynamic multi-duration renewal and short stay pricing from VStudy external API.
 */

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/api_config.php';
require_once __DIR__ . '/../config/database.php';

$raw = file_get_contents('php://input');
$input = json_decode($raw, true) ?? [];

$roomType = trim($input['roomType'] ?? $input['room_type'] ?? $_GET['roomType'] ?? $_GET['room_type'] ?? '4 IN 1 AC');

if (empty($roomType)) {
    echo json_encode(['success' => false, 'message' => 'roomType is required']);
    exit();
}

// Normalize roomType string
$normalizedType = preg_replace('/\s+/', ' ', trim($roomType));

$pricingApiUrl = defined('VSTUDY_PRICING_API_URL') ? VSTUDY_PRICING_API_URL : 'https://xp7w1bhk-3000.inc1.devtunnels.ms/api/hostel-applications/external/pricing';
$clientId = defined('VSTUDY_CLIENT_ID') ? VSTUDY_CLIENT_ID : '';
$clientSecret = defined('VSTUDY_CLIENT_SECRET') ? VSTUDY_CLIENT_SECRET : '';

$ch = curl_init($pricingApiUrl);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode(['roomType' => $normalizedType]));
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Content-Type: application/json',
    'x-client-id: ' . $clientId,
    'x-client-secret: ' . $clientSecret
]);
curl_setopt($ch, CURLOPT_TIMEOUT, 5);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
$res = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($code === 200 && !empty($res)) {
    $data = json_decode($res, true);
    if (!empty($data['success']) && !empty($data['data'])) {
        echo json_encode($data);
        exit();
    }
}

// Fallback pricing calculation matching VStudy ERP formula:
// 1-day / nightly rate = (annual room rent ÷ 365, rounded up to the next ₹50) × 3. Food and caution are not included.
$baseRent = 70000;
$baseFood = 50000;

try {
    $database = new Database();
    $db = $database->getConnection();
    if ($db) {
        $stmtDb = $db->prepare("SELECT amount, total_beds FROM rooms_groups_details WHERE LOWER(TRIM(room_type)) = LOWER(TRIM(?)) AND amount > 0 LIMIT 1");
        $stmtDb->execute([$normalizedType]);
        $rowDb = $stmtDb->fetch(PDO::FETCH_ASSOC);
        if ($rowDb && (float)$rowDb['amount'] > 0) {
            $baseRent = (float)$rowDb['amount'];
        }
    }
} catch (Exception $eDb) {}

if ($baseRent <= 70000) {
    if (stripos($normalizedType, 'single') !== false || stripos($normalizedType, '1 in 1') !== false) {
        $baseRent = 120000;
    } elseif (stripos($normalizedType, 'super deluxe') !== false && (stripos($normalizedType, '4 in 1') !== false || stripos($normalizedType, '4-in-1') !== false)) {
        $baseRent = 95000;
    } elseif (stripos($normalizedType, 'super deluxe') !== false && (stripos($normalizedType, '3 in 1') !== false || stripos($normalizedType, '3-in-1') !== false)) {
        $baseRent = 110000;
    } elseif (stripos($normalizedType, '2 in 1') !== false || stripos($normalizedType, 'double') !== false) {
        $baseRent = 90000;
    } elseif (stripos($normalizedType, '3 in 1') !== false || stripos($normalizedType, 'triple') !== false) {
        $baseRent = 75000;
    }
}

$perDay = (int)(ceil(($baseRent / 365.0) / 50.0) * 50.0 * 3);

$fallback = [
    'success' => true,
    'data' => [
        'roomType' => $normalizedType,
        'occupancy' => 4,
        'ebInclusive' => false,
        'freshBooking' => [
            'roomRent' => $baseRent,
            'food' => $baseFood,
            'cautionDeposit' => 5000,
            'total' => $baseRent + $baseFood + 5000
        ],
        'renewals' => [
            [
                'months' => 12,
                'premiumMultiplier' => 1.0,
                'roomRent' => $baseRent,
                'food' => $baseFood,
                'cautionDeposit' => 0,
                'total' => $baseRent + $baseFood
            ],
            [
                'months' => 9,
                'premiumMultiplier' => 1.32,
                'roomRent' => round($baseRent * 0.99),
                'food' => round($baseFood * 0.75),
                'cautionDeposit' => 0,
                'total' => round($baseRent * 0.99) + round($baseFood * 0.75)
            ],
            [
                'months' => 6,
                'premiumMultiplier' => 1.56,
                'roomRent' => round($baseRent * 0.78),
                'food' => round($baseFood * 0.50),
                'cautionDeposit' => 0,
                'total' => round($baseRent * 0.78) + round($baseFood * 0.50)
            ],
            [
                'months' => 3,
                'premiumMultiplier' => 1.8,
                'roomRent' => round($baseRent * 0.45),
                'food' => round($baseFood * 0.25),
                'cautionDeposit' => 0,
                'total' => round($baseRent * 0.45) + round($baseFood * 0.25)
            ]
        ],
        'shortStay' => [
            'perDay' => $perDay,
            'premiumMultiplier' => 3
        ]
    ]
];

echo json_encode($fallback);
