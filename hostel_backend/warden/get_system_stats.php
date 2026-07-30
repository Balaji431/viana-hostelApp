<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

$database = new Database();
$pdo = $database->getConnection();

$warden_username = isset($_GET['warden_username']) ? trim($_GET['warden_username']) : (isset($_GET['username']) ? trim($_GET['username']) : '');

try {
    if (!empty($warden_username) && strtolower($warden_username) !== 'admin') {
        // Filter stats by warden's assigned mapped locations in mapping_staff / rooms_groups_details
        $query = "
            SELECT 
                COUNT(DISTINCT rgd.id) as total_rooms, 
                COALESCE(SUM(rgd.total_beds), 0) as total_capacity, 
                COALESCE(SUM(rgd.occupied_beds), 0) as total_occupied, 
                COALESCE(SUM(rgd.available_beds), 0) as total_available 
            FROM rooms_groups_details rgd
            JOIN mapping_staff ms ON (
                TRIM(rgd.hostel_name) LIKE CONCAT('%', TRIM(ms.hostel_name), '%')
                AND LOWER(rgd.group_name) LIKE CONCAT('%', LOWER(ms.floor_name), '%')
            )
            WHERE ms.username = :warden_username OR ms.staff_bio_id = :warden_username2
               OR rgd.warden_user_id = :warden_username3
        ";
        $stmt = $pdo->prepare($query);
        $stmt->execute([
            ':warden_username' => $warden_username,
            ':warden_username2' => $warden_username,
            ':warden_username3' => $warden_username,
        ]);
        $room_res = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$room_res || intval($room_res['total_rooms']) == 0) {
            $queryFallback = "
                SELECT 
                    COUNT(DISTINCT rgd.id) as total_rooms, 
                    COALESCE(SUM(rgd.total_beds), 0) as total_capacity, 
                    COALESCE(SUM(rgd.occupied_beds), 0) as total_occupied, 
                    COALESCE(SUM(rgd.available_beds), 0) as total_available 
                FROM rooms_groups_details rgd
                JOIN users u ON (u.username = :warden_username OR u.biometric_id = :warden_username2)
                WHERE rgd.warden_user_id = u.biometric_id 
                   OR rgd.warden_name = u.full_name
                   OR rgd.warden_name LIKE CONCAT('%', u.full_name, '%')
            ";
            $stmtFB = $pdo->prepare($queryFallback);
            $stmtFB->execute([
                ':warden_username' => $warden_username,
                ':warden_username2' => $warden_username
            ]);
            $fbRes = $stmtFB->fetch(PDO::FETCH_ASSOC);
            if ($fbRes && intval($fbRes['total_rooms']) > 0) {
                $room_res = $fbRes;
            }
        }
    } else {
        // Global stats for Admin
        $query = "SELECT 
                    COUNT(*) as total_rooms, 
                    COALESCE(SUM(total_beds), 0) as total_capacity, 
                    COALESCE(SUM(occupied_beds), 0) as total_occupied, 
                    COALESCE(SUM(available_beds), 0) as total_available 
                  FROM rooms_groups_details";
        $stmt = $pdo->query($query);
        $room_res = $stmt->fetch(PDO::FETCH_ASSOC);
    }

    echo json_encode([
        'success' => true,
        'data' => [
            'total_rooms' => (int)($room_res['total_rooms'] ?? 0),
            'total_capacity' => (int)($room_res['total_capacity'] ?? 0),
            'total_occupied' => (int)($room_res['total_occupied'] ?? 0),
            'total_available' => (int)($room_res['total_available'] ?? 0),
        ]
    ]);

} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage()
    ]);
}
?>
