<?php
require_once __DIR__ . '/../config/database.php';
$db = new Database();
$conn = $db->getConnection();
if (!$conn) {
    echo "Connection failed\n";
    exit(1);
}
$query = "SELECT u.id, u.full_name, u.username as register_no, u.role,
                 p.hostel_name, p.room_allocation,
                 hr.room_no, hr.room_type as hr_room_type, hr.room_code
          FROM users u
          LEFT JOIN profile p ON u.username = p.reg_no
          LEFT JOIN hostel_rooms hr ON (hr.id = p.current_room_id OR (COALESCE(p.current_room_id, 0) = 0 AND hr.room_code = p.room_allocation))
          WHERE u.username = 'uday12' LIMIT 1";
$stmt = $conn->prepare($query);
$stmt->execute();
$results = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo json_encode($results, JSON_PRETTY_PRINT) . "\n";
?>
