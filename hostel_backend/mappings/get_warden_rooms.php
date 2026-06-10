<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

require_once '../config/database.php';

$username = $_GET['username'] ?? null;

if (!$username) {
    echo json_encode(["success" => false, "message" => "Username is required"]);
    exit();
}

try {
    // 1. Get warden's mappings from mapping_staff
    $stmt = $pdo->prepare("SELECT hostel_name, floor_name, wing_name FROM mapping_staff WHERE username = ? AND role = 'Warden'");
    $stmt->execute([$username]);
    $mappings = $stmt->fetchAll(PDO::FETCH_ASSOC);

    if (empty($mappings)) {
        echo json_encode(["success" => false, "message" => "No mappings found for warden: $username"]);
        exit();
    }

    $all_rooms = [];
    foreach ($mappings as $map) {
        $h_name = $map['hostel_name'];
        $f_name = $map['floor_name'];
        $w_name = $map['wing_name'];

        // 2. Query rooms matching this specific mapping
        // We handle hierarchy: Wing > Floor > Hostel
        $query = "SELECT room_code, room_no, floor, wing_code, hostel_name 
                  FROM hostel_rooms 
                  WHERE 1=1";
        
        $params = [];
        if (!empty($h_name)) {
            $query .= " AND hostel_name = ?";
            $params[] = $h_name;
        }
        if (!empty($f_name)) {
            $query .= " AND floor = ?";
            $params[] = $f_name;
        }
        if (!empty($w_name)) {
            $query .= " AND wing_code = ?";
            $params[] = $w_name;
        }

        $roomStmt = $pdo->prepare($query);
        $roomStmt->execute($params);
        $rooms = $roomStmt->fetchAll(PDO::FETCH_ASSOC);
        
        $all_rooms = array_merge($all_rooms, $rooms);
    }

    // Remove duplicates if any (though mappings should be distinct)
    $unique_rooms = array_map("unserialize", array_unique(array_map("serialize", $all_rooms)));

    echo json_encode([
        "success" => true,
        "warden" => $username,
        "mapping_count" => count($mappings),
        "total_rooms" => count($unique_rooms),
        "rooms" => array_values($unique_rooms)
    ]);

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
}
?>
