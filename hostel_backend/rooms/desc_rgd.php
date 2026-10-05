<?php
if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    echo json_encode(["status" => "error", "message" => "Forbidden: CLI access only"]);
    exit();
}
require_once __DIR__ . '/../config/database.php';
$db = (new Database())->getConnection();
$stmt = $db->query('DESCRIBE rooms_groups_details');
print_r($stmt->fetchAll(PDO::FETCH_COLUMN));
