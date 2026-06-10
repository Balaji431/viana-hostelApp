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



$sub_zone_id = isset($_GET['id']) ? (int)$_GET['id'] : 0;

if ($sub_zone_id <= 0) {
    echo json_encode([
        'success' => false,
        'message' => 'Valid sub-zone ID required'
    ]);
    exit();
}

try {
    // Check if sub-zone has staff assignments
    $check_query = "SELECT COUNT(*) as count FROM staff_assignments WHERE sub_zone_id = ?";
    $check_stmt = $conn->prepare($check_query);
    $check_stmt->bind_param("i", $sub_zone_id);
    $check_stmt->execute();
    $result = $check_stmt->get_result();
    $row = $result->fetch_assoc();
    
    if ($row['count'] > 0) {
        echo json_encode([
            'success' => false,
            'message' => 'Cannot delete sub-zone. It has staff assigned to it.'
        ]);
        exit();
    }
    
    // Delete the sub-zone
    $query = "DELETE FROM sub_zones WHERE id = ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("i", $sub_zone_id);
    
    if ($stmt->execute()) {
        if ($stmt->affected_rows > 0) {
            echo json_encode([
                'success' => true,
                'message' => 'Sub-zone deleted successfully'
            ]);
        } else {
            echo json_encode([
                'success' => false,
                'message' => 'Sub-zone not found'
            ]);
        }
    } else {
        echo json_encode([
            'success' => false,
            'message' => 'Failed to delete sub-zone'
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
