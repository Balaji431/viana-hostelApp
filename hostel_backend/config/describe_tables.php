<?php
$conn = new PDO("mysql:host=localhost;dbname=stay_simats", "root", "");
echo "USERS TABLE:\n";
$stmt = $conn->query("DESCRIBE users");
print_r($stmt->fetchAll(PDO::FETCH_ASSOC));
echo "\nPAYMENT TABLE:\n";
$stmt = $conn->query("DESCRIBE payment");
print_r($stmt->fetchAll(PDO::FETCH_ASSOC));
echo "\nPROFILE TABLE:\n";
$stmt = $conn->query("DESCRIBE profile");
print_r($stmt->fetchAll(PDO::FETCH_ASSOC));
?>
