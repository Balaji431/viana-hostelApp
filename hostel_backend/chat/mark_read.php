<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

if (!empty($data->request_id) && !empty($data->user_id)) {
    $request_id = $data->request_id;
    $user_input = $data->user_id;

    try {
        // Resolve username - Check BOTH users table and parent_users table
        $user_query = $db->prepare("SELECT username FROM users WHERE id = ? OR username = ? LIMIT 1");
        $user_query->execute([$user_input, $user_input]);
        $user_row = $user_query->fetch(PDO::FETCH_ASSOC);
        
        if ($user_row) {
            $username = $user_row['username'];
        } else {
            $parent_query = $db->prepare("SELECT parent_id as username FROM parent_users WHERE id = ? OR parent_id = ? LIMIT 1");
            $parent_query->execute([$user_input, $user_input]);
            $parent_row = $parent_query->fetch(PDO::FETCH_ASSOC);
            $username = $parent_row ? $parent_row['username'] : $user_input;
        }

        // Resolve the "Conversation" details from the current request_id
        $thread_query = $db->prepare("SELECT student_id, department FROM request1 WHERE CONVERT(request_id USING utf8mb4) = CONVERT(? USING utf8mb4) LIMIT 1");
        $thread_query->execute([$request_id]);
        $thread = $thread_query->fetch(PDO::FETCH_ASSOC);

        $dept_clean = $thread ? strtolower($thread['department']) : '';
        $dept_pat = '%' . $dept_clean . '%';
        if (strpos($dept_clean, 'maint') !== false) $dept_pat = '%maint%';
        if (strpos($dept_clean, 'sec') !== false) $dept_pat = '%sec%';
        if (strpos($dept_clean, 'warden') !== false) $dept_pat = '%warden%';

        if ($thread) {
            $student_id = $thread['student_id'];
            $department = $thread['department'];

            // Mark ALL messages in this thread as seen with Universal Translation
            $query = "UPDATE chat_messages m
                     JOIN request1 r ON (CONVERT(m.request_id USING utf8mb4) = CONVERT(r.request_id USING utf8mb4))
                     SET m.status = 'seen' 
                     WHERE (
                         CONVERT(m.request_id USING utf8mb4) = CONVERT(:req_id USING utf8mb4)
                         OR (
                             r.student_id = :student_id 
                             AND (LOWER(r.department) = LOWER(:dept) OR LOWER(r.department) LIKE :dept_pat)
                         )
                     )
                     AND CONVERT(m.sender_id USING utf8mb4) != CONVERT(:user USING utf8mb4)
                     AND m.status IN ('sent', 'delivered')";

            $stmt = $db->prepare($query);
            $stmt->bindParam(':req_id', $request_id);
            $stmt->bindParam(':student_id', $student_id);
            $stmt->bindParam(':dept', $department);
            $stmt->bindParam(':dept_pat', $dept_pat);
            $stmt->bindParam(':user', $username);
            $stmt->execute();
            $affected = $stmt->rowCount();

            // Fallback: If joined update affected 0 rows, update directly by request_id
            if ($affected === 0) {
                $f_stmt = $db->prepare("UPDATE chat_messages SET status = 'seen' WHERE CONVERT(request_id USING utf8mb4) = CONVERT(? USING utf8mb4) AND CONVERT(sender_id USING utf8mb4) != CONVERT(? USING utf8mb4) AND status IN ('sent', 'delivered')");
                $f_stmt->execute([$request_id, $username]);
                $affected = $f_stmt->rowCount();
            }

            echo json_encode([
                "success" => true,
                "message" => "Conversation marked as seen",
                "affected_rows" => $affected
            ]);
        } else {
            // Fallback: If request1 record doesn't exist yet, just mark by request_id directly
            $query = "UPDATE chat_messages SET status = 'seen' WHERE CONVERT(request_id USING utf8mb4) = CONVERT(? USING utf8mb4) AND CONVERT(sender_id USING utf8mb4) != CONVERT(? USING utf8mb4) AND status IN ('sent', 'delivered')";
            $stmt = $db->prepare($query);
            $stmt->execute([$request_id, $username]);
            echo json_encode(["success" => true, "message" => "Individual request marked (fallback)", "affected_rows" => $stmt->rowCount()]);
        }
    } catch (Exception $e) {
        echo json_encode(["success" => false, "message" => $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Incomplete data"]);
}
?>
