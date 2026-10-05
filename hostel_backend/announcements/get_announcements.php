<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

$sql = "SELECT id, title, content, date, posted_by, warden_name, created_at FROM announcements ORDER BY date DESC, id DESC LIMIT 20";
$result = $conn->query($sql);

if (!$result) {
    // Fallback if posted_by or warden_name columns are not yet in some environments
    $sql = "SELECT * FROM announcements ORDER BY date DESC, id DESC LIMIT 20";
    $result = $conn->query($sql);
}

$announcements = array();
if ($result && $result->num_rows > 0) {
    while($row = $result->fetch_assoc()) {
        $announcements[] = $row;
    }
}

echo json_encode(array("status" => "success", "data" => $announcements));
$conn->close();
?>
