<?php
require_once 'config/database.php';
header('Content-Type: text/plain');

try {
    $stmt = $pdo->query("SHOW TABLES");
    while ($row = $stmt->fetch(PDO::FETCH_NUM)) {
        echo $row[0] . "\n";
    }
} catch (Exception $e) {
    echo "Error: " . $e->getMessage();
}
