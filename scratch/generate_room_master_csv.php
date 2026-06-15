<?php
require_once __DIR__ . '/../hostel_backend/config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();
    if (!$db) {
        throw new Exception("Could not connect to database.");
    }

    $sql = "SELECT * FROM room_master ORDER BY building_code, floor_no, block_no, room_no";
    $stmt = $db->query($sql);
    $rooms = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $csvFile = __DIR__ . '/../room_master.csv';
    $output = fopen($csvFile, 'w');
    if (!$output) {
        throw new Exception("Could not open output file: $csvFile");
    }

    // Add UTF-8 BOM
    fprintf($output, chr(0xEF).chr(0xBB).chr(0xBF));

    // Headers
    fputcsv($output, [
        'Hostel Name', 
        'Room Code', 
        'Room Type', 
        'Capacity'
    ]);

    function cleanHostelName($rawName) {
        $hostelMapping = [
            'KAVERI' => 'KAVERI HOSTEL',
            'VAIGAI' => 'VAIGAI HOSTEL',
            'KRISHNA' => 'KRISHNA HOSTEL',
            'KRISHAN' => 'KRISHNA HOSTEL',
            'NOYYAL' => 'NOYYAL HOSTEL',
            'PONNI' => 'PONNI HOSTEL',
            'SIRUVANI' => 'SIRUVANI HOSTEL',
            'PORUNAI' => 'PORUNAI HOSTEL',
            'PALAR' => 'PALAR HOSTEL',
            'ALLIED' => 'ALLIED HEALTH SCIENCES',
            'RADIANTS' => 'Radiants INN Ladies Hostel Building',
        ];
        $upperName = strtoupper($rawName);
        foreach ($hostelMapping as $key => $value) {
            if (strpos($upperName, $key) !== false) {
                return $value;
            }
        }
        return $rawName;
    }

    $count = 0;
    foreach ($rooms as $row) {
        fputcsv($output, [
            cleanHostelName($row['location_name'] ?? ''),
            $row['room_code'] ?? '',
            $row['room_type'] ?? 'Not Assigned',
            $row['room_capacity'] ?? '0'
        ]);
        $count++;
    }

    fclose($output);
    echo "SUCCESS: Exported $count room master records to room_master.csv successfully.\n";

} catch (Exception $e) {
    echo "ERROR: " . $e->getMessage() . "\n";
}
?>
