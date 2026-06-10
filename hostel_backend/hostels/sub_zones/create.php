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

if (!empty($data->zone_id) && !empty($data->sub_zone_name) && !empty($data->sub_zone_code)) {
    
    $zone_id = (int)$data->zone_id;
    $sub_zone_name = trim($data->sub_zone_name);
    $sub_zone_code = trim($data->sub_zone_code);
    $description = isset($data->description) ? trim($data->description) : '';
    $capacity = isset($data->capacity) ? (int)$data->capacity : 0;
    $floor = isset($data->floor) ? (int)$data->floor : 1;
    
    try {
        // Check if sub-zone code already exists in this zone
        $check_query = "SELECT id FROM sub_zones WHERE sub_zone_code = ? AND zone_id = ?";
        $check_stmt = $conn->prepare($check_query);
        $check_stmt->bind_param("si", $sub_zone_code, $zone_id);
        $check_stmt->execute();
        
        if ($check_stmt->get_result()->num_rows > 0) {
            echo json_encode([
                'success' => false,
                'message' => 'Sub-zone code already exists in this zone'
            ]);
            exit();
        }
        
        // Insert new sub-zone
        $query = "INSERT INTO sub_zones (zone_id, sub_zone_name, sub_zone_code, description, capacity, floor, created_at) 
                  VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)";
        
        $stmt = $conn->prepare($query);
        $stmt->bind_param("issiii", $zone_id, $sub_zone_name, $sub_zone_code, $description, $capacity, $floor);
        
        if ($stmt->execute()) {
            $sub_zone_id = $conn->insert_id;
            echo json_encode([
                'success' => true,
                'message' => 'Sub-zone created successfully',
                'data' => [
                    'id' => $sub_zone_id,
                    'zone_id' => $zone_id,
                    'sub_zone_name' => $sub_zone_name,
                    'sub_zone_code' => $sub_zone_code,
                    'description' => $description,
                    'capacity' => $capacity,
                    'floor' => $floor,
                    'created_at' => date('Y-m-d H:i:s')
                ]
            ]);
        } else {
            echo json_encode([
                'success' => false,
                'message' => 'Failed to create sub-zone'
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
        'message' => 'Incomplete data. Required: zone_id, sub_zone_name, sub_zone_code'
    ]);
}

$conn->close();
?>
