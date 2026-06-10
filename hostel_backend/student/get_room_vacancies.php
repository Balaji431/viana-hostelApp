<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit(0);
}

try {
    // Get room vacancies from database
    // For now, we'll return mock data structure but this can be enhanced
    // to fetch actual room data from your room allocation system
    
    $vacancies = [
        [
            'id' => 'h1',
            'name' => 'Block A',
            'zones' => [
                [
                    'id' => 'z1',
                    'name' => 'Ground Floor',
                    'subZones' => [
                        [
                            'id' => 'sz1',
                            'name' => 'Wing A',
                            'rooms' => [
                                ['id' => 'r1', 'number' => 'A-101', 'capacity' => 2, 'occupied' => 1],
                                ['id' => 'r2', 'number' => 'A-102', 'capacity' => 2, 'occupied' => 2],
                                ['id' => 'r3', 'number' => 'A-103', 'capacity' => 3, 'occupied' => 0],
                            ]
                        ],
                        [
                            'id' => 'sz2',
                            'name' => 'Wing B',
                            'rooms' => [
                                ['id' => 'r4', 'number' => 'A-104', 'capacity' => 2, 'occupied' => 2],
                                ['id' => 'r5', 'number' => 'A-105', 'capacity' => 2, 'occupied' => 1],
                            ]
                        ]
                    ]
                ],
                [
                    'id' => 'z2',
                    'name' => '2nd Floor',
                    'subZones' => [
                        [
                            'id' => 'sz3',
                            'name' => 'Main Wing',
                            'rooms' => [
                                ['id' => 'r6', 'number' => 'A-201', 'capacity' => 3, 'occupied' => 1],
                                ['id' => 'r7', 'number' => 'A-202', 'capacity' => 2, 'occupied' => 0],
                                ['id' => 'r8', 'number' => 'A-204', 'capacity' => 2, 'occupied' => 2],
                            ]
                        ]
                    ]
                ]
            ]
        ],
        [
            'id' => 'h2',
            'name' => 'Block B',
            'zones' => [
                [
                    'id' => 'z3',
                    'name' => 'Ground Floor',
                    'subZones' => [
                        [
                            'id' => 'sz4',
                            'name' => 'East Wing',
                            'rooms' => [
                                ['id' => 'r9', 'number' => 'B-101', 'capacity' => 2, 'occupied' => 1],
                                ['id' => 'r10', 'number' => 'B-102', 'capacity' => 3, 'occupied' => 3],
                            ]
                        ]
                    ]
                ]
            ]
        ]
    ];
    
    echo json_encode([
        'status' => 'success',
        'message' => 'Room vacancies retrieved successfully',
        'data' => $vacancies
    ]);
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}

$conn->close();
?>
