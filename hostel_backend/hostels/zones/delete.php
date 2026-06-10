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



$zone_id = isset($_GET['id']) ? (int)$_GET['id'] : 0;

if ($zone_id <= 0) {
    echo json_encode([
        'success' => false,
        'message' => 'Valid zone ID required'
    ]);
    exit();
}

try {
    // Check if zone has sub-zones
    $check_query = "SELECT COUNT(*) as count FROM sub_zones WHERE zone_id = ?";
    $check_stmt = $conn->prepare($check_query);
    $check_stmt->bind_param("i", $zone_id);
    $check_stmt->execute();
    $result = $check_stmt->get_result();
    $row = $result->fetch_assoc();
    
    if ($row['count'] > 0) {
        echo json_encode([
            'success' => false,
            'message' => 'Cannot delete zone. It has sub-zones assigned to it.'
        ]);
        exit();
    }
    
    // Delete the zone
    $query = "DELETE FROM zones WHERE id = ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("i", $zone_id);
    
    if ($stmt->execute()) {
        if ($stmt->affected_rows > 0) {
            echo json_encode([
                'success' => true,
                'message' => 'Zone deleted successfully'
            ]);
        } else {
            echo json_encode([
                'success' => false,
                'message' => 'Zone not found'
            ]);
        }
    } else {
        echo json_encode([
            'success' => false,
            'message' => 'Failed to delete zone'
        ]);
    }
    
} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'message' => 'Database error: ' . $e->getMessage()
    ]);
}

$conn->close();
?>
