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

// Initialize database connection
$database = new DatabaseMysqli();
$conn = $database->getConnection();

/**
 * Helper to fetch exact fee from renew_fee table or hardcoded requirements
 */
function getFeeForRoomType($conn, $room_type_name) {
    if (empty($room_type_name)) return 0;
    
    $normalized = strtoupper(trim($room_type_name));
    
    // Exact requirement for AC - B ATTACHED (6 IN 1) or variants
    if ($normalized === 'AC - B ATTACHED (6 IN 1)' || $normalized === 'AC - B ATTACHED') {
        return 65000.00;
    }
    
    // Look up in renew_fee table
    $query = "SELECT six_month_amount, monthly_amount FROM renew_fee WHERE UPPER(TRIM(room_type)) = ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("s", $normalized);
    $stmt->execute();
    $res = $stmt->get_result()->fetch_assoc();
    
    if ($res) {
        if (floatval($res['six_month_amount']) > 0) return (float)$res['six_month_amount'];
        if (floatval($res['monthly_amount']) > 0) return (float)$res['monthly_amount'] * 12;
    }
    
    return 0;
}

try {
    if (!isset($_GET['student_id'])) {
        throw new Exception('Student ID is required');
    }
    
    $student_id = (int)$_GET['student_id'];
    
    $get_requests = $conn->prepare("
        SELECT 
            r.*,
            hr.amount as room_amount,
            hr.room_type as hr_room_type
        FROM room_change_requests r
        LEFT JOIN hostel_rooms hr ON r.requested_room = hr.room_code
        WHERE r.student_id = ?
        ORDER BY r.created_at DESC
    ");
    
    $get_requests->bind_param("i", $student_id);
    $get_requests->execute();
    $result = $get_requests->get_result();
    
    $requests = [];
    while ($row = $result->fetch_assoc()) {
        $amount = (float)$row['amount_to_pay'];
        $rtype = $row['requested_room_type'] ?? $row['hr_room_type'] ?? 'Standard';
        
        // Lazy fix/normalization for amounts
        if (($row['status'] == 'pre_approved' || $row['status'] == 'approved') && $amount <= 0) {
            $amount = getFeeForRoomType($conn, $rtype);
            if ($amount <= 0) {
                $amount = (float)$row['room_amount'];
            }
            
            // Persist the fix if we found a valid amount
            if ($amount > 0) {
                $upd = $conn->prepare("UPDATE room_change_requests SET amount_to_pay = ? WHERE request_id = ?");
                $upd->bind_param("ds", $amount, $row['request_id']);
                $upd->execute();
            }
        }
        
        $requests[] = [
            'request_id' => $row['request_id'],
            'student_id' => (int)$row['student_id'],
            'student_name' => $row['student_name'],
            'student_reg_no' => $row['student_reg_no'],
            'current_room' => $row['current_room'],
            'requested_room' => $row['requested_room'],
            'requested_room_type' => $rtype,
            'reason' => $row['reason'],
            'status' => $row['status'],
            'processed_by' => $row['processed_by'] ? (int)$row['processed_by'] : null,
            'processed_by_name' => $row['processed_by_name'],
            'remarks' => $row['remarks'],
            'created_at' => $row['created_at'],
            'updated_at' => $row['updated_at'],
            'reserved_until' => $row['reserved_until'],
            'payment_status' => $row['payment_status'] ?? 'unpaid',
            'amount_to_pay' => $amount
        ];
    }
    
    echo json_encode([
        'success' => true,
        'status' => 'success',
        'message' => 'Room change requests retrieved successfully',
        'data' => $requests
    ]);
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}
?>
