<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header('Content-Type: application/json; charset=UTF-8');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

try {
    $db = new Database();
    $conn = $db->getConnection();
    
    if (!$conn) {
        throw new Exception("Database connection failed");
    }

    $stmt = $conn->query("SELECT * FROM matched_student_payments ORDER BY id ASC");
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $upload_dir = __DIR__ . '/../uploads';
    if (!file_exists($upload_dir)) {
        mkdir($upload_dir, 0777, true);
    }

    $csv_file = $upload_dir . '/matched_students.csv';
    $fp = fopen($csv_file, 'w');

    // Add BOM for proper UTF-8 Excel display
    fputs($fp, chr(0xEF) . chr(0xBB) . chr(0xBF));

    // Headers
    fputcsv($fp, [
        'ID', 'Roll Number', 'Student Name', 'Gender', 'Campus', 
        'Hostel Preference', 'Allocated Hostel', 'Allocated Room', 
        'New Requested Hostel', 'New Requested Room Type', 'New Payment Status', 
        'New Room Req Paid Date', 'Transaction Reference', 'New Hostel Paid', 
        'Old Check In Date', 'Old Renewal Date', 'Matched At'
    ]);

    foreach ($rows as $row) {
        fputcsv($fp, [
            $row['id'],
            $row['roll_number'],
            $row['student_name'],
            $row['gender'],
            $row['campus'],
            $row['hostel_preference'],
            $row['allocated_hostel'],
            $row['allocated_room'],
            $row['new_req_hostel'],
            $row['new_room_request__room_type'],
            $row['new_payment_status'],
            $row['new_room_req_payed_date'],
            $row['transaction_reference'],
            $row['new_hostel_paid'],
            $row['old_check_in_date'],
            $row['old_renewal_date'],
            $row['matched_at']
        ]);
    }

    fclose($fp);

    // Build the download URL dynamically
    $protocol = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
    $host = $_SERVER['HTTP_HOST'] ?? 'localhost:8081';
    
    $download_url = "$protocol://$host/uploads/matched_students.csv";

    echo json_encode([
        "success" => true,
        "status" => "success",
        "message" => "Excel sheet generated successfully",
        "download_url" => $download_url,
        "local_download_url" => "http://localhost:8081/uploads/matched_students.csv"
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "success" => false,
        "status" => "error",
        "message" => "Export failed: " . $e->getMessage()
    ]);
}
?>
