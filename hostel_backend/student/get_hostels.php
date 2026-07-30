<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

if (!$conn) {
    echo json_encode(['status' => 'error', 'message' => 'Database connection failed']);
    exit();
}

try {
    // Query to fetch all hostels from hostel_type table
    $query = "
        SELECT 
            h.id,
            h.campus,
            h.hostel_name,
            h.hostel_type,
            h.building_code,
            COUNT(DISTINCT r.group_name) as zone_count,
            COUNT(r.s_no) as room_count,
            COALESCE(SUM(r.total_beds), 0) as total_capacity,
            COALESCE(SUM(r.available_beds), 0) as available_rooms
        FROM hostel_type h
        LEFT JOIN rooms_groups_details r ON (TRIM(h.hostel_name) = TRIM(r.hostel_name))
        GROUP BY h.id, h.campus, h.hostel_name, h.hostel_type, h.building_code
        ORDER BY h.id ASC
    ";
    
    $result = $conn->query($query);
    
    if (!$result) {
        throw new Exception("Error fetching hostels: " . $conn->error);
    }
    
    $hostels = [];
    $cityCampus = [];
    $thandalamCampus = [];
    $poonamalleeCampus = [];
    
    while ($row = $result->fetch_assoc()) {
        $hostel = [
            'id' => (int)$row['id'],
            'campus' => $row['campus'],
            'hostel_name' => $row['hostel_name'],
            'hostel_type' => $row['hostel_type'],
            'building_code' => $row['building_code'],
            'zone_count' => (int)$row['zone_count'],
            'room_count' => (int)$row['room_count'],
            'total_capacity' => (int)$row['total_capacity'],
            'available_rooms' => max(0, (int)$row['available_rooms'])
        ];
        
        // Group by campus
        if ($row['campus'] === 'City Campus') {
            $cityCampus[] = $hostel;
        } else if ($row['campus'] === 'Poonamallee Campus') {
            $poonamalleeCampus[] = $hostel;
            // Also include in thandalamCampus list if UI displays thandalamCampus as primary
            $thandalamCampus[] = $hostel;
        } else {
            $thandalamCampus[] = $hostel;
        }
        
        $hostels[] = $hostel;
    }
    
    echo json_encode([
        'status' => 'success',
        'message' => 'Hostels retrieved successfully',
        'data' => [
            'all_hostels' => $hostels,
            'by_campus' => [
                'city_campus' => $cityCampus,
                'thandalam_campus' => $thandalamCampus,
                'poonamallee_campus' => $poonamalleeCampus
            ],
            'total_count' => count($hostels)
        ]
    ]);
    
    $conn->close();
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}
?>
