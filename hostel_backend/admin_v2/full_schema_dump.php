<?php
require_once '../config/database.php';
function checkTable($pdo, $tableName) {
    echo "\n--- Structure for $tableName ---\n";
    try {
        $result = $pdo->query("DESCRIBE $tableName");
        while($row = $result->fetch(PDO::FETCH_ASSOC)) {
            echo "Field: {$row['Field']}, Type: {$row['Type']}\n";
        }
    } catch (Exception $e) {
        echo "Error checking $tableName: " . $e->getMessage() . "\n";
    }
}

header('Content-Type: text/plain');
checkTable($pdo, 'hostel_rooms');
checkTable($pdo, 'rooms');
checkTable($pdo, 'hostel_type');
checkTable($pdo, 'hostels');
checkTable($pdo, 'zones');
checkTable($pdo, 'sub_zones');
?>
