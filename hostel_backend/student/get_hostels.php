<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if (($_SERVER['REQUEST_METHOD'] ?? '') == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

if (!$conn) {
    echo json_encode(['status' => 'error', 'message' => 'Database connection failed']);
    exit();
}

function normalizeInstitution(string $inst): string {
    $inst = trim($inst);
    if (stripos($inst, 'Engineering') !== false || stripos($inst, 'SSE') !== false
        || (stripos($inst, 'SIMATS') !== false && stripos($inst, 'Medicine') === false && stripos($inst, 'Dentist') === false)
        || stripos($inst, 'Thandalam') !== false) {
        return 'SIMATS - Engineering';
    }
    if (stripos($inst, 'Medicine') !== false || stripos($inst, 'SMC') !== false) {
        return 'SMC - Medicine';
    }
    if (stripos($inst, 'Dentist') !== false || stripos($inst, 'SDC') !== false) {
        return 'SDC - Dentistry';
    }
    if (stripos($inst, 'Law') !== false || stripos($inst, 'SSL') !== false) {
        return 'SSL - Law';
    }
    if (stripos($inst, 'Management') !== false || stripos($inst, 'SSM') !== false) {
        return 'SSM - Management';
    }
    if (stripos($inst, 'Physical') !== false || stripos($inst, 'SSPE') !== false) {
        return 'SSPE - Physical Education';
    }
    if (stripos($inst, 'Nursing') !== false || stripos($inst, 'SNC') !== false) {
        return 'SNC - Nursing';
    }
    if (stripos($inst, 'Basic') !== false || stripos($inst, 'SIBMS') !== false) {
        return 'SIBMS - Basic Sciences';
    }
    if (stripos($inst, 'Allied') !== false || stripos($inst, 'SCAHS') !== false) {
        return 'SCAHS - Allied Health';
    }
    if (stripos($inst, 'Design') !== false || stripos($inst, 'STUDIO') !== false) {
        return 'STUDIO - Design School';
    }
    if (stripos($inst, 'Liberal') !== false || stripos($inst, 'SCLAS') !== false) {
        return 'SCLAS - Liberal Arts';
    }
    return $inst;
}

try {
    $reg = $_GET['register_no'] ?? $_GET['username'] ?? $_GET['roll_number'] ?? null;
    $id  = $_GET['student_id'] ?? null;

    $gender      = null;   // 'Female' or 'Male'
    $hostelType  = null;   // 'Girls' or 'Boys'
    $institution = null;

    if ($reg || $id) {
        if ($reg) {
            $stmt = $conn->prepare("
                SELECT u.Gender, u.HostelType, u.Institution, p.institution as p_institution 
                FROM users u 
                LEFT JOIN profile p ON u.username = p.reg_no 
                WHERE u.username = ? OR u.email = ? LIMIT 1
            ");
            $stmt->bind_param("ss", $reg, $reg);
        } else {
            $stmt = $conn->prepare("
                SELECT u.Gender, u.HostelType, u.Institution, p.institution as p_institution 
                FROM users u 
                LEFT JOIN profile p ON u.id = p.user_id 
                WHERE u.id = ? LIMIT 1
            ");
            $stmt->bind_param("i", $id);
        }
        $stmt->execute();
        $studentRow = $stmt->get_result()->fetch_assoc();

        if ($studentRow) {
            $rawGender   = $studentRow['Gender'] ?? $studentRow['HostelType'] ?? '';
            $isFemale    = (stripos($rawGender, 'girl') !== false || stripos($rawGender, 'female') !== false);
            $gender      = $isFemale ? 'Female' : 'Male';
            $hostelType  = $isFemale ? 'Girls' : 'Boys';
            // Prefer users.Institution; fall back to profile.institution if blank
            $rawInst = '';
            if (!empty(trim($studentRow['Institution'] ?? ''))) {
                $rawInst = trim($studentRow['Institution']);
            } elseif (!empty(trim($studentRow['p_institution'] ?? ''))) {
                $rawInst = trim($studentRow['p_institution']);
            }
            if ($rawInst !== '') {
                $institution = normalizeInstitution($rawInst);
            }
        }
    }

    $whereConditions = ["1=1"];
    $params = [];
    $types  = "";

    if ($gender !== null) {
        // Strict gender match — rooms with blank/NULL gender are excluded from both boys & girls
        $whereConditions[] = "(r.gender = ? AND r.gender IS NOT NULL AND TRIM(r.gender) != '')";
        $params[] = $gender;
        $types   .= "s";
    }

    if ($institution !== null) {
        // Institution KNOWN → show ONLY hostels explicitly reserved for this institution.
        // Do NOT include unrestricted hostels (reserved_for = []) — those belong to no
        // specific institution and must not bleed into institution-filtered results.
        $whereConditions[] = "(r.reserved_for IS NOT NULL AND r.reserved_for != '[]' AND JSON_CONTAINS(r.reserved_for, JSON_QUOTE(?)))";
        $params[] = $institution;
        $types   .= "s";
    } elseif (!empty($reg) || !empty($id)) {
        // Specific student provided but institution unknown → show only completely unrestricted hostels
        $whereConditions[] = "(r.reserved_for IS NULL OR r.reserved_for = '[]')";
    }
    // When called without student (e.g. Admin Portal / Fee Management / Hierarchy), do not filter by institution

    $whereConditions[] = "r.available_beds > 0";
    $whereSql = implode(" AND ", $whereConditions);

    // Query distinct physical rooms and available beds directly from rooms_groups_details
    $query = "
        SELECT 
            r.hostel_name,
            COUNT(DISTINCT r.group_name) as floor_count,
            COUNT(DISTINCT r.room_type) as room_type_count,
            COUNT(r.s_no) as room_count,
            COALESCE(SUM(r.total_beds), 0) as total_capacity,
            COALESCE(SUM(r.available_beds), 0) as available_rooms,
            COALESCE(h.campus, 'Thandalam Campus') as campus,
            COALESCE(h.hostel_type, ?) as hostel_type,
            COALESCE(h.building_code, '') as building_code
        FROM rooms_groups_details r
        LEFT JOIN hostel_type h ON TRIM(h.hostel_name) = TRIM(r.hostel_name)
        WHERE $whereSql
        GROUP BY r.hostel_name, h.campus, h.hostel_type, h.building_code
        HAVING available_rooms > 0
        ORDER BY r.hostel_name ASC
    ";

    $hostelTypeDefault = $hostelType ?? 'Girls';
    $finalParams = array_merge([$hostelTypeDefault], $params);
    $finalTypes  = "s" . $types;

    $stmt = $conn->prepare($query);
    if (!empty($finalParams)) {
        $stmt->bind_param($finalTypes, ...$finalParams);
    }
    $stmt->execute();
    $result = $stmt->get_result();

    if (!$result) {
        throw new Exception("Error fetching hostels: " . $conn->error);
    }

    $hostels           = [];
    $cityCampus        = [];
    $thandalamCampus   = [];
    $poonamalleeCampus = [];

    while ($row = $result->fetch_assoc()) {
        $hostel = [
            'id'              => $row['hostel_name'],
            'campus'          => $row['campus'],
            'hostel_name'     => $row['hostel_name'],
            'hostel_type'     => $row['hostel_type'],
            'building_code'   => $row['building_code'],
            'zone_count'      => (int)$row['floor_count'],
            'room_count'      => (int)$row['room_count'],
            'room_type_count' => (int)$row['room_type_count'],
            'total_capacity'  => (int)$row['total_capacity'],
            'available_rooms' => max(0, (int)$row['available_rooms'])
        ];

        if ($row['campus'] === 'City Campus') {
            $cityCampus[] = $hostel;
        } elseif ($row['campus'] === 'Poonamallee Campus') {
            $poonamalleeCampus[] = $hostel;
            $thandalamCampus[]   = $hostel;
        } else {
            $thandalamCampus[]   = $hostel;
        }

        $hostels[] = $hostel;
    }

    echo json_encode([
        'status'  => 'success',
        'message' => 'Hostels retrieved successfully',
        'data'    => [
            'all_hostels'      => $hostels,
            'by_campus'        => [
                'city_campus'        => $cityCampus,
                'thandalam_campus'   => $thandalamCampus,
                'poonamallee_campus' => $poonamalleeCampus
            ],
            'total_count'      => count($hostels),
            'filter_applied'   => [
                'gender'      => $gender,
                'institution' => $institution
            ]
        ]
    ]);

    $conn->close();

} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'status'  => 'error',
        'message' => $e->getMessage()
    ]);
}
?>
