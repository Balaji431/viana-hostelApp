<?php
require_once 'C:\xampp\htdocs\hostelapp\hostel_backend\config\database.php';
$database = new Database();
$db = $database->getConnection();

echo "=== Mapped parent for student 192524101 ===\n";
$stmt = $db->prepare("SELECT * FROM parent_student_map WHERE student_id = '192524101'");
$stmt->execute();
$map = $stmt->fetch(PDO::FETCH_ASSOC);
print_r($map);

if ($map) {
    echo "=== parent_users for parent_id: " . $map['parent_id'] . " ===\n";
    $stmt2 = $db->prepare("SELECT id, parent_id, fcm_token FROM parent_users WHERE parent_id = ?");
    $stmt2->execute([$map['parent_id']]);
    print_r($stmt2->fetch(PDO::FETCH_ASSOC));
}
?>
