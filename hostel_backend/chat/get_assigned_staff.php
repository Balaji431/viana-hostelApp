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

    // 1. Get student's location details (using LEFT JOIN so we still get profile if unallocated)
    $query = "SELECT hr.hostel_name, hr.floor, hr.wing_code, p.room_allocation
              FROM users u
              LEFT JOIN profile p ON u.username = p.reg_no
              LEFT JOIN hostel_rooms hr ON p.room_allocation = hr.room_code
              WHERE u.id = :id LIMIT 1";
    
    $stmt = $db->prepare($query);
    $stmt->bindParam(':id', $student_id);
    $stmt->execute();
    
    $location = $stmt->fetch(PDO::FETCH_ASSOC);
    
    // Check if unallocated or no profile exists yet
    $is_unallocated = false;
    if (!$location || empty($location['room_allocation']) || strtolower(trim($location['room_allocation'])) === 'unallocated' || $location['room_allocation'] === null) {
        $is_unallocated = true;
    }

    // 2. Load Venkatesh (warden1) details as chief warden fallback
    $stmt_w1 = $db->prepare("SELECT name, role, phone, username FROM mapping_staff WHERE username = 'warden1' LIMIT 1");
    $stmt_w1->execute();
    $warden1 = $stmt_w1->fetch(PDO::FETCH_ASSOC);
    if (!$warden1) {
        $warden1 = [
            'name' => 'Venkatesh',
            'role' => 'Warden',
            'phone' => 'N/A',
            'username' => 'warden1'
        ];
    }

    // Get all active staff roles dynamically
    $roles_query = "SELECT name FROM new_categories1 WHERE is_staff_role = 1";
    $roles_stmt = $db->query($roles_query);
    $active_roles = $roles_stmt->fetchAll(PDO::FETCH_COLUMN);
    
    $result = [];
    foreach ($active_roles as $role_name) {
        $result[strtolower(trim($role_name))] = null;
    }

    if ($is_unallocated) {
        // If unallocated, all staff roles remain null so direct chat pages show "Not Assigned" in the UI
    } else {
        // Allocated: Fetch and map to their specific wing/floor wardens
        $h_name = $location['hostel_name'];
        $f_name = $location['floor'];
        $w_name = $location['wing_code'];

        $staff_query = "SELECT ms.name, ms.role, ms.phone, ms.username 
                       FROM mapping_staff ms
                       WHERE (
                            LOWER(TRIM(ms.hostel_name)) = LOWER(TRIM(:h_name))
                            OR LOWER(TRIM(ms.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(:h_name)), '%')
                            OR LOWER(TRIM(:h_name)) LIKE CONCAT('%', LOWER(TRIM(ms.hostel_name)), '%')
                            OR ms.hostel_name IS NULL OR ms.hostel_name = ''
                       )
                       AND (
                            LOWER(TRIM(ms.floor_name)) = LOWER(TRIM(:f_name))
                            OR (LOWER(TRIM(:f_name)) IN ('f00', 'ground', 'ground floor') AND LOWER(TRIM(ms.floor_name)) IN ('f00', 'ground', 'ground floor'))
                            OR (LOWER(TRIM(:f_name)) IN ('f01', '1st floor') AND LOWER(TRIM(ms.floor_name)) IN ('f01', '1st floor'))
                            OR (LOWER(TRIM(:f_name)) IN ('f02', '2nd floor') AND LOWER(TRIM(ms.floor_name)) IN ('f02', '2nd floor'))
                            OR (LOWER(TRIM(:f_name)) IN ('f03', '3rd floor') AND LOWER(TRIM(ms.floor_name)) IN ('f03', '3rd floor'))
                            OR ms.floor_name IS NULL OR ms.floor_name = ''
                       )
                       AND (LOWER(TRIM(ms.wing_name)) = LOWER(TRIM(:w_name)) OR ms.wing_name IS NULL OR ms.wing_name = '')
                       ORDER BY 
                            (CASE WHEN LOWER(TRIM(ms.wing_name)) = LOWER(TRIM(:w_name)) THEN 10 ELSE 0 END) +
                            (CASE WHEN LOWER(TRIM(ms.floor_name)) = LOWER(TRIM(:f_name)) 
                                  OR (LOWER(TRIM(:f_name)) IN ('f00', 'ground') AND LOWER(TRIM(ms.floor_name)) IN ('f00', 'ground'))
                                  OR (LOWER(TRIM(:f_name)) IN ('f01', '1st floor') AND LOWER(TRIM(ms.floor_name)) IN ('f01', '1st floor'))
                                  THEN 5 ELSE 0 END) +
                            (CASE WHEN LOWER(TRIM(ms.hostel_name)) = LOWER(TRIM(:h_name)) THEN 1 ELSE 0 END) DESC";
        
        $stmt = $db->prepare($staff_query);
        $stmt->bindParam(':h_name', $h_name);
        $stmt->bindParam(':f_name', $f_name);
        $stmt->bindParam(':w_name', $w_name);
        $stmt->execute();
        
        $staff_list = $stmt->fetchAll(PDO::FETCH_ASSOC);

        foreach ($staff_list as $staff) {
            $role = strtolower(trim($staff['role']));
            if (array_key_exists($role, $result)) {
                if ($result[$role] === null) {
                    $result[$role] = $staff;
                }
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