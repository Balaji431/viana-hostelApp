<?php
require_once __DIR__ . '/../config/database.php';
$db = new Database();
$conn = $db->getConnection();
if (!$conn) {
    echo "Connection failed\n";
    exit(1);
}
$stmt = $conn->query("SELECT * FROM renew_fee");
$results = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo json_encode($results, JSON_PRETTY_PRINT) . "\n";
?>
