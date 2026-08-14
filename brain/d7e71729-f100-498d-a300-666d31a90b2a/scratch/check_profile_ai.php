<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

echo "=== CHECKING PROFILE TABLE AUTO INCREMENT & COUNT ===\n";
$stmt = $db->query("SELECT COUNT(*) as cnt, MAX(id) as max_id FROM profile");
$res = $stmt->fetch(PDO::FETCH_ASSOC);
print_r($res);

$stmt2 = $db->query("SHOW TABLE STATUS LIKE 'profile'");
$status = $stmt2->fetch(PDO::FETCH_ASSOC);
echo "Auto Increment value: " . $status['Auto_increment'] . "\n";
