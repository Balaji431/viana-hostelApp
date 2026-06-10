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
    // Get JSON input
    $json_input = file_get_contents('php://input');
    $data = json_decode($json_input, true);
    
    if (!$data) {
        throw new Exception('Invalid JSON data');
    }
    
    // Validate required fields
    $required_fields = ['request_id', 'status', 'warden_id'];
    foreach ($required_fields as $field) {
        if (!isset($data[$field]) || empty(trim($data[$field]))) {
            throw new Exception("Missing required field: $field");
        }
    }
    
    $request_id = trim($data['request_id']);
    $status = trim($data['status']);
    $warden_id = (int)$data['warden_id'];
    
    // Validate status
    if (!in_array($status, ['approved', 'rejected', 'completed'])) {
        throw new Exception('Invalid status. Must be: approved, rejected, or completed');
    }
    
    // Create storage instance
    $storage = new SimpleStorage();
    
    // Check if request exists
    $requests = $storage->readRequests();
    $request_exists = false;
    foreach ($requests as $req) {
        if ($req['requestId'] === $request_id) {
            $request_exists = true;
            break;
        }
    }
    
    if (!$request_exists) {
        throw new Exception('Room change request not found');
    }
    
    // Update the request
    $storage->updateRequest($request_id, $status);
    
    // Get updated request details
    $updated_request = [
        'request_id' => $request_id,
        'status' => $status,
        'updated_at' => date('Y-m-d H:i:s'),
        'processed_by' => $warden_id
    ];
    
    echo json_encode([
        'status' => 'success',
        'message' => "Room change request $status successfully",
        'data' => $updated_request
    ]);
    
} catch(Exception $e) {
    http_response_code(400);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}
?>
