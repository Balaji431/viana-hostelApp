<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

echo "=== SEARCHING FOR 'Gomathy' IN ALL TABLES ===\n";
$tables = $db->query("SHOW TABLES")->fetchAll(PDO::FETCH_COLUMN);

foreach ($tables as $tbl) {
    $cols = $db->query("DESCRIBE `$tbl`")->fetchAll(PDO::FETCH_COLUMN);
    $where = [];
    foreach ($cols as $c) {
        $where[] = "`$c` LIKE '%Gomathy%'";
    }
    $sql = "SELECT * FROM `$tbl` WHERE " . implode(" OR ", $where);
    try {
        $res = $db->query($sql)->fetchAll(PDO::FETCH_ASSOC);
        if (count($res) > 0) {
            echo "Table `$tbl` matches (" . count($res) . " rows):\n";
            foreach ($res as $r) {
                print_r($r);
            }
        }
    } catch (Exception $e) {}
}
