<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once '../config/api_config.php';

try {
    $externalApiUrl = 'https://vstudy.saveetha.com/api/hostel-settings/room-types/external';
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $externalApiUrl);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 30);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'x-client-id: ' . VSTUDY_CLIENT_ID,
        'x-client-secret: ' . VSTUDY_CLIENT_SECRET
    ]);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    if ($httpCode == 200 && $response) {
        $data = json_decode($response, true);
        $list = isset($data['data']) ? $data['data'] : (is_array($data) ? $data : []);
        echo json_encode([
            "status" => "success",
            "success" => true,
            "data" => $list
        ]);
    } else {
        echo json_encode([
            "status" => "error",
            "success" => false,
            "message" => "Failed to fetch room types from external API"
        ]);
    }
} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
?>
