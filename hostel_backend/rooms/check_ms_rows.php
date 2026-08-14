<?php
require '/var/www/html/config/database.php';
$db = (new Database())->getConnection();

echo "=== MAPPING_STAFF RECENT ROWS ===\n";
$stmt = $db->query("SELECT * FROM mapping_staff ORDER BY id DESC LIMIT 20");
print_r($stmt->fetchAll(PDO::FETCH_ASSOC));
