<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once '../config/database.php';

$database = new Database();
$conn = $database->getConnection();

try {
    // Get room types and amounts from the hostel_renew_fee table
    $sql = "SELECT room_type as name, hostel_fee, food_fee, total_fee, facility_description as description
            FROM hostel_renew_fee 
            ORDER BY hostel_fee ASC";
            
    $stmt = $conn->prepare($sql);
    $stmt->execute();
    $roomTypes = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Format for the frontend
    $formatted = [];
    foreach ($roomTypes as $room) {
        $formatted[] = [
            'id'               => $room['name'],
            'name'             => $room['name'],
            'hostel_fee'       => (float)$room['hostel_fee'],
            'food_fee'         => (float)$room['food_fee'],
            'total_fee'        => (float)$room['total_fee'],
            'six_month_amount' => (float)$room['hostel_fee'],   // kept for backward-compat
            'monthly_amount'   => round((float)$room['hostel_fee'] / 6, 2),
            'description'      => $room['description']
        ];
    }

    // Dynamic current room inclusion logic
    $username = $_GET['username'] ?? null;
    if ($username) {
        // Find student's current room type
        $stmt_user = $conn->prepare("
            SELECT u.RoomType as user_room, hr.room_type as hr_room
            FROM users u
            LEFT JOIN profile p ON u.username = p.reg_no
            LEFT JOIN hostel_rooms hr ON (hr.id = p.current_room_id OR (COALESCE(p.current_room_id, 0) = 0 AND hr.room_code = p.room_allocation))
            WHERE u.username = ? LIMIT 1
        ");
        $stmt_user->execute([$username]);
        $row_user = $stmt_user->fetch(PDO::FETCH_ASSOC);
        
        if ($row_user) {
            $current_room_type = !empty($row_user['hr_room']) ? $row_user['hr_room'] : $row_user['user_room'];
            $current_room_type = trim($current_room_type);
            
            if (!empty($current_room_type)) {
                // Check if current room type already exists in the formatted list (case-insensitive check)
                $exists = false;
                foreach ($formatted as $item) {
                    if (strcasecmp(trim($item['name']), $current_room_type) === 0) {
                        $exists = true;
                        break;
                    }
                }
                
                if (!$exists) {
                    // Fetch last payment amount
                    $stmt_pay = $conn->prepare("
                        SELECT amount FROM payment 
                        WHERE registerNumber = ? 
                        ORDER BY booking_date DESC LIMIT 1
                    ");
                    $stmt_pay->execute([$username]);
                    $pay_row = $stmt_pay->fetch(PDO::FETCH_ASSOC);
                    $amount = $pay_row ? (float)$pay_row['amount'] : null;
                    
                    if ($amount === null) {
                        $stmt_vsp = $conn->prepare("
                            SELECT paid_amount FROM vstudy_payments 
                            WHERE roll_number = ? LIMIT 1
                        ");
                        $stmt_vsp->execute([$username]);
                        $vsp_row = $stmt_vsp->fetch(PDO::FETCH_ASSOC);
                        $amount = $vsp_row ? (float)$vsp_row['paid_amount'] : null;
                    }
                    
                    // Default fallback amount if none is found
                    if ($amount === null || $amount <= 0) {
                        $amount = (stripos($current_room_type, 'ac') !== false && stripos($current_room_type, 'non ac') === false) ? 60000.00 : 32000.00;
                    }
                    
                    // Construct and append the current room type
                    $desc = (stripos($current_room_type, 'ac') !== false && stripos($current_room_type, 'non ac') === false) ? 'AC Room Sharing' : 'Non AC sharing';
                    $formatted[] = [
                        'id' => $current_room_type,
                        'name' => $current_room_type,
                        'six_month_amount' => $amount,
                        'monthly_amount' => 2000.00,
                        'description' => $desc
                    ];
                }
            }
        }
    }

    // Sort by six_month_amount ASC
    usort($formatted, function($a, $b) {
        return $a['six_month_amount'] <=> $b['six_month_amount'];
    });

    echo json_encode([
        'status' => 'success',
        'data' => $formatted
    ]);

} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
