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

// Drop tables if they exist to ensure clean state
$conn->query("SET FOREIGN_KEY_CHECKS = 0");
$conn->query("DROP TABLE IF EXISTS category_codes");
$conn->query("DROP TABLE IF EXISTS request_categories");
$conn->query("SET FOREIGN_KEY_CHECKS = 1");

$sql = "CREATE TABLE request_categories (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    icon_name VARCHAR(50) NOT NULL,
    color_hex VARCHAR(10) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)";

if ($conn->query($sql) === TRUE) {
    echo "Table 'request_categories' created. ";
    
    $sql_codes = "CREATE TABLE category_codes (
        id INT AUTO_INCREMENT PRIMARY KEY,
        category_id INT NOT NULL,
        code_name VARCHAR(50) NOT NULL,
        FOREIGN KEY (category_id) REFERENCES request_categories(id) ON DELETE CASCADE,
        UNIQUE KEY category_code (category_id, code_name)
    )";
    
    if ($conn->query($sql_codes) === TRUE) {
        echo "Table 'category_codes' created. ";
        
        // Seed initial data
        $conn->query("INSERT INTO request_categories (name, icon_name, color_hex) VALUES 
            ('Warden', 'people', '#4CAF50'),
            ('Security', 'shield', '#F44336'),
            ('Maintenance', 'build', '#FFC107')");
            
        $res = $conn->query("SELECT id, name FROM request_categories");
        while($row = $res->fetch_assoc()) {
            if($row['name'] == 'Warden') $w_id = $row['id'];
            if($row['name'] == 'Security') $s_id = $row['id'];
            if($row['name'] == 'Maintenance') $m_id = $row['id'];
        }
        
        $conn->query("INSERT INTO category_codes (category_id, code_name) VALUES 
            ($w_id, 'Permission Leave'), ($w_id, 'Home Visit'), ($w_id, 'Late Entry'), ($w_id, 'Guest Visit'),
            ($s_id, 'Theft Report'), ($s_id, 'Suspicious Activity'), ($s_id, 'Lost Item'), ($s_id, 'Emergency'),
            ($m_id, 'AC Repair'), ($m_id, 'Plumbing'), ($m_id, 'Electrical'), ($m_id, 'Furniture'), ($m_id, 'Cleaning')");
            
        echo "Data seeded successfully.";
    } else {
        echo "Error creating category_codes: " . $conn->error;
    }
} else {
    echo "Error creating request_categories: " . $conn->error;
}
$conn->close();
?>
