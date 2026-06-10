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

// Simple file-based storage for room change requests
class SimpleStorage {
    private $file_path;
    
    public function __construct() {
        $this->file_path = __DIR__ . '/room_change_requests.json';
    }
    
    public function readRequests() {
        if (!file_exists($this->file_path)) {
            return [];
        }
        $json = file_get_contents($this->file_path);
        return json_decode($json, true) ?: [];
    }
    
    public function writeRequests($requests) {
        return file_put_contents($this->file_path, json_encode($requests, JSON_PRETTY_PRINT));
    }
    
    public function addRequest($request) {
        $requests = $this->readRequests();
        $request['id'] = count($requests) + 1;
        $request['createdAt'] = date('Y-m-d H:i:s');
        $request['status'] = 'pending';
        $requests[] = $request;
        $this->writeRequests($requests);
        return $request;
    }
    
    public function updateRequest($requestId, $status) {
        $requests = $this->readRequests();
        foreach ($requests as &$request) {
            if ($request['requestId'] === $requestId) {
                $request['status'] = $status;
                $request['updatedAt'] = date('Y-m-d H:i:s');
                break;
            }
        }
        $this->writeRequests($requests);
        return true;
    }
    
    public function getRequests($status = null) {
        $requests = $this->readRequests();
        if ($status) {
            $requests = array_filter($requests, function($req) use ($status) {
                return $req['status'] === $status;
            });
        }
        return array_values($requests);
    }
}
?>
