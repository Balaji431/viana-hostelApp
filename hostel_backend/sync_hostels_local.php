<?php
$host = "localhost";
$db_name = "stay_simats";
$username = "root";
$password = ""; 
$port = 3306;

try {
    $pdo = new PDO("mysql:host=" . $host . ";port=" . $port . ";dbname=" . $db_name, $username, $password);
} catch (Exception $e) {
    try {
        $password = "vstay2026";
        $pdo = new PDO("mysql:host=" . $host . ";port=" . $port . ";dbname=" . $db_name, $username, $password);
    } catch (Exception $e2) {
        $port = 3307;
        $pdo = new PDO("mysql:host=" . $host . ";port=" . $port . ";dbname=" . $db_name, $username, $password);
    }
}

try {
    // 1. Get all from hostel_type
    $stmt = $pdo->query("SELECT hostel_name FROM hostel_type");
    $hostelTypes = $stmt->fetchAll(PDO::FETCH_COLUMN);
    
    // 2. Get all from hostels
    $stmt = $pdo->query("SELECT name FROM hostels");
    $hostels = $stmt->fetchAll(PDO::FETCH_COLUMN);
    
    echo "Hostel Type count: " . count($hostelTypes) . "\n";
    echo "Hostels count: " . count($hostels) . "\n";
    
    // Sync: If it's in hostel_type but not in hostels, add it
    foreach ($hostelTypes as $name) {
        if (!in_array($name, $hostels)) {
            echo "Adding to hostels: $name\n";
            $pdo->prepare("INSERT INTO hostels (name) VALUES (?)")->execute([$name]);
        }
    }
    
    // Sync: If it's in hostels but not in hostel_type, remove it (to match Image 4)
    foreach ($hostels as $name) {
        if (!in_array($name, $hostelTypes)) {
            echo "Removing from hostels (not in hostel_type): $name\n";
            $pdo->prepare("DELETE FROM hostels WHERE name = ?")->execute([$name]);
        }
    }
    
    echo "Sync completed.\n";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage();
}
