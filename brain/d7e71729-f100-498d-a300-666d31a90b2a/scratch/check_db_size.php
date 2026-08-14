<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

echo "=== DATABASE STORAGE & ROW METRICS ===\n";
$stmt = $db->query("
    SELECT 
        table_name AS `Table`,
        table_rows AS `Rows`,
        ROUND(((data_length + index_length) / 1024 / 1024), 2) AS `Size_MB`
    FROM information_schema.TABLES
    WHERE table_schema = 'stay_simats'
    ORDER BY (data_length + index_length) DESC
");
$tables = $stmt->fetchAll(PDO::FETCH_ASSOC);
print_r($tables);
