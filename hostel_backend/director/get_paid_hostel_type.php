<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

$register_no = $_GET['register_no'] ?? null;

if (!$register_no) {
    echo json_encode(["success" => false, "message" => "Registration number is required"]);
    exit();
}

// Mock Director Application database/payment logs
$mock_payments = [
    '192425398' => [
        'register_no' => '192425398',
        'fee_paid' => true,
        'paid_amount' => 68000.00,
        'hostel_type' => 'Girls',
        'room_type' => 'AC - B ATTACHED (6 IN 1)',
        'facility' => 'AC',
        'bath_attached' => 'Yes',
        'institution' => 'Saveetha School of Engineering'
    ],
    '192413034' => [
        'register_no' => '192413034',
        'fee_paid' => true,
        'paid_amount' => 80000.00,
        'hostel_type' => 'Girls',
        'room_type' => 'AC - B ATTACHED (4 IN 1)',
        'facility' => 'AC',
        'bath_attached' => 'Yes',
        'institution' => 'Saveetha School of Engineering'
    ],
    '192315010' => [
        'register_no' => '192315010',
        'fee_paid' => true,
        'paid_amount' => 45000.00,
        'hostel_type' => 'Girls',
        'room_type' => 'NON AC (6 IN 1)',
        'facility' => 'Non AC',
        'bath_attached' => 'Yes',
        'institution' => 'Saveetha School of Engineering'
    ]
];

if (array_key_exists($register_no, $mock_payments)) {
    echo json_encode(["success" => true, "data" => $mock_payments[$register_no]]);
} else {
    // Generous default fallback to simulate a paid new student for any other account
    echo json_encode([
        "success" => true,
        "data" => [
            'register_no' => $register_no,
            'fee_paid' => true,
            'paid_amount' => 68000.00,
            'hostel_type' => 'Girls',
            'room_type' => 'AC - B ATTACHED (6 IN 1)',
            'facility' => 'AC',
            'bath_attached' => 'Yes',
            'institution' => 'Saveetha Institute of Medical and Technical Sciences'
        ]
    ]);
}
?>
