<?php
require_once __DIR__ . '/../config/database.php';
$database = new Database();
$db = $database->getConnection();

echo "<h2>Distinct Statuses in request1:</h2>";
$stmt = $db->query("SELECT status, COUNT(*) as cnt FROM request1 GROUP BY status");
if ($stmt) {
    while($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        echo "<pre>"; print_r($row); echo "</pre>";
    }
}
?>
