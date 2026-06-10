<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

$database = new Database();
$db = $database->getConnection();

$warden_username = $_GET['warden_username'] ?? null;
$student_username = $_GET['student_username'] ?? null;

// Get total unread messages sent TO THE SPECIFIC WARDEN or STUDENT for each department/category
// Using Universal Translation (CONVERT) to handle mixed character sets
if ($student_username) {
    $sql = "SELECT r.department, COUNT(*) as unread_count 
            FROM chat_messages m 
            JOIN request1 r ON (CONVERT(m.request_id USING utf8mb4) = CONVERT(r.request_id USING utf8mb4)) 
            WHERE (m.status = 'sent' OR m.status = 'delivered') 
              AND m.message_type NOT IN ('request_card', 'status')
              AND CONVERT(m.receiver_id USING utf8mb4) = CONVERT(:student_username USING utf8mb4) 
              AND CONVERT(m.sender_id USING utf8mb4) != CONVERT(m.receiver_id USING utf8mb4)
            GROUP BY r.department";
} elseif ($warden_username) {
    $sql = "SELECT r.department, COUNT(*) as unread_count 
            FROM chat_messages m 
            JOIN request1 r ON (CONVERT(m.request_id USING utf8mb4) = CONVERT(r.request_id USING utf8mb4)) 
            WHERE (m.status = 'sent' OR m.status = 'delivered') 
              AND m.message_type NOT IN ('request_card', 'status')
              AND CONVERT(m.receiver_id USING utf8mb4) = CONVERT(:warden_username USING utf8mb4) 
              AND CONVERT(m.sender_id USING utf8mb4) != CONVERT(m.receiver_id USING utf8mb4)
            GROUP BY r.department";
} else {
    // No valid username supplied — return all-zero summary safely
    echo json_encode(array(
        "status" => "success",
        "data"   => array("warden" => 0, "parent_warden" => 0, "security" => 0, "maintenance" => 0)
    ));
    exit;
}

try {
    $stmt = $db->prepare($sql);
    if ($student_username) {
        $stmt->bindParam(':student_username', $student_username);
    } elseif ($warden_username) {
        $stmt->bindParam(':warden_username', $warden_username);
    }
    $stmt->execute();
    
    // Build summary dynamically with lowercase keys to match new_categories1.name values
    // Pre-seed with known categories at 0
    $summary = array(
        "warden"       => 0,
        "parent_warden"=> 0,
        "security"     => 0,
        "maintenance"  => 0
    );

    while($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $raw_dept = $row['department'];
        // Normalize: lowercase, fix 'messages' alias
        $dept = strtolower(trim($raw_dept));
        if ($dept == 'messages') $dept = 'warden';
        // Add to summary (include dynamic depts like 'electricity', 'maintenance3')
        $summary[$dept] = (int)$row['unread_count'];
    }

    echo json_encode(array("status" => "success", "data" => $summary));
} catch (Exception $e) {
    echo json_encode(array("status" => "error", "message" => $e->getMessage()));
}
?>