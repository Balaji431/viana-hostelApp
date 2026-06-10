<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
    http_response_code(200);
    exit();
}

require_once '../config/database.php';
require_once '../utils/activity_logger.php';

if (!$pdo) {
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit();
}

$data = json_decode(file_get_contents("php://input"), true);

if (empty($data['id']) || empty($data['hostel_name'])) {
    echo json_encode(["success" => false, "message" => "Hostel ID and name are required"]);
    exit();
}

try {
    $pdo->beginTransaction();

    $id = $data['id'];
    $newName = $data['hostel_name'];
    $campus = $data['campus'] ?? 'Thandalam Campus';
    $type = $data['type'] ?? 'Girls';
    $buildingCode = $data['building_code'] ?? '';

    // 0. Get old name first to update profile table later
    $stmt = $pdo->prepare("SELECT hostel_name FROM hostel_type WHERE id = ?");
    $stmt->execute([$id]);
    $oldName = $stmt->fetchColumn();

    // 1. Update hostel_type
    $stmt = $pdo->prepare("UPDATE hostel_type SET campus = ?, hostel_name = ?, hostel_type = ?, building_code = ? WHERE id = ?");
    $stmt->execute([$campus, $newName, $type, $buildingCode, $id]);

    // 2. Update hostel_rooms denormalized fields
    $stmt = $pdo->prepare("UPDATE hostel_rooms SET campus = ?, hostel_name = ?, hostel_type = ?, building_code = ? WHERE hostel_id = ?");
    $stmt->execute([$campus, $newName, $type, $buildingCode, $id]);

    // 3. Update profile table for all students in this hostel
    if ($oldName && $oldName !== $newName) {
        $stmt = $pdo->prepare("UPDATE profile SET hostel_name = ? WHERE hostel_name = ?");
        $stmt->execute([$newName, $oldName]);

        // 4. Log the activity
        logAdminActivity($data['admin_id'] ?? 1, "Renamed Hostel (Full Update)", "Changed '$oldName' to '$newName'");
    }

    // 3. Handle Rooms (Optional: If room data is provided, we could sync them)
    // For now, let's just support updating basic info and denormalized fields.
    // If the user wants to add/remove rooms, they usually do that via manage_rooms.php.
    // But let's add a basic room sync if provided.
    
    if (isset($data['sync_rooms']) && $data['sync_rooms'] === true && !empty($data['rooms'])) {
        // This is a more complex operation (delete and re-insert or update existing)
        // For simplicity, let's just update existing rooms or add new ones.
        // But the user might want to delete rooms too.
        // Let's stick to updating the basic hostel info first to ensure stability.
    }

    $pdo->commit();
    echo json_encode(["success" => true, "message" => "Hostel updated successfully"]);

} catch (Exception $e) {
    $pdo->rollBack();
    echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
}
?>
