<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

require_once '../config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();

    $sql = "SELECT c.id, c.name, c.icon_name as icon, c.color_hex as color, c.is_staff_role,
            GROUP_CONCAT(cc.code_name SEPARATOR ', ') as codes
            FROM new_categories1 c 
            LEFT JOIN new_category_codes1 cc ON c.id = cc.category_id 
            GROUP BY c.id, c.name, c.icon_name, c.color_hex, c.is_staff_role
            ORDER BY c.id";

    $stmt = $db->query($sql);
    $categories = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "status" => "success",
        "categories" => $categories
    ]);
} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "message" => $e->getMessage()
    ]);
}
?>