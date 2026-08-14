<?php
echo "=== TESTING LOCAL DOCKER API RESPONSE FOR 192511250 ===\n";

$url = 'http://localhost:8081/get_user_data.php?id=4173&role=student';
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 5);
$res = curl_exec($ch);
curl_close($ch);

echo "Local API Response:\n$res\n";
