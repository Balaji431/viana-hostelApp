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

if (php_sapi_name() !== 'cli') echo "🚀 Restarting migration with correct registration number handling...\n";

$conn->autocommit(false);
try {
    // Clear the table first for a clean migration
    $conn->query("TRUNCATE TABLE room_change_requests");
    
    $query = "
        SELECT 
            r.id as old_id,
            r.request_id as old_request_id,
            r.student_id,
            u.username as student_name,
            u.RegisterNumber as student_reg_no,
            r.current_room,
            r.requested_room,
            r.change_reason as reason,
            r.status,
            r.created_at
        FROM request1 r
        JOIN users u ON r.student_id = u.id
        WHERE u.role = 'student' 
        AND (r.request_type = 'Room Change' OR r.requested_room IS NOT NULL)
    ";
    
    $result = $conn->query($query);
    if (!$result) throw new Exception($conn->error);
    
    while ($row = $result->fetch_assoc()) {
        $request_id = !empty($row['old_request_id']) ? $row['old_request_id'] : ('RCR-MIG-' . str_pad($row['old_id'], 6, '0', STR_PAD_LEFT));
        
        // Use registration number if available, otherwise use username as requested in modern schema
        $reg_no = !empty($row['student_reg_no']) ? $row['student_reg_no'] : $row['student_name'];
        
        $insert_query = "
            INSERT INTO room_change_requests (
                request_id, student_id, student_name, student_reg_no, 
                current_room, requested_room, reason, status, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ";
        
        $stmt = $conn->prepare($insert_query);
        $status = strtolower($row['status'] ?? 'pending');
        if (!in_array($status, ['pending', 'approved', 'rejected', 'completed'])) $status = 'pending';
        
        $current_room = $row['current_room'] ?? 'Unknown';
        $requested_room = $row['requested_room'] ?? 'Unknown';
        $reason = !empty($row['reason']) ? $row['reason'] : 'Migrated from request1';
        $created_at = $row['created_at'] ?? date('Y-m-d H:i:s');

        $stmt->bind_param("sisssssss", 
            $request_id, $row['student_id'], $row['student_name'], $reg_no,
            $current_room, $requested_room, $reason, $status, $created_at);
        
        $stmt->execute();
        echo "✅ Migrated {$request_id} for student {$row['student_name']}\n";
    }
    
    $conn->commit();
    echo "✨ Migration successful!\n";
} catch (Exception $e) {
    if (isset($conn)) $conn->rollback();
    echo "💥 Error: " . $e->getMessage() . "\n";
}
if (isset($conn)) $conn->close();
?>
