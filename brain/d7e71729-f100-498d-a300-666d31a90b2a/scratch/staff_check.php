<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

echo "--- Searching for staff / security accounts in users table ---\n";
$stmt = $db->query("SELECT id, username, full_name, role, Status FROM users WHERE role LIKE '%security%' OR role LIKE '%staff%' OR role LIKE '%warden%' LIMIT 20");
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
print_r($rows);

echo "--- Searching mapping_staff table ---\n";
try {
    $stmt2 = $db->query("SELECT * FROM mapping_staff LIMIT 20");
    $rows2 = $stmt2->fetchAll(PDO::FETCH_ASSOC);
    print_r($rows2);
} catch (Exception $e) {
    echo "No mapping_staff table or error: " . $e->getMessage() . "\n";
}
