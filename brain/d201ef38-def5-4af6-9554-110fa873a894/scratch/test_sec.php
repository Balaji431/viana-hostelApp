<?php
require_once 'c:\xampp\htdocs\hostelapp\hostel_backend\config\database.php';
$db_class = new Database();
$db = $db_class->getConnection();

$sec1 = $db->query("SELECT bio_id, employee_name as name, email, phone, department, 'Security' as designation, 'security' as role FROM security_users")->fetchAll(PDO::FETCH_ASSOC);
$sec2 = $db->query("SELECT username as bio_id, full_name as name, email, phone_number as phone, 'Security' as department, COALESCE(Designation, 'Security Guard') as designation, 'security' as role FROM users WHERE LOWER(role) = 'security'")->fetchAll(PDO::FETCH_ASSOC);
$sec3 = $db->query("SELECT bio_id, name, email, phone, dept as department, desig as designation, 'security' as role FROM staff_users WHERE LOWER(role) = 'security'")->fetchAll(PDO::FETCH_ASSOC);

$secList = [];
$seenSec = [];
foreach (array_merge($sec1, $sec2, $sec3) as $s) {
    $id = trim($s['bio_id'] ?? '');
    if (!$id || isset($seenSec[$id])) continue;
    $seenSec[$id] = true;
    $secList[] = $s;
}

echo count($secList) . " security users found.";
?>
