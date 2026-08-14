<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

$reg_no = '192511250';
$warden = 'Kanita K';

$stmt = $db->prepare("UPDATE profile SET warden = :warden WHERE reg_no = :reg OR email = :email");
$stmt->execute([':warden' => $warden, ':reg' => $reg_no, ':email' => '192511250.simats@saveetha.com']);

echo "Updated profile table warden column to '$warden' for $reg_no (rows affected: " . $stmt->rowCount() . ").\n";

$verify = $db->query("SELECT id, full_name, reg_no, warden, room_allocation FROM profile WHERE reg_no = '$reg_no'")->fetch(PDO::FETCH_ASSOC);
print_r($verify);
