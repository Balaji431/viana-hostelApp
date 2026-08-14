<?php
require '/var/www/html/config/database.php';
$db = (new Database())->getConnection();
$stmt = $db->query('DESCRIBE rooms_groups_details');
print_r($stmt->fetchAll(PDO::FETCH_COLUMN));
