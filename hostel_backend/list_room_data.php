<?php
// Simple script to output room types for the user
$db_host = "localhost";
$db_name = "stay_simats";
$db_user = "root";
$db_pass = "vstay2026"; // Try with the password found in database.php

try {
    $pdo = new PDO("mysql:host=$db_host;dbname=$db_name", $db_user, $db_pass);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    $sql = "SELECT room_type as name, MIN(amount) as monthlyCost, MIN(facility) as description
            FROM hostel_rooms 
            GROUP BY room_type 
            ORDER BY monthlyCost ASC";
            
    $stmt = $pdo->prepare($sql);
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo "DATABASE ROOM TYPES AND AMOUNTS:\n";
    echo str_repeat("-", 60) . "\n";
    printf("%-30s | %-12s | %s\n", "Room Type", "Monthly Amount", "Facility");
    echo str_repeat("-", 60) . "\n";
    foreach ($rows as $row) {
        printf("%-30s | ₹%-11s | %s\n", 
            $row['name'], 
            number_format($row['monthlyCost']), 
            $row['description']
        );
    }
    echo str_repeat("-", 60) . "\n";

} catch (PDOException $e) {
    // If password fails, try without password
    try {
        $pdo = new PDO("mysql:host=$db_host;dbname=$db_name", $db_user, "");
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        
        $sql = "SELECT room_type as name, MIN(amount) as monthlyCost, MIN(facility) as description
                FROM hostel_rooms 
                GROUP BY room_type 
                ORDER BY monthlyCost ASC";
                
        $stmt = $pdo->prepare($sql);
        $stmt->execute();
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        echo "DATABASE ROOM TYPES AND AMOUNTS:\n";
        echo str_repeat("-", 60) . "\n";
        printf("%-30s | %-12s | %s\n", "Room Type", "Monthly Amount", "Facility");
        echo str_repeat("-", 60) . "\n";
        foreach ($rows as $row) {
            printf("%-30s | ₹%-11s | %s\n", 
                $row['name'], 
                number_format($row['monthlyCost']), 
                $row['description']
            );
        }
        echo str_repeat("-", 60) . "\n";
    } catch (PDOException $e2) {
        echo "ERROR: " . $e2->getMessage();
    }
}
?>
