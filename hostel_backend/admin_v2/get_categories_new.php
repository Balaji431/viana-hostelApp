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

try {
    $database = new Database();
    $db = $database->getConnection();

    $sql = "SELECT c.id, c.name, c.icon_name, c.color_hex,
            GROUP_CONCAT(cc.code_name SEPARATOR '|') as codes
            FROM new_categories1 c 
            LEFT JOIN new_category_codes1 cc ON c.id = cc.category_id 
            GROUP BY c.id, c.name, c.icon_name, c.color_hex 
            ORDER BY c.id";

    $stmt = $db->prepare($sql);
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $categories = array();
    foreach ($rows as $row) {
        $codes = !empty($row['codes']) ? explode('|', $row['codes']) : [];
        $codes = array_filter($codes, function($code) {
            return !empty(trim($code));
        });
        $categories[] = array(
            'id' => $row['id'],
            'name' => $row['name'],
            'icon' => $row['icon_name'],
            'color' => $row['color_hex'],
            'codes' => array_values($codes)
        );
    }

    echo json_encode(array(
        "status" => "success", 
        "success" => true, 
        "categories" => $categories, 
        "data" => $categories
    ));

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(array(
        "status" => "error", 
        "message" => $e->getMessage(),
        "success" => false
    ));
}
?>
