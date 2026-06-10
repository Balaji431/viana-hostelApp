<?php
$host = "localhost";
$db_name = "stay_simats";
$username = "root";
$password = ""; // XAMPP default is empty
$port = 3306;

try {
    $pdo = new PDO("mysql:host=" . $host . ";port=" . $port . ";dbname=" . $db_name, $username, $password);
    $stmt = $pdo->query("SHOW TABLES");
    while ($row = $stmt->fetch(PDO::FETCH_NUM)) {
        echo $row[0] . "\n";
    }
} catch (Exception $e) {
    // Try with vstay2026 password just in case
    try {
        $password = "vstay2026";
        $pdo = new PDO("mysql:host=" . $host . ";port=" . $port . ";dbname=" . $db_name, $username, $password);
        $stmt = $pdo->query("SHOW TABLES");
        while ($row = $stmt->fetch(PDO::FETCH_NUM)) {
            echo $row[0] . "\n";
        }
    } catch (Exception $e2) {
        // Try port 3307
        try {
            $port = 3307;
            $pdo = new PDO("mysql:host=" . $host . ";port=" . $port . ";dbname=" . $db_name, $username, $password);
            $stmt = $pdo->query("SHOW TABLES");
            while ($row = $stmt->fetch(PDO::FETCH_NUM)) {
                echo $row[0] . "\n";
            }
        } catch (Exception $e3) {
            echo "Error: " . $e3->getMessage();
        }
    }
}
