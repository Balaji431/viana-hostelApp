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

$data = json_decode(file_get_contents("php://input"), true);

if (isset($data['name']) && isset($data['icon']) && isset($data['color']) && isset($data['codes'])) {
    $name = $conn->real_escape_string($data['name']);
    $icon = $conn->real_escape_string($data['icon']);
    $color = $conn->real_escape_string($data['color']);
    $codes = $data['codes']; // Array
    
    // UPSERT pattern: check if exists
    $check = $conn->query("SELECT id FROM request_categories WHERE name = '$name'");
    if ($check && $check->num_rows > 0) {
        $row = $check->fetch_assoc();
        $cat_id = $row['id'];
        $conn->query("UPDATE request_categories SET icon_name = '$icon', color_hex = '$color' WHERE id = $cat_id");
        $conn->query("DELETE FROM category_codes WHERE category_id = $cat_id");
    } else {
        $conn->query("INSERT INTO request_categories (name, icon_name, color_hex) VALUES ('$name', '$icon', '$color')");
        $cat_id = $conn->insert_id;
    }
    
    if ($cat_id) {
        foreach ($codes as $code) {
            $code_name = $conn->real_escape_string($code);
            $conn->query("INSERT INTO category_codes (category_id, code_name) VALUES ($cat_id, '$code_name')");
        }
        echo json_encode(array("status" => "success", "success" => true, "message" => "Category saved successfully"));
    } else {
        echo json_encode(array("status" => "error", "success" => false, "message" => "Failed to get category ID"));
    }
} else {
    echo json_encode(array("status" => "error", "success" => false, "message" => "Missing required fields"));
}

$conn->close();
?>
