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

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit(0);
}

try {
    // Get optional status filter
    $status_filter = isset($_GET['status']) ? $_GET['status'] : null;
    
    // Base query
    $query = "
        SELECT 
            r.id,
            r.request_id,
            r.student_id,
            u.full_name as student_name,
            u.username as student_reg_no,
            r.current_room,
            r.requested_room,
            r.change_reason as reason,
            r.status,
            r.created_at,
            r.updated_at
        FROM request1 r
        JOIN users u ON r.student_id = u.id
        WHERE r.request_type = 'room_change'
    ";
    
    $params = [];
    $types = "";
    
    // Add status filter if provided
    if ($status_filter && in_array($status_filter, ['pending', 'approved', 'rejected', 'completed'])) {
        $query .= " AND r.status = ?";
        $params[] = $status_filter;
        $types .= "s";
    }
    
    $query .= " ORDER BY r.created_at DESC";
    
    $get_requests = $conn->prepare($query);
    
    if (!empty($params)) {
        $get_requests->bind_param($types, ...$params);
    }
    
    $get_requests->execute();
    $result = $get_requests->get_result();
    
    $requests = [];
    while ($row = $result->fetch_assoc()) {
        $requests[] = [
            'id' => (int)$row['id'],
            'request_id' => $row['request_id'],
            'student_id' => (int)$row['student_id'],
            'student_name' => $row['student_name'],
            'student_reg_no' => $row['student_reg_no'],
            'current_room' => $row['current_room'],
            'requested_room' => $row['requested_room'],
            'reason' => $row['reason'],
            'status' => $row['status'],
            'created_at' => $row['created_at'],
            'updated_at' => $row['updated_at']
        ];
    }
    
    echo json_encode([
        'status' => 'success',
        'message' => 'Room change requests retrieved successfully',
        'data' => $requests
    ]);
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}

$conn->close();
?>
