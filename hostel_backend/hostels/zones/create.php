<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';



$data = json_decode(file_get_contents("php://input"));

if (!empty($data->hostel_id) && !empty($data->zone_name) && !empty($data->zone_code)) {
    
    $hostel_id = (int)$data->hostel_id;
    $zone_name = trim($data->zone_name);
    $zone_code = trim($data->zone_code);
    $description = isset($data->description) ? trim($data->description) : '';
    $capacity = isset($data->capacity) ? (int)$data->capacity : 0;
    
    try {
        // Check if zone code already exists
        $check_query = "SELECT id FROM zones WHERE zone_code = ? AND hostel_id = ?";
        $check_stmt = $conn->prepare($check_query);
        $check_stmt->bind_param("si", $zone_code, $hostel_id);
        $check_stmt->execute();
        
        if ($check_stmt->get_result()->num_rows > 0) {
            echo json_encode([
                'success' => false,
                'message' => 'Zone code already exists in this hostel'
            ]);
            exit();
        }
        
        // Insert new zone
        $query = "INSERT INTO zones (hostel_id, zone_name, zone_code, description, capacity, created_at) 
                  VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)";
        
        $stmt = $conn->prepare($query);
        $stmt->bind_param("isssi", $hostel_id, $zone_name, $zone_code, $description, $capacity);
        
        if ($stmt->execute()) {
            $zone_id = $conn->insert_id;
            echo json_encode([
                'success' => true,
                'message' => 'Zone created successfully',
                'data' => [
                    'id' => $zone_id,
                    'hostel_id' => $hostel_id,
                    'zone_name' => $zone_name,
                    'zone_code' => $zone_code,
                    'description' => $description,
                    'capacity' => $capacity,
                    'created_at' => date('Y-m-d H:i:s')
                ]
            ]);
        } else {
            echo json_encode([
                'success' => false,
                'message' => 'Failed to create zone'
            ]);
        }
        
    } catch (Exception $e) {
        echo json_encode([
            'success' => false,
            'message' => 'Database error: ' . $e->getMessage()
        ]);
    }
} else {
    echo json_encode([
        'success' => false,
        'message' => 'Incomplete data. Required: hostel_id, zone_name, zone_code'
    ]);
}

$conn->close();
?>
