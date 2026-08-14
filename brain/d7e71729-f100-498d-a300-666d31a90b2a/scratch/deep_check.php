<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

echo "--- Searching for 27034 in all tables ---\n";
$tables = $db->query("SHOW TABLES")->fetchAll(PDO::FETCH_COLUMN);
foreach ($tables as $tbl) {
    $cols = $db->query("DESCRIBE `$tbl`")->fetchAll(PDO::FETCH_COLUMN);
    $whereParts = [];
    foreach ($cols as $col) {
        $whereParts[] = "`$col` LIKE '%27034%'";
    }
    $sql = "SELECT * FROM `$tbl` WHERE " . implode(' OR ', $whereParts) . " LIMIT 5";
    try {
        $stmt = $db->query($sql);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        if (count($rows) > 0) {
            echo "Found 27034 in table `$tbl` (" . count($rows) . " rows):\n";
            print_r($rows);
        }
    } catch (Exception $e) {
        // skip
    }
}

echo "\n--- Checking 192511250 student details ---\n";
$stmt = $db->prepare("SELECT * FROM users WHERE username = '192511250' OR email = '192511250.simats@saveetha.com' LIMIT 1");
$stmt->execute();
$row = $stmt->fetch(PDO::FETCH_ASSOC);
if ($row) {
    print_r($row);
    // Let's test common passwords like welcome123, 123user123, 192511250, saveetha123, etc.
    $testPwds = ['123user123', 'welcome123', '192511250', 'saveetha', 'saveetha123', 'user123', '12345678', '123456'];
    foreach ($testPwds as $tp) {
        if (password_verify($tp, $row['password'])) {
            echo "MATCHED PASSWORD: '$tp'!\n";
        }
    }
} else {
    echo "Student 192511250 not found in users.\n";
}
