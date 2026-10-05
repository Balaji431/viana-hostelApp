<?php
require_once __DIR__ . '/../config/database.php';

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        die("Error: Could not connect to database.\n");
    }
    $sql = file_get_contents(__DIR__ . '/create_eb_billing_tables.sql');
    $db->exec($sql);
    echo "SUCCESS: EB billing tables created or already exist.\n";
} catch (Exception $e) {
    echo "ERROR: " . $e->getMessage() . "\n";
}
