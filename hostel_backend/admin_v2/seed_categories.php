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

include '../config/db_config.php';

// Default categories to seed
$defaultCategories = [
    [
        'name' => 'Warden',
        'icon' => 'Icons.people',
        'color' => '#2196F3',
        'codes' => ['Hostel Management', 'Student Discipline', 'Emergency Response']
    ],
    [
        'name' => 'Security',
        'icon' => 'Icons.security',
        'color' => '#FF5722',
        'codes' => ['Gate Security', 'Night Patrol', 'Incident Report']
    ],
    [
        'name' => 'Maintenance',
        'icon' => 'Icons.build',
        'color' => '#4CAF50',
        'codes' => ['Electrical', 'Plumbing', 'Carpentry', 'Cleaning']
    ]
];

foreach ($defaultCategories as $category) {
    $name = $conn->real_escape_string($category['name']);
    $icon = $conn->real_escape_string($category['icon']);
    $color = $conn->real_escape_string($category['color']);
    $codes = $category['codes'];
    
    // Check if category exists
    $check = $conn->query("SELECT id FROM request_categories WHERE name = '$name'");
    if ($check && $check->num_rows == 0) {
        // Insert category
        $conn->query("INSERT INTO request_categories (name, icon_name, color_hex) VALUES ('$name', '$icon', '$color')");
        $cat_id = $conn->insert_id;
        
        // Insert codes
        foreach ($codes as $code) {
            $code_name = $conn->real_escape_string($code);
            $conn->query("INSERT INTO category_codes (category_id, code_name) VALUES ($cat_id, '$code_name')");
        }
    }
}

echo json_encode(array("status" => "success", "message" => "Default categories seeded successfully"));

$conn->close();
?>
