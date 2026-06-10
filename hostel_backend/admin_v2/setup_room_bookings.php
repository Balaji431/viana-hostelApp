<?php
header("Content-Type: text/plain");
$pdo = new PDO("mysql:host=localhost;port=3307;dbname=stay_simats", "root", "vstay2026");

try {
    echo "Starting setup for 'new_room_booking' table...\n";

    // 1. Create Table
    $createTable = "CREATE TABLE IF NOT EXISTS `new_room_booking` (
      `nbid` int(11) NOT NULL,
      `registerNumber` int(11) NOT NULL,
      `name` varchar(50) NOT NULL,
      `institution` varchar(50) NOT NULL,
      `hostel_name` varchar(50) NOT NULL,
      `room_type` varchar(50) NOT NULL,
      `room_no` varchar(50) NOT NULL,
      `bed_no` varchar(50) NOT NULL,
      `valid_from` date NOT NULL,
      `valid_to` date NOT NULL,
      `valid_status` varchar(50) NOT NULL,
      `due days` int(11) NOT NULL,
      `admin_status` varchar(50) NOT NULL,
      `created_on` date NOT NULL,
      PRIMARY KEY (`nbid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=latin1";

    $pdo->exec($createTable);
    echo "Table 'new_room_booking' created or already exists.\n";

    // 2. Clear existing data to avoid duplicates if re-run
    $pdo->exec("TRUNCATE TABLE `new_room_booking`");
    echo "Table truncated.\n";

    // 3. Insert Data (Pasted from your request)
    $inserts = [
        "(1, 192524101, 'RACHAKONDA YOGA NANDHINI', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R01', 'B1', '2025-06-21', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(2, 192525052, 'SHAIK RESHMA', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R01', 'B2', '2025-06-13', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(3, 192522025, 'SREELEKHA. G', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R01', 'B4', '2025-06-12', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(4, 192522017, 'VIMALA C', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R01', 'B6', '2025-07-07', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(5, 192520009, 'HARITHAA S', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R02', 'B1', '2025-07-05', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(6, 192511095, 'B.LAYAASRI', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R02', 'B2', '2025-06-11', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(7, 192573002, 'S. SHAMAH ALI FATHIMA', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R02', 'B3', '2025-06-19', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(8, 192519045, 'A. VANDANA DEVI', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R02', 'B4', '2025-06-11', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(9, 192525071, 'K RAMYA', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R02', 'B5', '2025-06-14', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(10, 192511111, 'POOJAVEERARAGHAVAN', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R02', 'B6', '2025-07-15', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(11, 192515010, 'NETRAVATHI. C', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R03', 'B1', '2025-06-08', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(12, 192522035, 'SOWMIYA. R', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R03', 'B2', '2025-06-11', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(13, 192512061, 'Y. YASHASWINI ', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R03', 'B3', '2025-06-11', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(14, 192525064, 'M.PARINITHA LAKSHMI SANTHOSHI', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R03', 'B4', '2025-06-21', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(15, 192511035, 'ELAKATI RENU SREE', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R03', 'B5', '2025-06-12', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(16, 192522018, 'HARITHA K K', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R03', 'B6', '2025-09-06', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(17, 192522039, 'NEVETHA MADURAI VEERAN MATHI', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R04', 'B1', '2025-06-29', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(18, 192511087, 'SNEHITHA. A', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R04', 'B2', '2025-06-18', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(19, 192565016, 'DIVYA SREE P', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R04', 'B3', '2025-07-11', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(20, 192524124, 'PRIYANKA GANESAN', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R04', 'B4', '2025-07-08', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(21, 192524144, 'S. MAGALAKSHMI ', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R04', 'B5', '2025-07-09', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(22, 192524143, 'D. VAISHNAVI', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R04', 'B6', '2025-07-04', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(23, 192525037, 'PAGIDIPALLI RUCHITHA REDDY', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R05', 'B1', '2025-07-05', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(24, 192525086, 'BOLLAPU NAGA NIKITHA', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R05', 'B2', '2025-07-05', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(25, 192525097, 'PALLAPATI SAI SEVITHA', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R05', 'B3', '2025-06-11', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(26, 192519055, 'ASHITHA. M', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R05', 'B4', '2025-06-20', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(27, 192512071, 'S.NITHYASRI ', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R05', 'B5', '2025-06-11', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')",
        "(28, 192521140, 'THARIKA. S', 'SSE', 'Vaigai', 'AC - B ATTACHED (6 IN 1)', 'T32-F00-W01-R05', 'B6', '2025-06-11', '2026-05-31', 'Valid', 243, 'Confirmed', '2025-09-13')"
    ];

    $sql = "INSERT INTO `new_room_booking` 
            (`nbid`, `registerNumber`, `name`, `institution`, `hostel_name`, `room_type`, `room_no`, `bed_no`, `valid_from`, `valid_to`, `valid_status`, `due days`, `admin_status`, `created_on`) 
            VALUES " . implode(", ", $inserts);
    
    $pdo->exec($sql);
    echo "Inserted " . count($inserts) . " records successfully.\n";
    echo "You can now run 'fix_profile_dates.php' to sync this data to the profile table.\n";

} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
?>
