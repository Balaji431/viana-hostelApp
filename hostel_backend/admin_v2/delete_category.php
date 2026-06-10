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

// Enable error reporting
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

try {
    $data = json_decode(file_get_contents("php://input"), true);

    if (isset($data['id']) || isset($data['name'])) {
        $cat_id = 0;
        
        if (isset($data['id'])) {
            $cat_id = intval($data['id']);
        } else {
            $name = $data['name'];
            $stmt = $conn->prepare("SELECT id FROM new_categories1 WHERE name = ?");
            $stmt->bind_param("s", $name);
            $stmt->execute();
            $result = $stmt->get_result();
            if ($row = $result->fetch_assoc()) {
                $cat_id = $row['id'];
            }
        }
        
        if ($cat_id > 0) {
            $conn->begin_transaction();
            
            // Delete codes (FOREIGN KEY should handle this if ON DELETE CASCADE, but manual is safer)
            $stmt_codes = $conn->prepare("DELETE FROM new_category_codes1 WHERE category_id = ?");
            $stmt_codes->bind_param("i", $cat_id);
            $stmt_codes->execute();
            
            // Delete category
            $stmt_cat = $conn->prepare("DELETE FROM new_categories1 WHERE id = ?");
            $stmt_cat->bind_param("i", $cat_id);
            $stmt_cat->execute();
            
            $conn->commit();
            echo json_encode([
                "status" => "success",
                "success" => true,
                "message" => "Category deleted successfully"
            ]);
        } else {
            echo json_encode([
                "status" => "error",
                "success" => false,
                "message" => "Category not found"
            ]);
        }
    } else {
        echo json_encode([
            "status" => "error",
            "success" => false,
            "message" => "Missing category ID or name"
        ]);
    }
} catch (Exception $e) {
    if (isset($conn)) $conn->rollback();
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => "Database error: " . $e->getMessage()
    ]);
}

$conn->close();
?>
