<?php
if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    echo json_encode(["status" => "error", "message" => "Forbidden: CLI access only"]);
    exit();
}
require_once __DIR__ . '/../config/database.php';
$db = (new Database())->getConnection();

echo "=== SECURITY USERS IN SECURITY_USERS OR USERS TABLE ===\n";
$stmt = $db->query("SELECT * FROM security_users LIMIT 10");
print_r($stmt->fetchAll(PDO::FETCH_ASSOC));

echo "\n=== MAPPING_STAFF WITH SECURITY ROLE ===\n";
$stmt2 = $db->query("SELECT * FROM mapping_staff WHERE LOWER(role) LIKE '%security%' LIMIT 10");
print_r($stmt2->fetchAll(PDO::FETCH_ASSOC));
