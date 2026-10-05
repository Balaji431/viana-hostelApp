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
require_once __DIR__ . '/../utils/auth_helper.php';

$authUser = requireAuth(['admin', 'super_admin', 'warden', 'maintenance', 'it']);

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $query = isset($_GET['query']) ? trim($_GET['query']) : '';
    $status = isset($_GET['status']) ? trim($_GET['status']) : 'all'; // all, verified, not_verified
    $hostel = isset($_GET['hostel']) ? trim($_GET['hostel']) : 'All';
    $floor = isset($_GET['floor']) ? trim($_GET['floor']) : 'All';
    $from_date = isset($_GET['from_date']) ? trim($_GET['from_date']) : '';
    if (!empty($from_date) && !preg_match('/^\d{4}-\d{2}-\d{2}$/', $from_date)) {
        $from_date = '';
    }
    $to_date = isset($_GET['to_date']) ? trim($_GET['to_date']) : '';
    if (!empty($to_date) && !preg_match('/^\d{4}-\d{2}-\d{2}$/', $to_date)) {
        $to_date = '';
    }
    // Backward compatibility for single date param
    if (empty($from_date) && empty($to_date) && !empty($_GET['date'])) {
        $single_date = trim($_GET['date']);
        if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $single_date)) {
            $from_date = $single_date;
            $to_date = $single_date;
        }
    }
    $staff_username = isset($_GET['staff_username']) ? trim($_GET['staff_username']) : (isset($_GET['warden_username']) ? trim($_GET['warden_username']) : '');
    $role = isset($_GET['role']) ? strtolower(trim($_GET['role'])) : '';
    $page = isset($_GET['page']) ? max(1, (int)$_GET['page']) : 1;
    $limit = isset($_GET['limit']) ? max(1, (int)$_GET['limit']) : 25;
    $offset = ($page - 1) * $limit;

    // Check staff mappings for maintenance/security/warden
    $is_restricted_staff = false;
    $assigned_pairs = [];
    $assigned_hostels = [];
    $assigned_floors = [];

    if (!empty($staff_username) && !in_array($role, ['admin', 'superadmin', 'super_admin'])) {
        $mapStmt = $db->prepare("
            SELECT DISTINCT rgd.hostel_name, rgd.group_name, ms.floor_name as mapped_floor
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
        $mapStmt->execute([$staff_username, $staff_username]);
        $pairs = $mapStmt->fetchAll(PDO::FETCH_ASSOC);

        if (!empty($pairs)) {
            $is_restricted_staff = true;
            $assigned_pairs = $pairs;
            foreach ($pairs as $p) {
                $assigned_hostels[] = trim($p['hostel_name']);
                $assigned_floors[] = trim($p['group_name']);
            }
            $assigned_hostels = array_values(array_unique($assigned_hostels));
            $assigned_floors = array_values(array_unique($assigned_floors));
        }
    }

    // Available Hostels for Filter
    if ($is_restricted_staff && !empty($assigned_hostels)) {
        $availableHostels = $assigned_hostels;
    } else {
        $hostelStmt = $db->query("
            SELECT DISTINCT hostel_name 
            FROM rooms_groups_details 
            WHERE hostel_name IS NOT NULL AND hostel_name != '' 
            ORDER BY hostel_name ASC
        ");
        $availableHostels = $hostelStmt->fetchAll(PDO::FETCH_COLUMN);
    }

    // Available Floors for Filter
    $availableFloors = [];
    if ($is_restricted_staff) {
        if (!empty($hostel) && strtolower($hostel) !== 'all') {
            $matchedFloors = [];
            foreach ($assigned_pairs as $p) {
                if (strcasecmp(trim($p['hostel_name']), $hostel) === 0 && !empty($p['group_name'])) {
                    $matchedFloors[] = trim($p['group_name']);
                }
            }
            $availableFloors = !empty($matchedFloors) ? array_values(array_unique($matchedFloors)) : $assigned_floors;
        } else {
            $availableFloors = $assigned_floors;
        }
    } else {
        if (!empty($hostel) && strtolower($hostel) !== 'all') {
            $flrStmt = $db->prepare("
                SELECT DISTINCT group_name 
                FROM rooms_groups_details 
                WHERE hostel_name = ? AND group_name IS NOT NULL AND group_name != '' 
                ORDER BY group_name ASC
            ");
            $flrStmt->execute([$hostel]);
            $availableFloors = $flrStmt->fetchAll(PDO::FETCH_COLUMN);
        } else {
            $flrStmt = $db->query("
                SELECT DISTINCT group_name 
                FROM rooms_groups_details 
                WHERE group_name IS NOT NULL AND group_name != '' 
                ORDER BY group_name ASC
            ");
            $availableFloors = $flrStmt->fetchAll(PDO::FETCH_COLUMN);
        }
    }

    // Build WHERE clause
    $where = ["rgd.hostel_name IS NOT NULL AND rgd.hostel_name != ''"];
    $params = [];

    if (!empty($hostel) && strtolower($hostel) !== 'all') {
        $where[] = "rgd.hostel_name = ?";
        $params[] = $hostel;

        if (!empty($floor) && strtolower($floor) !== 'all') {
            $where[] = "(rgd.group_name = ? OR LOWER(rgd.group_name) LIKE ? OR LOWER(?) LIKE CONCAT('%', LOWER(rgd.group_name), '%'))";
            $params[] = $floor;
            $params[] = '%' . strtolower($floor) . '%';
            $params[] = $floor;
        } elseif ($is_restricted_staff) {
            $hostelFloors = [];
            foreach ($assigned_pairs as $p) {
                if (strcasecmp(trim($p['hostel_name']), $hostel) === 0 && !empty($p['group_name'])) {
                    $hostelFloors[] = trim($p['group_name']);
                }
            }
            $hostelFloors = array_values(array_unique($hostelFloors));
            if (!empty($hostelFloors)) {
                $fPlaceholders = implode(',', array_fill(0, count($hostelFloors), '?'));
                $where[] = "rgd.group_name IN ($fPlaceholders)";
                foreach ($hostelFloors as $hf) {
                    $params[] = $hf;
                }
            }
        }
    } elseif ($is_restricted_staff && !empty($assigned_pairs)) {
        if (!empty($floor) && strtolower($floor) !== 'all') {
            $where[] = "(rgd.group_name = ? OR LOWER(rgd.group_name) LIKE ? OR LOWER(?) LIKE CONCAT('%', LOWER(rgd.group_name), '%'))";
            $params[] = $floor;
            $params[] = '%' . strtolower($floor) . '%';
            $params[] = $floor;
        } else {
            $pairClauses = [];
            foreach ($assigned_pairs as $p) {
                $pairClauses[] = "(rgd.hostel_name = ? AND rgd.group_name = ?)";
                $params[] = $p['hostel_name'];
                $params[] = $p['group_name'];
            }
            if (!empty($pairClauses)) {
                $where[] = "(" . implode(" OR ", $pairClauses) . ")";
            }
        }
    } elseif (!empty($floor) && strtolower($floor) !== 'all') {
        $where[] = "(rgd.group_name = ? OR LOWER(rgd.group_name) LIKE ?)";
        $params[] = $floor;
        $params[] = '%' . strtolower($floor) . '%';
    }

    if (!empty($query)) {
        $where[] = "rgd.room_number LIKE ?";
        $params[] = "%$query%";
    }

    if ($status === 'verified') {
        $where[] = "emr.id IS NOT NULL";
    } elseif ($status === 'not_verified') {
        $where[] = "emr.id IS NULL";
    }

    $whereSQL = implode(" AND ", $where);

    if (!empty($from_date) && !empty($to_date)) {
        $dateFilter = "WHERE DATE(created_at) >= " . $db->quote($from_date) . " AND DATE(created_at) <= " . $db->quote($to_date);
    } elseif (!empty($from_date)) {
        $dateFilter = "WHERE DATE(created_at) >= " . $db->quote($from_date);
    } elseif (!empty($to_date)) {
        $dateFilter = "WHERE DATE(created_at) <= " . $db->quote($to_date);
    } else {
        $dateFilter = "";
    }

    // Count query
    $countSql = "
        SELECT 
            COUNT(*) as total,
            COUNT(CASE WHEN emr.id IS NOT NULL THEN 1 END) as total_verified,
            COUNT(CASE WHEN emr.id IS NULL THEN 1 END) as total_not_verified
        FROM (
            SELECT MIN(s_no) as s_no, hostel_name, group_name, room_number
            FROM rooms_groups_details
            WHERE hostel_name IS NOT NULL AND hostel_name != ''
            GROUP BY hostel_name, group_name, room_number
        ) rgd
        LEFT JOIN (
            SELECT r1.room_no, r1.hostel_name, r1.id, r1.current_reading, r1.units_consumed, r1.created_at
            FROM eb_meter_readings r1
            INNER JOIN (
                SELECT room_no, hostel_name, MAX(id) as max_id
                FROM eb_meter_readings
                $dateFilter
                GROUP BY room_no, hostel_name
            ) r2 ON r1.id = r2.max_id
        ) emr ON (emr.room_no = rgd.room_number)
        WHERE $whereSQL
    ";

    $cStmt = $db->prepare($countSql);
    $cStmt->execute($params);
    $counts = $cStmt->fetch(PDO::FETCH_ASSOC);

    $totalRecords = (int)($counts['total'] ?? 0);
    $verifiedCount = (int)($counts['total_verified'] ?? 0);
    $notVerifiedCount = (int)($counts['total_not_verified'] ?? 0);
    $totalPages = max(1, (int)ceil($totalRecords / $limit));

    // Data query
    $dataSql = "
        SELECT 
            rgd.hostel_name,
            rgd.group_name as floor_name,
            rgd.room_number,
            emr.id as reading_id,
            emr.current_reading,
            emr.units_consumed,
            emr.created_at as verified_at,
            CASE WHEN emr.id IS NOT NULL THEN 1 ELSE 0 END as is_verified
        FROM (
            SELECT MIN(s_no) as s_no, hostel_name, group_name, room_number
            FROM rooms_groups_details
            WHERE hostel_name IS NOT NULL AND hostel_name != ''
            GROUP BY hostel_name, group_name, room_number
        ) rgd
        LEFT JOIN (
            SELECT r1.room_no, r1.hostel_name, r1.id, r1.current_reading, r1.units_consumed, r1.created_at
            FROM eb_meter_readings r1
            INNER JOIN (
                SELECT room_no, hostel_name, MAX(id) as max_id
                FROM eb_meter_readings
                $dateFilter
                GROUP BY room_no, hostel_name
            ) r2 ON r1.id = r2.max_id
        ) emr ON (emr.room_no = rgd.room_number)
        WHERE $whereSQL
        ORDER BY is_verified ASC, rgd.hostel_name ASC, rgd.group_name ASC, rgd.room_number ASC
        LIMIT $limit OFFSET $offset
    ";

    $dStmt = $db->prepare($dataSql);
    $dStmt->execute($params);
    $rooms = $dStmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "status" => "success",
        "data" => $rooms,
        "hostels" => $availableHostels,
        "floors" => $availableFloors,
        "is_restricted" => $is_restricted_staff,
        "pagination" => [
            "current_page" => $page,
            "total_pages" => $totalPages,
            "total" => $totalRecords,
            "limit" => $limit,
            "verified_count" => $verifiedCount,
            "not_verified_count" => $notVerifiedCount,
        ]
    ]);
} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "message" => $e->getMessage()
    ]);
}
