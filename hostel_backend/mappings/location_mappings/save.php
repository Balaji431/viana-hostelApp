<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../utils/activity_logger.php';
global $pdo;

if (isset($GLOBALS['mock_input_save'])) {
    $data = $GLOBALS['mock_input_save'];
} else {
    $data = json_decode(file_get_contents("php://input"), true);
}

if (!isset($data['hostel_id']) || !isset($data['staff'])) {
    echo json_encode(["success" => false, "message" => "Missing required fields"]);
    return;
}

try {
    $pdo->beginTransaction();
    
    $mappingId = $data['id'] ?? null;
    $hostelId = $data['hostel_id'];
    $zoneId = !empty($data['zone_id']) ? $data['zone_id'] : null;
    $subZoneId = !empty($data['sub_zone_id']) ? $data['sub_zone_id'] : null;
    
    if ($mappingId) {
        // Update existing mapping location
        $stmt = $pdo->prepare("UPDATE location_mappings SET hostel_id = ?, zone_id = ?, sub_zone_id = ? WHERE id = ?");
        $stmt->execute([$hostelId, $zoneId, $subZoneId, $mappingId]);
        
        // Clear old staff
        $stmt = $pdo->prepare("DELETE FROM mapping_staff WHERE mapping_id = ?");
        $stmt->execute([$mappingId]);
    } else {
        // Create new mapping location
        $stmt = $pdo->prepare("INSERT INTO location_mappings (hostel_id, zone_id, sub_zone_id) VALUES (?, ?, ?)");
        $stmt->execute([$hostelId, $zoneId, $subZoneId]);
        $mappingId = $pdo->lastInsertId();
    }
    
    if (!function_exists('isHostelNameMatch')) {
        function isHostelNameMatch($h1, $h2) {
            if (empty($h1) || empty($h2)) return false;
            $n1 = strtolower(preg_replace('/\s*hostel\s*/i', '', trim($h1)));
            $n2 = strtolower(preg_replace('/\s*hostel\s*/i', '', trim($h2)));
            return ($n1 === $n2) || (strpos($n1, $n2) !== false) || (strpos($n2, $n1) !== false);
        }
    }

    // 1. Verify no multiple wardens for the same area in the payload itself
    $seen_areas = [];
    foreach ($data['staff'] as $staff) {
        $username = $staff['username'] ?? '';
        $role = $staff['role'] ?? '';
        $hostel_name = $staff['hostel_name'] ?? '';
        $floor_name = $staff['floor_name'] ?? '';
        $wing_name = $staff['wing_name'] ?? '';
        
        if (strtolower($role) === 'warden') {
            $key = strtolower(trim($hostel_name)) . '|' . strtolower(trim($floor_name)) . '|' . strtolower(trim($wing_name));
            if (isset($seen_areas[$key])) {
                if ($seen_areas[$key] !== $username) {
                    $first_warden_name = "";
                    foreach ($data['staff'] as $s2) {
                        if (($s2['username'] ?? '') === $seen_areas[$key]) {
                            $first_warden_name = $s2['name'] ?? '';
                            break;
                        }
                    }
                    http_response_code(409);
                    echo json_encode([
                        "success" => false,
                        "message" => "This area already has a warden assigned: $first_warden_name (@{$seen_areas[$key]}). Please edit or remove the existing mapping before assigning another warden."
                    ]);
                    if ($pdo->inTransaction()) $pdo->rollBack();
                    return;
                }
            } else {
                $seen_areas[$key] = $username;
            }
        }
    }

    // 2. Backend Validation Checks prior to staff mapping updates
    foreach ($data['staff'] as $staff) {
        $username = $staff['username'] ?? '';
        $role = $staff['role'] ?? '';
        $hostel_name = $staff['hostel_name'] ?? '';
        $floor_name = $staff['floor_name'] ?? '';
        $wing_name = $staff['wing_name'] ?? '';
        
        if (strtolower($role) === 'warden') {
            // A. Verify user exists in users table and users.role = 'warden'
            $user_chk = $pdo->prepare("SELECT role FROM users WHERE username = ? LIMIT 1");
            $user_chk->execute([$username]);
            $u_row = $user_chk->fetch(PDO::FETCH_ASSOC);
            if (!$u_row) {
                echo json_encode(["success" => false, "message" => "Warden user '$username' does not exist in the users table."]);
                if ($pdo->inTransaction()) $pdo->rollBack();
                return;
            }
            if (strtolower($u_row['role']) !== 'warden') {
                echo json_encode(["success" => false, "message" => "User '$username' does not have the warden role."]);
                if ($pdo->inTransaction()) $pdo->rollBack();
                return;
            }
            
            // B. Validate hostel is one of the hostels registered in hostel_type table
            $hostel_stmt = $pdo->query("SELECT DISTINCT hostel_name FROM hostel_type");
            $valid_hostels = $hostel_stmt->fetchAll(PDO::FETCH_COLUMN);
            $is_valid_hostel = false;
            foreach ($valid_hostels as $vh) {
                if (isHostelNameMatch($vh, $hostel_name)) {
                    $is_valid_hostel = true;
                    break;
                }
            }
            if (!$is_valid_hostel) {
                $allowed_hostels = implode(', ', $valid_hostels);
                echo json_encode(["success" => false, "message" => "Selected hostel '$hostel_name' is invalid. Valid hostels: $allowed_hostels."]);
                if ($pdo->inTransaction()) $pdo->rollBack();
                return;
            }
            
            // C. Block duplicate mapping for username + hostel_name + floor_name + wing_name (same warden, same area)
            $dup_chk = $pdo->prepare("
                SELECT id FROM mapping_staff 
                WHERE username = ? AND hostel_name = ? AND floor_name = ? AND wing_name = ? AND mapping_id != ?
            ");
            $dup_chk->execute([$username, $hostel_name, $floor_name, $wing_name, $mappingId]);
            if ($dup_chk->fetch()) {
                echo json_encode(["success" => false, "message" => "A mapping already exists for '$username' in '$hostel_name' floor '$floor_name' wing '$wing_name'."]);
                if ($pdo->inTransaction()) $pdo->rollBack();
                return;
            }

            // D. Area assignment validation: only ONE active warden allowed per hostel_name + floor_name + wing_name
            $area_stmt = $pdo->prepare("
                SELECT username, name, hostel_name, floor_name, wing_name FROM mapping_staff 
                WHERE (LOWER(role) = 'warden') AND mapping_id != ?
            ");
            $area_stmt->execute([$mappingId]);
            
            $n_hostel_in = strtolower(trim($hostel_name));
            $n_floor_in = strtolower(trim($floor_name));
            $n_wing_in = strtolower(trim($wing_name));
            
            while ($row = $area_stmt->fetch(PDO::FETCH_ASSOC)) {
                $n_hostel_db = strtolower(trim($row['hostel_name']));
                $n_floor_db = strtolower(trim($row['floor_name']));
                $n_wing_db = strtolower(trim($row['wing_name']));
                
                if ($n_hostel_db === $n_hostel_in && $n_floor_db === $n_floor_in && $n_wing_db === $n_wing_in) {
                    if ($row['username'] !== $username) {
                        http_response_code(409); // Conflict
                        echo json_encode([
                            "success" => false,
                            "message" => "This area already has a warden assigned: {$row['name']} (@{$row['username']}). Please edit or remove the existing mapping before assigning another warden."
                        ]);
                        if ($pdo->inTransaction()) $pdo->rollBack();
                        return;
                    }
                }
            }
        }
    }

    // Insert new staff members with location details
    $stmt = $pdo->prepare("INSERT INTO mapping_staff (mapping_id, name, role, phone, username, hostel_name, floor_name, wing_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
    foreach ($data['staff'] as $staff) {
        $stmt->execute([
            $mappingId, 
            $staff['name'], 
            $staff['role'], 
            $staff['phone'], 
            $staff['username'] ?? '',
            $staff['hostel_name'] ?? '',
            $staff['floor_name'] ?? '',
            $staff['wing_name'] ?? ''
        ]);
    }
    
    $actionType = isset($data['id']) && $data['id'] ? "UPDATE_STAFF_MAPPING" : "CREATE_STAFF_MAPPING";
    logAudit(null, null, null, $actionType, "Staff Mappings", null, $data);

    $pdo->commit();
    echo json_encode(["status" => "success", "id" => $mappingId]);

} catch (Exception $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
}
?>
