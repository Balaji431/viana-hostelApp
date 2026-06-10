<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once '../config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();

    $hostelFilter = isset($_GET['hostel_name']) ? $_GET['hostel_name'] : '';

    if (empty($hostelFilter)) {
        echo json_encode([
            "status" => "error",
            "success" => false,
            "message" => "hostel_name parameter is required"
        ]);
        exit();
    }

    // Query to get floor-wise room count and room types with actual database values
    $sql = "SELECT 
                floor,
                room_type,
                COUNT(*) as total_rooms,
                SUM(total_vacancy) as total_beds_capacity,
                SUM(available_rooms) as available_beds,
                SUM(occupied_rooms) as occupied_beds
            FROM hostel_rooms 
            WHERE hostel_name = ?
            GROUP BY floor, room_type
            ORDER BY 
                CASE floor 
                    WHEN 'Ground' THEN 0
                    WHEN 'First' THEN 1
                    WHEN 'Second' THEN 2
                    WHEN 'Third' THEN 3
                    WHEN 'Fourth' THEN 4
                    WHEN 'Fifth' THEN 5
                    WHEN 'Sixth' THEN 6
                    ELSE 7
                END,
                room_type";

    $stmt = $db->prepare($sql);
    $stmt->execute([$hostelFilter]);
    $results = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Function to extract bed capacity from room type name
    function extractBedCapacity($roomType) {
        // Match patterns like "4 IN 1", "6 IN 1", "8 IN 1", etc.
        if (preg_match('/(\d+)\s*IN\s*1/i', $roomType, $matches)) {
            return intval($matches[1]);
        }
        // Default to 4 if not found
        return 4;
    }

    // Group by floor for easier consumption
    $floors = [];
    foreach ($results as $row) {
        $floor = $row['floor'];
        $bedCapacity = extractBedCapacity($row['room_type']);
        
        // Calculate expected total beds based on room count and capacity
        $expectedTotalBeds = $row['total_rooms'] * $bedCapacity;
        
        // Use actual database values - don't convert
        $actualTotalBeds = $row['total_beds_capacity'];
        $availableBeds = $row['available_beds'];
        $occupiedBeds = $row['occupied_beds'];
        
        if (!isset($floors[$floor])) {
            $floors[$floor] = [
                'floor' => $floor,
                'total_rooms' => 0,
                'total_beds_capacity' => 0,
                'available_beds' => 0,
                'occupied_beds' => 0,
                'room_types' => []
            ];
        }
        $floors[$floor]['total_rooms'] += $row['total_rooms'];
        $floors[$floor]['total_beds_capacity'] += $actualTotalBeds;
        $floors[$floor]['available_beds'] += $availableBeds;
        $floors[$floor]['occupied_beds'] += $occupiedBeds;
        $floors[$floor]['room_types'][] = [
            'room_type' => $row['room_type'],
            'bed_capacity' => $bedCapacity,
            'total_rooms' => $row['total_rooms'],
            'total_beds_capacity' => $actualTotalBeds,
            'expected_total_beds' => $expectedTotalBeds,
            'available_beds' => $availableBeds,
            'occupied_beds' => $occupiedBeds,
            'data_consistency' => $actualTotalBeds == ($availableBeds + $occupiedBeds) ? 'consistent' : 'inconsistent'
        ];
    }

    // Convert to indexed array
    $floorSummary = array_values($floors);

    echo json_encode([
        "status" => "success",
        "success" => true,
        "hostel_name" => $hostelFilter,
        "data" => $floorSummary,
        "total_floors" => count($floorSummary)
    ]);
} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
