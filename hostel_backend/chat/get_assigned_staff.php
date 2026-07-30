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
    $query = "SELECT rgd.hostel_name, rgd.group_name as floor_group, p.room_allocation
              FROM users u
              LEFT JOIN profile p ON TRIM(u.username) = TRIM(p.reg_no)
              LEFT JOIN rooms_groups_details rgd ON TRIM(p.room_allocation) = TRIM(rgd.room_number)
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
    $active_roles = $roles_stmt ? $roles_stmt->fetchAll(PDO::FETCH_COLUMN) : [];
    
    $result = [
        'warden' => null,
        'security' => null,
        'maintenannce' => null,
        'maintenance' => null,
    ];
    foreach ($active_roles as $role_name) {
        $result[strtolower(trim($role_name))] = null;
    }

    if ($is_unallocated) {
        // If unallocated, all staff roles remain null so direct chat pages show "Not Assigned" in the UI
    } else {
        // Allocated: Fetch and map to their specific wing/floor wardens
        $h_name = $location['hostel_name'] ?? '';
        $f_name = '';
        $w_name = '';

        $room = trim($location['room_allocation']);
        $parts = explode('-', $room);
        $f_code = '';
        $w_code = '';

        foreach ($parts as $part) {
            $p = strtolower(trim($part));
            if (preg_match('/^f\d+$/i', $p)) {
                $f_code = $p;
            } else if (preg_match('/^w[a-z0-9]*$/i', $p)) {
                $w_code = $p;
            }
        }

        if (!empty($f_code)) {
            // Map floor code to floor name
            if ($f_code === 'f00') $f_name = 'ground';
            else if ($f_code === 'f01') $f_name = 'first';
            else if ($f_code === 'f02') $f_name = 'second';
            else if ($f_code === 'f03') $f_name = 'third';
            else if ($f_code === 'f04') $f_name = 'fourth';
            else if ($f_code === 'f05') $f_name = 'fifth';
            else if ($f_code === 'f06') $f_name = 'sixth';
            else if ($f_code === 'f07') $f_name = 'seventh';
            else if ($f_code === 'f08') $f_name = 'eighth';
            else if ($f_code === 'f09') $f_name = 'ninth';
            else $f_name = $f_code;
            
            $w_name = $w_code;
        } else {
            // Fallback: parse from group_name
            $fg = strtolower($location['floor_group'] ?? '');
            if (strpos($fg, 'ground') !== false) $f_name = 'ground';
            else if (strpos($fg, 'first') !== false) $f_name = 'first';
            else if (strpos($fg, 'second') !== false) $f_name = 'second';
            else if (strpos($fg, 'third') !== false) $f_name = 'third';
            else if (strpos($fg, 'fourth') !== false) $f_name = 'fourth';
            else if (strpos($fg, 'fifth') !== false) $f_name = 'fifth';
            else if (strpos($fg, 'sixth') !== false) $f_name = 'sixth';
            else if (strpos($fg, 'seventh') !== false) $f_name = 'seventh';
            else if (strpos($fg, 'eighth') !== false) $f_name = 'eighth';
            else if (strpos($fg, 'ninth') !== false) $f_name = 'ninth';
        }

        $staff_query = "SELECT COALESCE(su.full_name, ms.name) as name, ms.role, COALESCE(su.phone_number, ms.phone) as phone, COALESCE(ms.staff_bio_id, ms.username) as username 
                       FROM mapping_staff ms
                       LEFT JOIN users su ON ms.staff_bio_id COLLATE utf8mb4_general_ci = su.username COLLATE utf8mb4_general_ci
                       WHERE (
                            LOWER(TRIM(ms.hostel_name)) COLLATE utf8mb4_general_ci = LOWER(TRIM(:h_name)) COLLATE utf8mb4_general_ci
                            OR LOWER(TRIM(ms.hostel_name)) COLLATE utf8mb4_general_ci LIKE CONCAT('%', LOWER(TRIM(:h_name)) COLLATE utf8mb4_general_ci, '%')
                            OR LOWER(TRIM(:h_name)) COLLATE utf8mb4_general_ci LIKE CONCAT('%', LOWER(TRIM(ms.hostel_name)) COLLATE utf8mb4_general_ci, '%')
                            OR ms.hostel_name IS NULL OR ms.hostel_name = ''
                       )
                       ORDER BY 
                            (CASE WHEN LOWER(TRIM(ms.floor_name)) COLLATE utf8mb4_general_ci LIKE CONCAT('%', LOWER(TRIM(:f_name)) COLLATE utf8mb4_general_ci, '%') THEN 5 ELSE 0 END) +
                            (CASE WHEN LOWER(TRIM(ms.hostel_name)) COLLATE utf8mb4_general_ci = LOWER(TRIM(:h_name)) COLLATE utf8mb4_general_ci THEN 1 ELSE 0 END) DESC";
        
        $stmt = $db->prepare($staff_query);
        $stmt->bindParam(':h_name', $h_name);
        $stmt->bindParam(':f_name', $f_name);
        $stmt->execute();
        
        $staff_list = $stmt->fetchAll(PDO::FETCH_ASSOC);

        foreach ($staff_list as $staff) {
            $roleRaw = strtolower(trim($staff['role']));
            $possibleKeys = [];
            if (strpos($roleRaw, 'warden') !== false) {
                $possibleKeys[] = 'warden';
            } else if (strpos($roleRaw, 'security') !== false) {
                $possibleKeys[] = 'security';
            } else if (strpos($roleRaw, 'maint') !== false) {
                $possibleKeys[] = 'maintenannce';
                $possibleKeys[] = 'maintenance';
            } else {
                $possibleKeys[] = $roleRaw;
            }

            foreach ($possibleKeys as $rKey) {
                if (!isset($result[$rKey]) || $result[$rKey] === null) {
                    $result[$rKey] = $staff;
                }
            }
        }
    }

    // ── FALLBACK GUARANTEE FOR ALLOCATED STUDENTS ──────────────────────
    if (!$is_unallocated) {
        // Fallback Warden
        if (empty($result['warden'])) {
            $result['warden'] = $warden1;
        }

        // Fallback Security
        if (empty($result['security'])) {
            $sec_stmt = $db->query("SELECT full_name as name, 'security' as role, phone_number as phone, username FROM users WHERE role = 'security' LIMIT 1");
            $sec_row = $sec_stmt ? $sec_stmt->fetch(PDO::FETCH_ASSOC) : null;
            if ($sec_row) {
                $result['security'] = $sec_row;
            } else {
                $result['security'] = ['name' => 'A Arjun', 'role' => 'security', 'phone' => 'N/A', 'username' => '14717'];
            }
        }

        // Fallback Maintenance
        if (empty($result['maintenance']) || empty($result['maintenannce'])) {
            $maint_stmt = $db->query("SELECT full_name as name, 'maintenance' as role, phone_number as phone, username FROM users WHERE role = 'maintenance' LIMIT 1");
            $maint_row = $maint_stmt ? $maint_stmt->fetch(PDO::FETCH_ASSOC) : null;
            if ($maint_row) {
                $result['maintenance'] = $maint_row;
                $result['maintenannce'] = $maint_row;
            } else {
                $m_fallback = ['name' => 'A Karthik', 'role' => 'maintenance', 'phone' => 'N/A', 'username' => '6329'];
                $result['maintenance'] = $m_fallback;
                $result['maintenannce'] = $m_fallback;
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