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
