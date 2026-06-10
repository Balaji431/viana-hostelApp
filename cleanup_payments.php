<?php
try {
    $db = new PDO("mysql:host=127.0.0.1;port=3307;dbname=stay_simats", "root", "vstay2026");
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    $names = ['RACHAKONDA YOGA NANDHINI', 'AKONDA YOGA NANDHINI'];
    
    echo "\nSearching by names...\n";
    foreach ($names as $name) {
        $query = "SELECT pid, registerNumber, name, payment_id, booking_date, amount FROM payment WHERE name LIKE ?";
        $stmt = $db->prepare($query);
        $stmt->execute(["%$name%"]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo "\nName: $name\n";
        echo "Found " . count($rows) . " records.\n";
        foreach ($rows as $row) {
            echo " - PID: {$row['pid']}, Reg: '{$row['registerNumber']}', Name: '{$row['name']}', ID: {$row['payment_id']}, Date: {$row['booking_date']}\n";
        }
    }

    $ids = ['192514101', '192525052', '192521101', '192525101', '192524101'];
    
    echo "\nStarting cleanup by ID...\n";
    foreach ($ids as $id) {
        $query = "SELECT pid, registerNumber, payment_id, booking_date, amount FROM payment WHERE TRIM(registerNumber) = ?";
        $stmt = $db->prepare($query);
        $stmt->execute([$id]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        echo "\nStudent: $id\n";
        echo "Found " . count($rows) . " records.\n";

        if (count($rows) > 1) {
            // Delete records that are NOT from 2025
            echo "Deleting newer/duplicate records for $id...\n";
            $db->prepare("DELETE FROM payment WHERE TRIM(registerNumber) = ? AND booking_date NOT LIKE '2025%'")->execute([$id]);
        }
    }

    echo "\nCleanup complete.";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage();
}
?>
