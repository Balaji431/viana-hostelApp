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

    // 1. Get student's profile warden and location details
    $query = "SELECT p.warden as profile_warden, 
                     COALESCE(rgd.hostel_name, p.hostel_name, u.HostelName) as hostel_name, 
                     rgd.group_name as floor_group, 
                     COALESCE(NULLIF(p.room_allocation,''), u.RoomId) as room_allocation, 
                     rgd.warden_name as rgd_warden
              FROM users u
              LEFT JOIN profile p ON TRIM(u.username) = TRIM(p.reg_no)
              LEFT JOIN rooms_groups_details rgd ON (
                  rgd.room_number = COALESCE(NULLIF(p.room_allocation,''), u.RoomId)
                  OR REPLACE(REPLACE(TRIM(rgd.room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(COALESCE(NULLIF(p.room_allocation,''), u.RoomId)), ' ', ''), '-', '')
              )
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

    if (!$is_unallocated) {
        $target_warden_name = trim($location['profile_warden'] ?? $location['rgd_warden'] ?? '');

        // 1. Direct Warden Lookup from Profile / RGD Warden Name
        if (!empty($target_warden_name)) {
            $w_stmt = $db->prepare("
                SELECT COALESCE(su.full_name, ms.name) as name, 'Warden' as role, COALESCE(su.phone_number, ms.phone) as phone, COALESCE(ms.staff_bio_id, ms.username) as username 
                FROM mapping_staff ms
                LEFT JOIN users su ON (CONVERT(ms.staff_bio_id USING utf8mb4) = CONVERT(su.username USING utf8mb4) OR CONVERT(ms.username USING utf8mb4) = CONVERT(su.username USING utf8mb4))
                WHERE (LOWER(TRIM(ms.name)) = LOWER(TRIM(:w_name)) OR LOWER(TRIM(su.full_name)) = LOWER(TRIM(:w_name)))
                  AND LOWER(ms.role) LIKE '%warden%'
                LIMIT 1
            ");
            $w_stmt->bindParam(':w_name', $target_warden_name);
            $w_stmt->execute();
            $matched_warden = $w_stmt->fetch(PDO::FETCH_ASSOC);

            if (!$matched_warden) {
                // Fallback: check users table directly for warden
                $u_stmt = $db->prepare("SELECT full_name as name, 'Warden' as role, phone_number as phone, username FROM users WHERE LOWER(TRIM(full_name)) = LOWER(TRIM(?)) LIMIT 1");
                $u_stmt->execute([$target_warden_name]);
                $matched_warden = $u_stmt->fetch(PDO::FETCH_ASSOC);
            }

            if ($matched_warden) {
                $result['warden'] = $matched_warden;
            } else {
                $result['warden'] = [
                    'name' => $target_warden_name,
                    'role' => 'Warden',
                    'phone' => 'N/A',
                    'username' => 'warden'
                ];
            }
        }

        // 2. Fetch Security, Maintenance & Other Staff by Group Name / Hostel Name
        $group_name = trim($location['floor_group'] ?? '');
        $h_name = trim($location['hostel_name'] ?? '');

        $staff_query = "
            SELECT COALESCE(su.full_name, ms.name) as name, ms.role, COALESCE(su.phone_number, ms.phone) as phone, COALESCE(ms.staff_bio_id, ms.username) as username 
            FROM mapping_staff ms
            LEFT JOIN users su ON (CONVERT(ms.staff_bio_id USING utf8mb4) = CONVERT(su.username USING utf8mb4) OR CONVERT(ms.username USING utf8mb4) = CONVERT(su.username USING utf8mb4))
            WHERE (
                 LOWER(TRIM(ms.floor_name)) = LOWER(TRIM(:group_name))
                 OR LOWER(TRIM(:group_name)) LIKE CONCAT('%', LOWER(TRIM(ms.floor_name)), '%')
                 OR LOWER(TRIM(ms.hostel_name)) = LOWER(TRIM(:h_name))
                 OR LOWER(TRIM(ms.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(:h_name)), '%')
                 OR LOWER(TRIM(:h_name)) LIKE CONCAT('%', LOWER(TRIM(ms.hostel_name)), '%')
                 OR ms.hostel_name IS NULL OR ms.hostel_name = ''
            )
            ORDER BY 
                 (CASE WHEN LOWER(TRIM(ms.floor_name)) = LOWER(TRIM(:group_name)) THEN 100 ELSE 0 END) +
                 (CASE WHEN LOWER(TRIM(ms.hostel_name)) = LOWER(TRIM(:h_name)) THEN 10 ELSE 0 END) DESC
        ";
        $stmt = $db->prepare($staff_query);
        $stmt->bindParam(':group_name', $group_name);
        $stmt->bindParam(':h_name', $h_name);
        $stmt->execute();
        $staff_list = $stmt->fetchAll(PDO::FETCH_ASSOC);

        foreach ($staff_list as $staff) {
            $roleRaw = strtolower(trim($staff['role']));
            if (strpos($roleRaw, 'security') !== false) {
                if (empty($result['security'])) $result['security'] = $staff;
            } else if (strpos($roleRaw, 'maint') !== false) {
                if (empty($result['maintenance'])) $result['maintenance'] = $staff;
                if (empty($result['maintenannce'])) $result['maintenannce'] = $staff;
            } else if (strpos($roleRaw, 'warden') !== false) {
                if (empty($result['warden'])) $result['warden'] = $staff;
            }
        }
    }

    echo json_encode([
        'success' => true,
        'group_name' => $location['floor_group'] ?? '',
        'room_number' => $location['room_allocation'] ?? '',
        'data' => $result
    ]);

} catch (Exception $e) {
    echo json_encode(['success' => false, 'message' => 'Server error: ' . $e->getMessage()]);
}
?>