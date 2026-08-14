<?php
require '/var/www/html/config/database.php';
require '/var/www/html/config/api_config.php';

$_SERVER['REQUEST_METHOD'] = 'GET';
$_GET['search'] = 'T22-F04-W0-R08';
ob_start();
include '/var/www/html/rooms/fetch_room_master.php';
$output = ob_get_clean();

echo "--- T22-F04-W0-R08 FETCH RESPONSE ---\n";
$json = json_decode($output, true);
print_r($json['data'] ?? $output);

$_GET['search'] = 'T22-F04-W0-R14';
ob_start();
include '/var/www/html/rooms/fetch_room_master.php';
$output2 = ob_get_clean();

echo "--- T22-F04-W0-R14 FETCH RESPONSE ---\n";
$json2 = json_decode($output2, true);
print_r($json2['data'] ?? $output2);
