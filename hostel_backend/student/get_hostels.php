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
            COUNT(DISTINCT r.wing_code) as zone_count,
            COUNT(r.id) as room_count,
            SUM(r.total_capacity) as total_capacity,
            (SUM(r.available_rooms) - COALESCE(res.total_res, 0)) as available_rooms
        FROM hostel_type h
        LEFT JOIN hostel_rooms r ON h.id = r.hostel_id
        LEFT JOIN (
            SELECT h2.id as hostel_id, COUNT(*) as total_res
            FROM room_change_requests rcr
            JOIN hostel_rooms hr2 ON TRIM(rcr.requested_room) = TRIM(hr2.room_code)
            JOIN hostel_type h2 ON hr2.hostel_id = h2.id
            WHERE rcr.status IN ('pre_approved', 'approved') 
              AND rcr.payment_status = 'unpaid'
              AND rcr.reserved_until > NOW()
              AND rcr.requested_room IS NOT NULL AND rcr.requested_room != ''
            GROUP BY h2.id
        ) res ON h.id = res.hostel_id
        GROUP BY h.id, h.campus, h.hostel_name, h.hostel_type, h.building_code
        ORDER BY 
            CASE h.campus
                WHEN 'City Campus' THEN 1
                WHEN 'Thandalam Campus' THEN 2
                ELSE 3
            END,
            h.hostel_name ASC
    ";
    
    $result = $conn->query($query);
    
    if (!$result) {
        throw new Exception("Error fetching hostels: " . $conn->error);
    }
    
    $hostels = [];
    $cityCampus = [];
    $thandalamCampus = [];
    
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
        } else if ($row['campus'] === 'Thandalam Campus') {
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
                'thandalam_campus' => $thandalamCampus
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
