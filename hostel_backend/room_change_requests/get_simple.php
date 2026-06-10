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



require_once 'simple_storage.php';

try {
    // Get optional status filter
    $status_filter = isset($_GET['status']) ? $_GET['status'] : null;
    
    // Create storage instance
    $storage = new SimpleStorage();
    
    // Get requests
    $requests = $storage->getRequests($status_filter);
    
    echo json_encode([
        'status' => 'success',
        'message' => 'Room change requests retrieved successfully',
        'data' => $requests
    ]);
    
} catch(Exception $e) {
    http_response_code(400);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}
?>
