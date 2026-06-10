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

$database = new DatabaseMysqli();
$conn = $database->getConnection();

$student_id = isset($_GET['student_id']) ? (int)$_GET['student_id'] : 0;

if ($student_id <= 0) {
    echo json_encode([
        'success' => false,
        'status' => 'error',
        'message' => 'Valid student ID required'
    ]);
    exit();
}

try {
    // Note: Adjusting query to use log_time if date column doesn't exist or to format log_time as date
    $query = "SELECT log_time as date, status, 'N/A' as check_in_time, 'N/A' as check_out_time, '' as remarks 
              FROM attendance 
              WHERE student_id = ? 
              ORDER BY log_time DESC 
              LIMIT 30";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param("i", $student_id);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $attendance_history = [];
    while ($row = $result->fetch_assoc()) {
        $attendance_history[] = [
            'date' => $row['date'],
            'status' => $row['status'],
            'check_in_time' => $row['check_in_time'],
            'check_out_time' => $row['check_out_time'],
            'remarks' => $row['remarks']
        ];
    }
    
    echo json_encode([
        'success' => true,
        'status' => 'success',
        'data' => $attendance_history,
        'count' => count($attendance_history)
    ]);
    
} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'status' => 'error',
        'message' => 'Database error: ' . $e->getMessage()
    ]);
}

$conn->close();
?>
