<?php
header('Content-Type: text/plain; charset=utf-8');
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/api_config.php';

$db = new Database();
$conn = $db->getConnection();

if (!$conn) {
    die("Database connection failed\n");
}

$page = 1;
$limit = 50; // Limit of 50 to retrieve all pages quickly
$totalPages = 1;
$inserted_count = 0;

$upsert_sql = "INSERT INTO vstudy_payments (
    student_name, roll_number, gender, academic_year, campus, 
    hostel_preference, hostel_name, payment_status, application_status, paid_date, 
    transaction_reference, paid_amount
) VALUES (
    :student_name, :roll_number, :gender, :academic_year, :campus, 
    :hostel_preference, :hostel_name, :payment_status, :application_status, :paid_date, 
    :transaction_reference, :paid_amount
)";
$stmt_upsert = $conn->prepare($upsert_sql);

do {
    echo "Fetching page $page (limit: $limit)...\n";
    $url = VSTUDY_PAYMENT_API_URL . "?page=$page&limit=$limit";
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 30);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
    curl_setopt($ch, CURLOPT_IPRESOLVE, CURL_IPRESOLVE_V4);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'x-client-id: ' . VSTUDY_CLIENT_ID,
        'x-client-secret: ' . VSTUDY_CLIENT_SECRET,
        'Accept: application/json'
    ]);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curl_error = curl_error($ch);
    curl_close($ch);
    
    if ($curl_error || $httpCode !== 200) {
        die("API call failed at page $page: " . ($curl_error ?: "HTTP Status: $httpCode") . "\n");
    }
    
    $data = json_decode($response, true);
    $records = isset($data['data']) ? $data['data'] : (is_array($data) ? $data : []);
    
    // Set totalPages dynamically on first response
    if ($page === 1) {
        echo "=== TRUNCATING vstudy_payments TABLE ===\n";
        $conn->exec("TRUNCATE TABLE vstudy_payments");
        $conn->exec("ALTER TABLE vstudy_payments AUTO_INCREMENT = 1");

        $totalPages = $data['pagination']['totalPages'] ?? 1;
        $totalRows = $data['pagination']['total'] ?? 0;
        echo "Total API Records: $totalRows, Total Pages: $totalPages\n";
    }
    
    foreach ($records as $record) {
        $student = $record['student'] ?? [];
        $hostel = $record['hostel'] ?? [];
        $room = $record['room'] ?? [];
        $fees = $record['fees'] ?? [];

        $student_name = $student['name'] ?? $record['student_name'] ?? $record['name'] ?? null;
        $roll_number = $student['rollNumber'] ?? $record['roll_number'] ?? $record['rollNumber'] ?? null;
        $gender = $room['gender'] ?? $record['gender'] ?? 'Female';
        $department = $record['department'] ?? null;
        $academic_year = $record['academic_year'] ?? '1st Year';
        $campus = $hostel['campus'] ?? $record['campus'] ?? 'Saveetha School of Engineering';
        $hostel_preference = $room['roomType'] ?? $record['hostel_preference'] ?? null;
        $hostel_name = $hostel['name'] ?? $record['hostel_name'] ?? null;
        
        if (empty($hostel_name)) {
            $isFemale = (stripos((string)$gender, 'female') !== false);
            if (stripos((string)$campus, 'Poonamallee') !== false) {
                $hostel_name = $isFemale ? 'Radiance Inn' : 'Stunners Den';
            } else {
                if ($isFemale) {
                    if (stripos((string)$hostel_preference, 'non ac') !== false || stripos((string)$hostel_preference, 'non-ac') !== false) {
                        $hostel_name = 'Ponni Hostel';
                    } else {
                        $hostel_name = 'Vaigai Hostel';
                    }
                } else {
                    if (stripos((string)$hostel_preference, 'super deluxe') !== false) {
                        $hostel_name = 'Noyyal Hostel';
                    } else if (stripos((string)$hostel_preference, 'semi deluxe') !== false) {
                        $hostel_name = 'Kaveri Hostel';
                    } else {
                        $hostel_name = 'Krishna Hostel';
                    }
                }
            }
        }

        $payment_status = $record['payment_status'] ?? 'Paid';
        $application_status = $record['application_status'] ?? 'Verified';
        $paid_date = $record['paidAt'] ?? $record['paid_date'] ?? date('Y-m-d H:i:s');
        $transaction_reference = $record['receiptNumber'] ?? $record['transaction_reference'] ?? 'TXN' . time() . rand(10, 99);
        
        $paid_amount = $fees['total'] ?? $record['paid_amount'] ?? $record['amount'] ?? null;
        if ($paid_amount === null) {
            if (stripos((string)$hostel_preference, 'non ac') !== false || stripos((string)$hostel_preference, 'non-ac') !== false) {
                $paid_amount = 45000.00;
            } else {
                $paid_amount = 68000.00;
            }
        }

        if (empty($roll_number)) {
            continue;
        }

        $stmt_upsert->execute([
            ':student_name' => $student_name,
            ':roll_number' => trim($roll_number),
            ':gender' => $gender,
            ':academic_year' => $academic_year,
            ':campus' => $campus,
            ':hostel_preference' => $hostel_preference,
            ':hostel_name' => $hostel_name,
            ':payment_status' => $payment_status,
            ':application_status' => $application_status,
            ':paid_date' => $paid_date,
            ':transaction_reference' => $transaction_reference,
            ':paid_amount' => $paid_amount
        ]);
        $inserted_count++;
    }
    
    $page++;
} while ($page <= $totalPages);

echo "=== SUCCESSFULLY POPULATED $inserted_count ROWS IN vstudy_payments ===\n";
?>
