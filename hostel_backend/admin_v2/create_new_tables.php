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

$database = new DatabaseMysqli();
$conn = $database->getConnection();

// Create new table if it doesn't exist
$conn->query("CREATE TABLE IF NOT EXISTS new_categories1 (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    icon_name VARCHAR(255) NOT NULL,
    color_hex VARCHAR(7) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)");

// Create new codes table if it doesn't exist
$conn->query("CREATE TABLE IF NOT EXISTS new_category_codes1 (
    id INT AUTO_INCREMENT PRIMARY KEY,
    category_id INT NOT NULL,
    code_name VARCHAR(255) NOT NULL,
    FOREIGN KEY (category_id) REFERENCES new_categories1(id) ON DELETE CASCADE,
    INDEX (category_id)
)");

// Check if data already exists to avoid duplicates
$check = $conn->query("SELECT COUNT(*) as count FROM new_categories1");
$row = $check->fetch_assoc();

if ($row['count'] == 0) {
    // Insert sample data
    $sample_categories = [
        ['name' => 'Warden', 'icon' => 'Icons.people', 'color' => '#2196F3', 'codes' => ['Hostel Management', 'Student Discipline', 'Emergency Response']],
        ['name' => 'Security', 'icon' => 'Icons.security', 'color' => '#F44336', 'codes' => ['Gate Security', 'Night Patrol', 'Incident Report']],
        ['name' => 'Maintenance', 'icon' => 'Icons.build', 'color' => '#4CAF50', 'codes' => ['Electrical', 'Plumbing', 'Carpentry', 'Cleaning']]
    ];

    foreach ($sample_categories as $cat_data) {
        $name = $conn->real_escape_string($cat_data['name']);
        $icon = $conn->real_escape_string($cat_data['icon']);
        $color = $conn->real_escape_string($cat_data['color']);
        
        // Insert category
        $conn->query("INSERT INTO new_categories1 (name, icon_name, color_hex) VALUES ('$name', '$icon', '$color')");
        $category_id = $conn->insert_id;
        
        // Insert codes
        foreach ($cat_data['codes'] as $code) {
            $code_name = $conn->real_escape_string($code);
            $conn->query("INSERT INTO new_category_codes1 (category_id, code_name) VALUES ($category_id, '$code_name')");
        }
    }
}

// Get all categories with codes
$sql = "SELECT c.id, c.name, c.icon_name, c.color_hex,
        GROUP_CONCAT(cc.code_name SEPARATOR ', ') as codes
        FROM new_categories1 c 
        LEFT JOIN new_category_codes1 cc ON c.id = cc.category_id 
        GROUP BY c.id, c.name, c.icon_name, c.color_hex 
        ORDER BY c.id";

$result = $conn->query($sql);
$categories = [];

if ($result && $result->num_rows > 0) {
    while ($row = $result->fetch_assoc()) {
        $codes = !empty($row['codes']) ? explode(', ', $row['codes']) : [];
        $categories[] = [
            'id' => $row['id'],
            'name' => $row['name'],
            'icon' => $row['icon_name'],
            'color' => $row['color_hex'],
            'codes' => $codes
        ];
    }
}

echo json_encode([
    'success' => true,
    'status' => 'success',
    'data' => $categories
]);

$conn->close();
?>
