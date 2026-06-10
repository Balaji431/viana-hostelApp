<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once '../config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();

    $data = json_decode(file_get_contents("php://input"), true);

    if (isset($data['name'])) {
        $name = $data['name'];
        $icon = $data['icon_name'] ?? $data['icon'] ?? 'category';
        $color = $data['color_hex'] ?? $data['color'] ?? '#3498db';
        $cat_id = isset($data['id']) ? intval($data['id']) : 0;
        $codes = isset($data['codes']) ? (is_array($data['codes']) ? $data['codes'] : explode(',', $data['codes'])) : [];

        if ($cat_id > 0) {
            $stmt = $db->prepare("UPDATE new_categories1 SET name = ?, icon_name = ?, color_hex = ?, is_staff_role = ? WHERE id = ?");
            $stmt->execute([$name, $icon, $color, $data['is_staff_role'] ?? 1, $cat_id]);
            
            $stmt_del = $db->prepare("DELETE FROM new_category_codes1 WHERE category_id = ?");
            $stmt_del->execute([$cat_id]);
        } else {
            $check_stmt = $db->prepare("SELECT id FROM new_categories1 WHERE name = ?");
            $check_stmt->execute([$name]);
            $row = $check_stmt->fetch(PDO::FETCH_ASSOC);
            
            if ($row) {
                echo json_encode(["status" => "error", "message" => "Category with this name already exists"]);
                exit();
            } else {
                $ins_stmt = $db->prepare("INSERT INTO new_categories1 (name, icon_name, color_hex, is_staff_role) VALUES (?, ?, ?, ?)");
                $ins_stmt->execute([$name, $icon, $color, $data['is_staff_role'] ?? 1]);
                $cat_id = $db->lastInsertId();
            }
        }

        if (!empty($codes)) {
            $code_stmt = $db->prepare("INSERT INTO new_category_codes1 (category_id, code_name) VALUES (?, ?)");
            foreach ($codes as $code) {
                if (!empty(trim($code))) {
                    $code_stmt->execute([$cat_id, trim($code)]);
                }
            }
        }

        echo json_encode(["status" => "success", "id" => $cat_id]);
    } else {
        echo json_encode(["status" => "error", "message" => "Name is required"]);
    }
} catch (Exception $e) {
    echo json_encode(["status" => "error", "message" => $e->getMessage()]);
}
?>