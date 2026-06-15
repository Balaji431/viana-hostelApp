<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header('Content-Type: application/json; charset=UTF-8');

$request_method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($request_method == 'OPTIONS') {
    http_response_code(200);
    exit();
}

$register_no = $_GET['register_no'] ?? null;

if (!$register_no) {
    echo json_encode(["success" => false, "message" => "Registration number is required"]);
    exit();
}

require_once __DIR__ . '/../config/database.php';

try {
    $db = new Database();
    $conn = $db->getConnection();
    
    if ($conn) {
        // Check vstudy_payments table first
        $stmt = $conn->prepare("SELECT * FROM vstudy_payments WHERE roll_number = :reg_no LIMIT 0,1");
        $stmt->execute([':reg_no' => $register_no]);
        
        if ($stmt->rowCount() > 0) {
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            
            $hPref = $row['hostel_preference'] ?? 'Girls';
            $hType = (stripos($hPref, 'girls') !== false || stripos($row['gender'], 'female') !== false) ? 'Girls' : 'Boys';
            $facility = (stripos($hPref, 'non ac') !== false || stripos($hPref, 'non-ac') !== false) ? 'Non AC' : 'AC';
            $amount = (double)($row['paid_amount'] ?? 45000.00);
            
            echo json_encode([
                "success" => true,
                "data" => [
                    'register_no' => $row['roll_number'],
                    'fee_paid' => (strtolower($row['payment_status'] ?? '') == 'paid'),
                    'paid_amount' => $amount,
                    'hostel_type' => $hType,
                    'hostel_name' => $row['hostel_name'] ?? $hType,
                    'room_type' => $hPref,
                    'facility' => $facility,
                    'bath_attached' => 'Yes',
                    'institution' => $row['campus'] ?? 'Saveetha School of Engineering',
                    'student_name' => $row['student_name'],
                    'gender' => $row['gender'],
                    'department' => $row['department'],
                    'academic_year' => $row['academic_year'],
                    'campus' => $row['campus'],
                    'hostel_preference' => $row['hostel_preference'],
                    'payment_status' => $row['payment_status'],
                    'application_status' => $row['application_status'],
                    'paid_date' => $row['paid_date'],
                    'transaction_reference' => $row['transaction_reference']
                ]
            ]);
            exit();
        }
    }
    
    // If not found in DB, return failure response (no mock data fallback)
    echo json_encode([
        "success" => false,
        "message" => "No paid hostel application found for this registration number."
    ]);
    exit();
} catch (Exception $e) {
    error_log("Error in get_paid_hostel_type from DB: " . $e->getMessage());
    echo json_encode([
        "success" => false,
        "message" => "Server error checking payment details."
    ]);
    exit();
}
?>
