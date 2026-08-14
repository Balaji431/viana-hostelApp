<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../../config/database.php';
require_once '../../utils/activity_logger.php';

$mappingId = $_GET['id'] ?? null;

if (!$mappingId) {
    echo json_encode(["success" => false, "message" => "Mapping ID required"]);
    exit();
}

try {
    // 1. Fetch mapped staff and location info before deleting
    $stmt_m = $pdo->prepare("
        SELECT m.hostel_id, m.zone_id, m.sub_zone_id, h.hostel_name
        FROM location_mappings m
        LEFT JOIN hostel_type h ON m.hostel_id = h.id
        WHERE m.id = ?
    ");
    $stmt_m->execute([$mappingId]);
    $mapping = $stmt_m->fetch(PDO::FETCH_ASSOC);

    $staff = [];
    if ($mapping) {
        $stmt_s = $pdo->prepare("SELECT username, name, role FROM mapping_staff WHERE mapping_id = ?");
        $stmt_s->execute([$mappingId]);
        $staff = $stmt_s->fetchAll(PDO::FETCH_ASSOC);
    }

    // ON DELETE CASCADE will handle mapping_staff
    $stmt = $pdo->prepare("DELETE FROM location_mappings WHERE id = ?");
    $stmt->execute([$mappingId]);

    // Log DELETE_STAFF_MAPPING audit event
    if ($mapping) {
        $hostel_name = $mapping['hostel_name'] ?? 'Unknown Hostel';
        $floor = $mapping['zone_id'] ?? 'All';
        $wing = $mapping['sub_zone_id'] ?? 'All';
        
        foreach ($staff as $s) {
            $uBio = trim($s['username'] ?? '');
            $sRole = strtolower(trim($s['role'] ?? ''));
            
            if (!empty($uBio) && (strpos($sRole, 'maint') !== false || strpos($sRole, 'secur') !== false)) {
                // Check if staff has any other remaining mappings in mapping_staff
                $checkRemaining = $pdo->prepare("SELECT COUNT(*) FROM mapping_staff WHERE (username = ? OR staff_bio_id = ?) AND mapping_id != ?");
                $checkRemaining->execute([$uBio, $uBio, $mappingId]);
                $remCount = $checkRemaining->fetchColumn();

                if ($remCount == 0) {
                    // Remove from users and profile tables if no active mapping_staff record remains
                    $pdo->prepare("DELETE FROM profile WHERE reg_no = ? OR user_id IN (SELECT id FROM users WHERE username = ?)")->execute([$uBio, $uBio]);
                    $pdo->prepare("DELETE FROM users WHERE username = ? AND role IN ('maintenance', 'security')")->execute([$uBio, $uBio]);
                    $pdo->prepare("DELETE FROM maintenance_users WHERE bio_id = ?")->execute([$uBio]);
                    $pdo->prepare("DELETE FROM security_users WHERE bio_id = ?")->execute([$uBio]);
                }
            }

            logAudit(
                null,
                $s['username'],
                strtolower($s['role']),
                'DELETE_STAFF_MAPPING',
                'Staff Mappings',
                [
                    'hostel_name' => $hostel_name,
                    'floor' => $floor,
                    'wing' => $wing,
                    'staff_name' => $s['name']
                ],
                null
            );
        }
    }

    echo json_encode(["success" => true]);

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
}
?>
