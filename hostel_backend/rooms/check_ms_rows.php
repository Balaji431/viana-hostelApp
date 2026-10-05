<?php
if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    echo json_encode(["status" => "error", "message" => "Forbidden: CLI access only"]);
    exit();
}
require_once __DIR__ . '/../config/database.php';
$db = (new Database())->getConnection();

echo "=== MAPPING_STAFF RECENT ROWS ===\n";
$stmt = $db->query("SELECT * FROM mapping_staff ORDER BY id DESC LIMIT 20");
print_r($stmt->fetchAll(PDO::FETCH_ASSOC));
