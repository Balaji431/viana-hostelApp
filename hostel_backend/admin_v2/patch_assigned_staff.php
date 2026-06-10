<?php
header('Content-Type: application/json');
$target = '../chat/get_assigned_staff.php';

$content = <<<'EOD'
<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

require_once '../config/database.php';

$student_id = $_GET['student_id'] ?? null;

if (!$student_id) {
    echo json_encode(['success' => false, 'message' => 'Student ID is required']);
    exit;
}

try {
    $database = new Database();
    $db = $database->getConnection();

    // 1. Get student's location details
    $query = "SELECT hr.hostel_name, hr.floor, hr.wing_code
              FROM users u
              JOIN profile p ON u.username = p.reg_no
              JOIN hostel_rooms hr ON p.room_allocation = hr.room_code
              WHERE u.id = :id LIMIT 1";
    
    $stmt = $db->prepare($query);
    $stmt->bindParam(':id', $student_id);
    $stmt->execute();
    
    $location = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$location) {
        echo json_encode(['success' => false, 'message' => 'No room allocation found for this student']);
        exit;
    }

    $h_name = $location['hostel_name'];
    $f_name = $location['floor'];
    $w_name = $location['wing_code'];

    // 2. Find staff matching this location in mapping_staff
    $staff_query = "SELECT name, role, phone, username 
                   FROM mapping_staff 
                   WHERE (hostel_name = :h_name OR hostel_name IS NULL OR hostel_name = '')
                   AND (floor_name = :f_name OR floor_name IS NULL OR floor_name = '')
                   AND (wing_name = :w_name OR wing_name IS NULL OR wing_name = '')
                   ORDER BY (CASE WHEN wing_name = :w_name THEN 4 ELSE 0 END) + 
                            (CASE WHEN floor_name = :f_name THEN 2 ELSE 0 END) +
                            (CASE WHEN hostel_name = :h_name THEN 1 ELSE 0 END) DESC";
    
    $stmt = $db->prepare($staff_query);
    $stmt->bindParam(':h_name', $h_name);
    $stmt->bindParam(':f_name', $f_name);
    $stmt->bindParam(':w_name', $w_name);
    $stmt->execute();
    
    $staff_list = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    // 3. Get all available staff roles from categories dynamically
    $roles_query = "SELECT name FROM new_categories1 WHERE is_staff_role = 1";
    $roles_stmt = $db->query($roles_query);
    $active_roles = $roles_stmt->fetchAll(PDO::FETCH_COLUMN);
    
    $result = [];
    foreach ($active_roles as $role_name) {
        $result[$role_name] = null;
    }

    foreach ($staff_list as $staff) {
        $role = $staff['role'];
        if (array_key_exists($role, $result)) {
            if ($result[$role] === null) {
                $result[$role] = $staff;
            }
        }
    }

    echo json_encode([
        'success' => true,
        'data' => $result
    ]);

} catch (Exception $e) {
    echo json_encode(['success' => false, 'message' => 'Server error: ' . $e->getMessage()]);
}
?>
EOD;

if (file_put_contents($target, $content)) {
    echo json_encode(['status' => 'success', 'message' => 'File patched successfully']);
} else {
    echo json_encode(['status' => 'error', 'message' => 'Failed to patch file']);
}
?>
