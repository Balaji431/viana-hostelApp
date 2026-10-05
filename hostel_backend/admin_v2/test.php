<?php
if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    echo json_encode(["status" => "error", "message" => "Forbidden: CLI access only"]);
    exit();
}
$_GET['hostel_name'] = 'Krishna Hostel';
require 'get_external_fees.php';
