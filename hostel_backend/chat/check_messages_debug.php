<?php
require_once __DIR__ . '/../config/database.php';
$database = new Database();
$db = $database->getConnection();

echo "<h2>Rajesh Kumar (rajesh1) Unread Messages:</h2>";
$sql = "SELECT m.*, r.department 
        FROM chat_messages m 
        JOIN request1 r ON (CONVERT(m.request_id USING utf8mb4) = CONVERT(r.request_id USING utf8mb4)) 
        WHERE (m.status = 'sent' OR m.status = 'delivered') 
          AND m.message_type NOT IN ('request_card', 'status')
          AND CONVERT(m.receiver_id USING utf8mb4) = CONVERT('rajesh1' USING utf8mb4)";
$stmt = $db->query($sql);
if ($stmt) {
    while($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        echo "<pre>";
        print_r($row);
        echo "</pre>";
    }
} else {
    echo "No messages found or query failed.";
}

echo "<h2>Bharat Bro (bharat1) Unread Messages:</h2>";
$sql2 = "SELECT m.*, r.department 
        FROM chat_messages m 
        JOIN request1 r ON (CONVERT(m.request_id USING utf8mb4) = CONVERT(r.request_id USING utf8mb4)) 
        WHERE (m.status = 'sent' OR m.status = 'delivered') 
          AND m.message_type NOT IN ('request_card', 'status')
          AND CONVERT(m.receiver_id USING utf8mb4) = CONVERT('bharat1' USING utf8mb4)";
$stmt2 = $db->query($sql2);
if ($stmt2) {
    while($row = $stmt2->fetch(PDO::FETCH_ASSOC)) {
        echo "<pre>";
        print_r($row);
        echo "</pre>";
    }
} else {
    echo "No messages found or query failed.";
}
?>
