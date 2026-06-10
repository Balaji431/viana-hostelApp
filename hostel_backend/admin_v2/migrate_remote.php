<?php
header('Content-Type: application/json');
require_once '../config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();
    
    if (!$db) {
        throw new Exception("Could not connect to database");
    }

    $results = [];

    // 1. Fix new_categories1
    $stmt = $db->query("SHOW COLUMNS FROM new_categories1 LIKE 'is_staff_role'");
    if (!$stmt->fetch()) {
        $db->exec("ALTER TABLE new_categories1 ADD COLUMN is_staff_role TINYINT(1) DEFAULT 1");
        $results[] = "Added is_staff_role to new_categories1";
    } else {
        $results[] = "is_staff_role already exists in new_categories1";
    }

    // 2. Fix mapping_staff
    $db->exec("ALTER TABLE mapping_staff MODIFY COLUMN role VARCHAR(100) NOT NULL");
    $results[] = "Changed mapping_staff.role to VARCHAR(100)";

    echo json_encode(["status" => "success", "results" => $results]);

} catch (Exception $e) {
    echo json_encode(["status" => "error", "message" => $e->getMessage()]);
}
?>
