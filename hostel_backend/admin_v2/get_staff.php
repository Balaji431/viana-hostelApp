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

$status_filter = isset($_GET['status']) ? trim($_GET['status']) : '';
$role_filter = isset($_GET['role']) ? trim($_GET['role']) : '';
$limit = isset($_GET['limit']) ? (int)$_GET['limit'] : 50;
$offset = isset($_GET['offset']) ? (int)$_GET['offset'] : 0;

try {
    $query = "SELECT sm.id, sm.staff_id, sm.name, sm.email, sm.phone, sm.role, 
                     sm.employee_id, sm.status, sm.created_at, sm.updated_at,
                     h.hostel_name, h.hostel_code
              FROM staff_members sm
              LEFT JOIN hostels h ON sm.hostel_id = h.id";
    
    $params = [];
    $types = '';
    $where_clauses = [];
    
    if (!empty($status_filter)) {
        $where_clauses[] = "sm.status = ?";
        $params[] = $status_filter;
        $types .= 's';
    }
    
    if (!empty($role_filter)) {
        $where_clauses[] = "sm.role = ?";
        $params[] = $role_filter;
        $types .= 's';
    }
    
    if (!empty($where_clauses)) {
        $query .= " WHERE " . implode(' AND ', $where_clauses);
    }
    
    $query .= " ORDER BY sm.created_at DESC LIMIT ? OFFSET ?";
    $params[] = $limit;
    $params[] = $offset;
    $types .= 'ii';
    
    $stmt = $conn->prepare($query);
    
    if (!empty($params)) {
        $stmt->bind_param($types, ...$params);
    }
    
    $stmt->execute();
    $result = $stmt->get_result();
    
    $staff = [];
    while ($row = $result->fetch_assoc()) {
        $staff[] = [
            'id' => (int)$row['id'],
            'staff_id' => $row['staff_id'],
            'name' => $row['name'],
            'email' => $row['email'],
            'phone' => $row['phone'],
            'role' => $row['role'],
            'employee_id' => $row['employee_id'],
            'status' => $row['status'],
            'hostel_name' => $row['hostel_name'],
            'hostel_code' => $row['hostel_code'],
            'created_at' => $row['created_at'],
            'updated_at' => $row['updated_at']
        ];
    }
    
    // Get total count
    $count_query = "SELECT COUNT(*) as total FROM staff_members sm";
    if (!empty($where_clauses)) {
        $count_query .= " WHERE " . implode(' AND ', $where_clauses);
        $count_stmt = $conn->prepare($count_query);
        $count_stmt->bind_param(substr($types, 0, -2), ...array_slice($params, 0, -2));
    } else {
        $count_stmt = $conn->prepare($count_query);
    }
    $count_stmt->execute();
    
    $count_result = $count_stmt->get_result();
    $total_count = $count_result->fetch_assoc()['total'];
    
    echo json_encode([
        'success' => true,
        'data' => $staff,
        'count' => count($staff),
        'total' => (int)$total_count,
        'limit' => $limit,
        'offset' => $offset
    ]);
    
} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'message' => 'Database error: ' . $e->getMessage()
    ]);
}

$conn->close();
?>
