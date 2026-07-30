<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

try {
    $student_id = isset($_GET['student_id']) ? (int)$_GET['student_id'] : 0;
    
    // Room type match helper logic (strictly same room type student paid for)
    if (!function_exists('isRoomTypeMatch')) {
        function isRoomTypeMatch(string $paid_pref, string $room_type_db): bool {
            $a = strtoupper(preg_replace('/\s+/', ' ', trim($paid_pref)));
            $b = strtoupper(preg_replace('/\s+/', ' ', trim($room_type_db)));

            if ($a === $b) return true;

            $normalise = function(string $s): string {
                $s = str_ireplace('double', '2 in 1', $s);
                $s = str_replace(['-', '/'], ' ', $s);
                $s = preg_replace('/\s+/', ' ', $s);
                return trim($s);
            };

            if ($normalise($a) === $normalise($b)) return true;

            return false;
        }
    }

    $rooms = [];
    
    if ($student_id > 0) {
        // Fetch student credentials and gender
        $u_stmt = $conn->prepare("SELECT username, Gender FROM users WHERE id = ?");
        $u_stmt->bind_param("i", $student_id);
        $u_stmt->execute();
        $u_res = $u_stmt->get_result()->fetch_assoc();
        $reg_no = $u_res['username'] ?? '';
        $gender = $u_res['Gender'] ?? 'Female';
        $default_hostel_type = (stripos($gender, 'female') !== false || stripos($gender, 'girls') !== false) ? 'Girls' : 'Boys';
        
        $paid_hostel_name = '';
        $paid_room_type = '';
        $paid_facility = '';
        $paid_hostel_type = $default_hostel_type;

        $stmtPay = $conn->prepare("SELECT * FROM vstudy_payments WHERE roll_number = ? LIMIT 0,1");
        $stmtPay->bind_param("s", $reg_no);
        $stmtPay->execute();
        $payResult = $stmtPay->get_result();

        if ($payResult && $payResult->num_rows > 0) {
            $payRow = $payResult->fetch_assoc();
            $hPref = $payRow['hostel_preference'] ?? '';
            $paid_hostel_type = (stripos($hPref, 'girls') !== false || stripos($payRow['gender'] ?? '', 'female') !== false) ? 'Girls' : 'Boys';
            $paid_facility = (stripos($hPref, 'non ac') !== false || stripos($hPref, 'non-ac') !== false || stripos($hPref, 'non a/c') !== false) ? 'Non AC' : 'AC';
            $paid_hostel_name = $payRow['hostel_name'] ?? (($paid_hostel_type === 'Girls') ? 'Vaigai Hostel' : 'Krishna Hostel');
            $paid_room_type = $hPref;
        } else {
            $paid_hostel_name = ($default_hostel_type === 'Girls') ? 'Vaigai Hostel' : 'Krishna Hostel';
            $paid_room_type = ($default_hostel_type === 'Girls') ? 'AC - B ATTACHED (6 IN 1)' : '4 IN 1 AC';
            $paid_facility = 'AC';
        }

        $normalised_hostel = strtolower(trim(str_ireplace(' hostel', '', $paid_hostel_name)));

        // Fetch matching rooms with available_rooms > 0
        $query = "SELECT rgd.s_no as id, rgd.room_number as number, rgd.hostel_name as block, rgd.group_name as floor, 
                         rgd.total_beds as capacity, rgd.occupied_beds as occupied,
                         rgd.available_beds as available, rgd.room_type, 'AC' as facility, 
                         rgd.amount, rgd.hostel_name, rgd.gender as hostel_type, rgd.room_number as room_code, 'General' as wing_code, rgd.group_name as floor_code
                  FROM rooms_groups_details rgd
                  WHERE (TRIM(rgd.hostel_name) LIKE CONCAT('%', ?, '%'))
                  ORDER BY rgd.group_name, rgd.room_number";
        
        $stmtRooms = $conn->prepare($query);
        $stmtRooms->bind_param("s", $paid_hostel_name);
        $stmtRooms->execute();
        $result = $stmtRooms->get_result();
        
        while ($row = $result->fetch_assoc()) {
            $rooms[] = [
                "id" => $row['id'],
                "number" => $row['number'],
                "block" => $row['block'],
                "floor" => $row['floor'],
                "capacity" => (int)$row['capacity'],
                "occupied" => (int)$row['occupied'],
                "available" => (int)$row['available'],
                "room_type" => $row['room_type'],
                "facility" => $row['facility'],
                "amount" => $row['amount'],
                "hostel_name" => $row['hostel_name'],
                "hostel_type" => $row['hostel_type'],
                "room_code" => $row['room_code'],
                "wing_code" => $row['wing_code'],
                "floor_code" => $row['floor_code'],
                "occupied_beds" => [],
                "amenities" => ["WiFi", "AC"]
            ];
        }
    } else {
        // Fetch all rooms from rooms_groups_details
        $query = "SELECT rgd.s_no as id, rgd.room_number as number, rgd.hostel_name as block, rgd.group_name as floor, 
                         rgd.total_beds as capacity, rgd.occupied_beds as occupied,
                         rgd.available_beds as available, rgd.room_type, 'AC' as facility, 
                         rgd.amount, rgd.hostel_name, rgd.gender as hostel_type, rgd.room_number as room_code, 'General' as wing_code, rgd.group_name as floor_code
                  FROM rooms_groups_details rgd
                  ORDER BY rgd.group_name, rgd.room_number";
        
        $result = $conn->query($query);
        while ($row = $result->fetch_assoc()) {
            $rooms[] = [
                "id" => $row['id'],
                "number" => $row['number'],
                "block" => $row['block'],
                "floor" => $row['floor'],
                "capacity" => (int)$row['capacity'],
                "occupied" => (int)$row['occupied'],
                "available" => (int)$row['available'],
                "room_type" => $row['room_type'],
                "facility" => $row['facility'],
                "amount" => $row['amount'],
                "hostel_name" => $row['hostel_name'],
                "hostel_type" => $row['hostel_type'],
                "room_code" => $row['room_code'],
                "wing_code" => $row['wing_code'],
                "floor_code" => $row['floor_code'],
                "occupied_beds" => [],
                "amenities" => ["WiFi", "AC"]
            ];
        }
    }

    // Fetch dynamic hostels from hostel_type table
    $hostels_res = $conn->query("SELECT id, campus, hostel_name, hostel_type, building_code FROM hostel_type ORDER BY hostel_name");
    $hostels = [];
    while ($h = $hostels_res->fetch_assoc()) {
        $hostels[] = [
            "id" => (int)$h['id'],
            "campus" => $h['campus'],
            "hostel_name" => $h['hostel_name'],
            "hostel_type" => $h['hostel_type'],
            "building_code" => $h['building_code']
        ];
    }

    echo json_encode([
        "success" => true, 
        "rooms" => $rooms, 
        "hostels" => $hostels
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
?>
