<?php
require_once __DIR__ . '/../hostel_backend/config/database.php';

$database = new Database();
$pdo = $database->getConnection();

if (!$pdo) {
    die("Database connection failed");
}

$tables = ['parent_users', 'parent_student_map'];
foreach ($tables as $t) {
    echo "--- $t TABLE COLUMNS ---\n";
    try {
        $q = $pdo->query("DESCRIBE $t");
        while ($row = $q->fetch(PDO::FETCH_ASSOC)) {
            echo "{$row['Field']} - {$row['Type']}\n";
        }
    } catch (Exception $e) {
        echo "Error on $t: " . $e->getMessage() . "\n";
    }
    echo "\n";
}
?>
