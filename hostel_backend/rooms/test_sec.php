<?php
if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    echo json_encode(["status" => "error", "message" => "Forbidden: CLI access only"]);
    exit();
}
require_once __DIR__ . '/../config/database.php';
$db = (new Database())->getConnection();

$stmt = $db->query("SELECT COUNT(*) as total_rows, COUNT(DISTINCT room_number) as total_distinct_rooms FROM rooms_groups_details WHERE group_name LIKE '%Krishna Hostel(New) First Floor%'");
print_r($stmt->fetch(PDO::FETCH_ASSOC));
