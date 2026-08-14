<?php
$ch = curl_init('http://localhost:8081/auth/login.php');
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 5);
$res = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

echo "Backend HTTP Code: $code\n";
echo "Backend Response: $res\n";

$ch2 = curl_init('http://localhost:8080/config.json');
curl_setopt($ch2, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch2, CURLOPT_TIMEOUT, 5);
$res2 = curl_exec($ch2);
$code2 = curl_getinfo($ch2, CURLINFO_HTTP_CODE);
curl_close($ch2);

echo "Frontend config.json HTTP Code: $code2\n";
echo "Frontend config.json Response: $res2\n";
