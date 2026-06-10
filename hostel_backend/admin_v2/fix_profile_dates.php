<?php
$pdo = new PDO("mysql:host=localhost;port=3307;dbname=stay_simats", "root", "vstay2026");

if (!$pdo) {
    die("Database connection failed\n");
}

try {
    echo "<h1>Starting profile date fix...</h1>";
    
    // VERIFY new_room_booking exists
    $checkTable = $pdo->query("SHOW TABLES LIKE 'new_room_booking'");
    if ($checkTable->rowCount() == 0) {
        echo "<p style='color:red'>Error: Table 'new_room_booking' does not exist in the database.</p>";
    } else {
        $countTable = $pdo->query("SELECT COUNT(*) FROM new_room_booking")->fetchColumn();
        echo "<p>Table 'new_room_booking' found with $countTable records.</p>";
    }

    // 0. Update valid_from and valid_to using new_room_booking table (PRIMARY SOURCE)
    // We FORCE update here to ensure data is synced with the master booking list
    $sql0 = "UPDATE profile p
             JOIN new_room_booking nrb ON TRIM(p.reg_no) = TRIM(nrb.registerNumber)
             SET p.valid_from = nrb.valid_from,
                 p.valid_to = nrb.valid_to";
    
    $stmt0 = $pdo->prepare($sql0);
    $stmt0->execute();
    $count0 = $stmt0->rowCount();
    echo "<p>Step 0: Synced $count0 records from new_room_booking master list.</p>";

    // 1. Update valid_from using the earliest booking_date from payment table
    $sql1 = "UPDATE profile p
             SET p.valid_from = (
                 SELECT MIN(pay.booking_date) 
                 FROM payment pay 
                 WHERE TRIM(pay.registerNumber) = TRIM(p.reg_no)
             )
             WHERE (p.valid_from IS NULL OR p.valid_from = '0000-00-00' OR p.valid_from = '')";
    
    $stmt1 = $pdo->prepare($sql1);
    $stmt1->execute();
    $count1 = $stmt1->rowCount();
    echo "<p>Step 1: Updated $count1 records using payment history.</p>";
    
    // 2. For remaining records with 0000-00-00, set valid_from to 1 year before valid_to
    $sql2 = "UPDATE profile 
             SET valid_from = DATE_SUB(valid_to, INTERVAL 1 YEAR)
             WHERE (valid_from IS NULL OR valid_from = '0000-00-00' OR valid_from = '')
             AND valid_to IS NOT NULL AND valid_to != '0000-00-00' AND valid_to != ''";
             
    $stmt2 = $pdo->prepare($sql2);
    $stmt2->execute();
    $count2 = $stmt2->rowCount();
    echo "<p>Step 2: Updated $count2 records using valid_to inference.</p>";
    
    // 3. For any still 0000-00-00, set to current date
    $sql3 = "UPDATE profile 
             SET valid_from = CURRENT_DATE
             WHERE (valid_from IS NULL OR valid_from = '0000-00-00' OR valid_from = '')";
             
    $stmt3 = $pdo->prepare($sql3);
    $stmt3->execute();
    $count3 = $stmt3->rowCount();
    echo "<p>Step 3: Updated $count3 records to current date as fallback.</p>";

    echo "<h3>Fix completed successfully.</h3>";

} catch (Exception $e) {
    echo "<p style='color:red'>Error: " . $e->getMessage() . "</p>";
}
?>
