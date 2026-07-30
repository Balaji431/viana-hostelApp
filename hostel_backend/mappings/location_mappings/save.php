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

    // Bypass strict single-warden assignment restrictions as requested
    foreach ($data['staff'] as $staff) {
        $username = $staff['username'] ?? '';
        $hostel_name = $staff['hostel_name'] ?? '';
        
        if (!empty($username)) {
            // Validate hostel is one of the hostels registered in hostel_type table
            if (!empty($hostel_name)) {
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
            }
        }
    }

    // Insert new staff members with location details
    $stmt = $pdo->prepare("INSERT INTO mapping_staff (mapping_id, name, role, phone, username, staff_bio_id, hostel_name, floor_name, wing_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
    
    $userUpsert = $pdo->prepare("
        INSERT INTO users (username, full_name, phone_number, role, password, HostelName, Status, is_active, Institution)
        VALUES (:username, :name, :phone, :role, :pw, :hostel, '1', 1, 'SIMATS')
        ON DUPLICATE KEY UPDATE
            full_name = VALUES(full_name),
            phone_number = VALUES(phone_number),
            role = VALUES(role),
            HostelName = VALUES(HostelName),
            Status = '1',
            is_active = 1
    ");

    $staffUserUpsert = $pdo->prepare("
        INSERT INTO staff_users (bio_id, password, name, phone, role)
        VALUES (:bio_id, :pw, :name, :phone, :role)
        ON DUPLICATE KEY UPDATE
            name = VALUES(name),
            phone = VALUES(phone),
            role = VALUES(role)
    ");

    $pwHash = password_hash('welcome123', PASSWORD_BCRYPT);

    foreach ($data['staff'] as $staff) {
        $uBioId = trim($staff['username'] ?? '');
        $stmt->execute([
            $mappingId, 
            $staff['name'], 
            $staff['role'], 
            $staff['phone'], 
            $uBioId,
            $uBioId, // save bio_id into staff_bio_id as well
            $staff['hostel_name'] ?? '',
            $staff['floor_name'] ?? '',
            $staff['wing_name'] ?? ''
        ]);

        if (!empty($uBioId)) {
            $sRole = strtolower(trim($staff['role'] ?? 'staff'));
            if (strpos($sRole, 'maint') !== false) {
                $sRole = 'maintenance';
            }
            $sName = trim($staff['name'] ?? 'Staff');
            $sPhone = trim($staff['phone'] ?? '');
            $sHostel = trim($staff['hostel_name'] ?? '');

            $userUpsert->execute([
                ':username' => $uBioId,
                ':name'     => $sName,
                ':phone'    => $sPhone,
                ':role'     => $sRole,
                ':pw'       => $pwHash,
                ':hostel'   => $sHostel
            ]);

            $staffUserUpsert->execute([
                ':bio_id' => $uBioId,
                ':pw'     => $pwHash,
                ':name'   => $sName,
                ':phone'  => $sPhone,
                ':role'   => $sRole
            ]);
        }
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
