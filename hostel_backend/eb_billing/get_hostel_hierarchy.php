<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json; charset=UTF-8");

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $action = isset($_GET['action']) ? trim($_GET['action']) : 'tree';
    $hostelName = isset($_GET['hostel_name']) ? trim($_GET['hostel_name']) : '';
    $floorName = isset($_GET['floor_name']) ? trim($_GET['floor_name']) : '';
    $staff_username = isset($_GET['staff_username']) ? trim($_GET['staff_username']) : (isset($_GET['warden_username']) ? trim($_GET['warden_username']) : '');
    $role = isset($_GET['role']) ? strtolower(trim($_GET['role'])) : '';

    $is_restricted = false;
    $assigned_pairs = [];
    $assigned_hostels = [];
    $assigned_floors = [];

    if (!empty($staff_username) && !in_array($role, ['admin', 'superadmin', 'super_admin'])) {
        $mStmt = $db->prepare("
            SELECT DISTINCT rgd.hostel_name, rgd.group_name
            FROM rooms_groups_details rgd
            JOIN mapping_staff ms ON (TRIM(ms.username) = ? OR TRIM(ms.staff_bio_id) = ?)
            WHERE (
                LOWER(TRIM(ms.hostel_name)) = LOWER(TRIM(rgd.hostel_name))
                OR LOWER(TRIM(rgd.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(ms.hostel_name)), '%')
                OR LOWER(TRIM(ms.hostel_name)) LIKE CONCAT('%', LOWER(TRIM(rgd.hostel_name)), '%')
            )
            AND (
                LOWER(TRIM(ms.floor_name)) = 'all'
                OR ms.floor_name IS NULL
                OR ms.floor_name = ''
                OR LOWER(TRIM(ms.floor_name)) = LOWER(TRIM(rgd.group_name))
                OR LOWER(TRIM(rgd.group_name)) LIKE CONCAT('%', LOWER(TRIM(ms.floor_name)), '%')
                OR LOWER(TRIM(ms.floor_name)) LIKE CONCAT('%', LOWER(TRIM(rgd.group_name)), '%')
            )
            AND rgd.hostel_name IS NOT NULL AND rgd.hostel_name != ''
            AND rgd.group_name IS NOT NULL AND rgd.group_name != ''
        ");
        $mStmt->execute([$staff_username, $staff_username]);
        $pairs = $mStmt->fetchAll(PDO::FETCH_ASSOC);

        if (!empty($pairs)) {
            $is_restricted = true;
            $assigned_pairs = $pairs;
            foreach ($pairs as $p) {
                $assigned_hostels[] = trim($p['hostel_name']);
                $assigned_floors[] = trim($p['group_name']);
            }
            $assigned_hostels = array_values(array_unique($assigned_hostels));
            $assigned_floors = array_values(array_unique($assigned_floors));
        }
    }

    if ($action === 'hostels') {
        if ($is_restricted && !empty($assigned_hostels)) {
            echo json_encode(["status" => "success", "data" => $assigned_hostels]);
            exit();
        }
        $stmt = $db->query("
            SELECT DISTINCT hostel_name 
            FROM rooms_groups_details 
            WHERE hostel_name IS NOT NULL AND hostel_name != ''
            ORDER BY hostel_name ASC
        ");
        $hostels = $stmt->fetchAll(PDO::FETCH_COLUMN);
        echo json_encode(["status" => "success", "data" => $hostels]);
        exit();
    }

    if ($action === 'floors') {
        if ($is_restricted && !empty($hostelName)) {
            $matchedFloors = [];
            foreach ($assigned_pairs as $p) {
                if (strcasecmp($p['hostel_name'], $hostelName) === 0) {
                    $matchedFloors[] = $p['group_name'];
                }
            }
            if (!empty($matchedFloors)) {
                echo json_encode(["status" => "success", "data" => array_values(array_unique($matchedFloors))]);
                exit();
            }
        }
        $stmt = $db->prepare("
            SELECT DISTINCT group_name as floor_name 
            FROM rooms_groups_details 
            WHERE hostel_name = ? AND group_name IS NOT NULL AND group_name != ''
            ORDER BY group_name ASC
        ");
        $stmt->execute([$hostelName]);
        $floors = $stmt->fetchAll(PDO::FETCH_COLUMN);
        echo json_encode(["status" => "success", "data" => $floors]);
        exit();
    }

    if ($action === 'rooms') {
        $stmt = $db->prepare("
            SELECT DISTINCT room_number 
            FROM rooms_groups_details 
            WHERE hostel_name = ? AND (group_name = ? OR LOWER(group_name) LIKE ? OR LOWER(?) LIKE CONCAT('%', LOWER(group_name), '%')) AND room_number IS NOT NULL AND room_number != ''
            ORDER BY room_number ASC
        ");
        $stmt->execute([$hostelName, $floorName, '%' . strtolower($floorName) . '%', $floorName]);
        $rooms = $stmt->fetchAll(PDO::FETCH_COLUMN);
        echo json_encode(["status" => "success", "data" => $rooms]);
        exit();
    }

    // Default: Return full tree for instant cascading
    $where = ["hostel_name IS NOT NULL AND hostel_name != '' AND room_number IS NOT NULL AND room_number != ''"];
    $params = [];
    if ($is_restricted && !empty($assigned_pairs)) {
        $pairClauses = [];
        foreach ($assigned_pairs as $p) {
            $pairClauses[] = "(hostel_name = ? AND group_name = ?)";
            $params[] = $p['hostel_name'];
            $params[] = $p['group_name'];
        }
        if (!empty($pairClauses)) {
            $where[] = "(" . implode(" OR ", $pairClauses) . ")";
        }
    }
    $whereSQL = implode(' AND ', $where);
    $stmt = $db->prepare("
        SELECT hostel_name, group_name as floor_name, room_number 
        FROM rooms_groups_details 
        WHERE $whereSQL
        ORDER BY hostel_name ASC, group_name ASC, room_number ASC
    ");
    $stmt->execute($params);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $tree = [];
    foreach ($rows as $r) {
        $h = trim($r['hostel_name']);
        $f = trim($r['floor_name'] ?? '');
        $rm = trim($r['room_number'] ?? '');
        if (empty($h) || empty($rm)) continue;
        if (empty($f)) $f = "Ground Floor";

        if (!isset($tree[$h])) {
            $tree[$h] = [];
        }
        if (!isset($tree[$h][$f])) {
            $tree[$h][$f] = [];
        }
        $tree[$h][$f][] = $rm;
    }

    echo json_encode([
        "status" => "success",
        "data" => $tree
    ]);
} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "message" => $e->getMessage()
    ]);
}
