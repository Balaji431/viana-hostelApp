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



$role_filter = isset($_GET['role']) ? trim($_GET['role']) : '';
$limit = isset($_GET['limit']) ? (int)$_GET['limit'] : 50;
$offset = isset($_GET['offset']) ? (int)$_GET['offset'] : 0;

try {
    $query = "SELECT u.id, u.username, u.full_name, u.role, u.conduct, u.conduct_remarks, 
                     p.email, p.personal_phone, p.room_allocation, p.institution, 
                     p.hostel_name, p.address, p.dob, p.profile_pic, p.valid_from, p.valid_to
              FROM users u
              LEFT JOIN profile p ON u.username = p.reg_no";
    
    $params = [];
    $types = '';
    
    if (!empty($role_filter)) {
        $query .= " WHERE u.role = ?";
        $params[] = $role_filter;
        $types .= 's';
    }
    
    $query .= " ORDER BY u.id DESC LIMIT ? OFFSET ?";
    $params[] = $limit;
    $params[] = $offset;
    $types .= 'ii';
    
    $stmt = $conn->prepare($query);
    
    if (!empty($params)) {
        $stmt->bind_param($types, ...$params);
    }
    
    $stmt->execute();
    $result = $stmt->get_result();
    
    $students = [];
    while ($row = $result->fetch_assoc()) {
        $students[] = [
            'id' => (int)$row['id'],
            'username' => $row['username'],
            'full_name' => $row['full_name'],
            'role' => $row['role'],
            'conduct' => $row['conduct'],
            'conduct_remarks' => $row['conduct_remarks'],
            'email' => $row['email'],
            'phone' => $row['personal_phone'],
            'room_allocation' => $row['room_allocation'],
            'institution' => $row['institution'],
            'hostel_name' => $row['hostel_name'],
            'address' => $row['address'],
            'dob' => $row['dob'],
            'profile_pic' => $row['profile_pic'],
            'valid_from' => $row['valid_from'],
            'valid_to' => $row['valid_to']
        ];
    }
    
    // Get total count
    $count_query = "SELECT COUNT(*) as total FROM users u";
    if (!empty($role_filter)) {
        $count_query .= " WHERE u.role = ?";
        $count_stmt = $conn->prepare($count_query);
        $count_stmt->bind_param("s", $role_filter);
        $count_stmt->execute();
    } else {
        $count_stmt = $conn->prepare($count_query);
        $count_stmt->execute();
    }
    
    $count_result = $count_stmt->get_result();
    $total_count = $count_result->fetch_assoc()['total'];
    
    echo json_encode([
        'success' => true,
        'data' => $students,
        'count' => count($students),
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
