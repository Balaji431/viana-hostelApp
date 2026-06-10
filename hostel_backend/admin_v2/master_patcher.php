<?php
header('Content-Type: application/json');

$files_to_patch = [
    'get_categories.php' => '../admin_v2/get_categories.php',
    'save_category_final.php' => '../admin_v2/save_category_final.php',
    'get_assigned_staff.php' => '../chat/get_assigned_staff.php'
];

// Content for get_categories.php
$get_categories_content = <<<'EOD'
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
EOD;

// Content for save_category_final.php
$save_category_content = <<<'EOD'
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
        $icon = $data['icon'] ?? 'category';
        $color = $data['color'] ?? '#3498db';
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
                $cat_id = $row['id'];
                $upd_stmt = $db->prepare("UPDATE new_categories1 SET icon_name = ?, color_hex = ?, is_staff_role = ? WHERE id = ?");
                $upd_stmt->execute([$icon, $color, $data['is_staff_role'] ?? 1, $cat_id]);
                
                $del_stmt = $db->prepare("DELETE FROM new_category_codes1 WHERE category_id = ?");
                $del_stmt->execute([$cat_id]);
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
EOD;

// Content for get_assigned_staff.php (already have it)
// ... but for simplicity I'll just include it again in the script if needed.
// Actually I'll just use the ones I need now.

$results = [];

if (file_put_contents('../admin_v2/get_categories.php', $get_categories_content)) $results['get_categories'] = 'patched';
if (file_put_contents('../admin_v2/save_category_final.php', $save_category_content)) $results['save_category'] = 'patched';

echo json_encode(['status' => 'success', 'results' => $results]);
?>
