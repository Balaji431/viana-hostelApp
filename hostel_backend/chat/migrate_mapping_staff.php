<?php
// Migration to add username column to mapping_staff table
$host = "localhost";
$db_name = "stay_simats";
$username = "root";
$password = "vstay2026"; // Try from database.php
$port = 3306;

try {
    $pdo = new PDO("mysql:host=$host;port=$port;dbname=$db_name", $username, $password);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    // Check if column exists
    $stmt = $pdo->query("SHOW COLUMNS FROM mapping_staff LIKE 'username'");
    $exists = $stmt->fetch();
    
    if (!$exists) {
        $pdo->exec("ALTER TABLE mapping_staff ADD COLUMN username VARCHAR(100) AFTER phone");
        echo "Column 'username' added successfully to mapping_staff table.\n";
    } else {
        echo "Column 'username' already exists in mapping_staff table.\n";
    }
    
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
?>
