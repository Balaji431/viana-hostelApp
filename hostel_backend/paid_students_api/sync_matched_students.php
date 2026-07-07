<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
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

    // 1. Recreate the matched_student_payments table with new schema
    $conn->exec("DROP TABLE IF EXISTS matched_student_payments");
    $create_table_sql = "
        CREATE TABLE matched_student_payments (
            id INT AUTO_INCREMENT PRIMARY KEY,
            roll_number VARCHAR(50) UNIQUE,
            student_name VARCHAR(255),
            gender VARCHAR(50),
            campus VARCHAR(255),
            hostel_preference VARCHAR(255),
            allocated_hostel VARCHAR(255),
            allocated_room VARCHAR(255),
            new_req_hostel VARCHAR(255),
            new_room_request__room_type VARCHAR(255),
            new_payment_status VARCHAR(50),
            new_room_req_payed_date VARCHAR(100),
            transaction_reference VARCHAR(255),
            new_hostel_paid DECIMAL(10,2),
            old_check_in_date VARCHAR(100),
            old_renewal_date VARCHAR(100),
            matched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
    ";
    $conn->exec($create_table_sql);

    // 2. Query overlapping students in users & vstudy_payments tables
    $query = "
        SELECT 
            u.username as roll_number,
            u.full_name as student_name,
            u.Gender as gender,
            u.Campus as campus,
            vp.hostel_preference,
            p.hostel_name as allocated_hostel,
            p.room_allocation as allocated_room,
            vp.hostel_name as new_req_hostel,
            vp.hostel_preference as new_room_request__room_type,
            vp.payment_status as new_payment_status,
            vp.paid_date as new_room_req_payed_date,
            vp.transaction_reference,
            vp.paid_amount as new_hostel_paid,
            COALESCE(p.check_in_date, p.valid_from) as old_check_in_date,
            COALESCE(p.renewal_date, p.valid_to) as old_renewal_date
        FROM users u
        INNER JOIN vstudy_payments vp ON u.username = vp.roll_number
        INNER JOIN profile p ON u.username = p.reg_no
        WHERE u.role = 'student'
          AND p.current_room_id IS NOT NULL
          AND p.current_room_id > 0
          AND p.room_allocation IS NOT NULL
          AND p.room_allocation != ''
          AND LOWER(vp.payment_status) = 'paid'
    ";
    $stmt = $conn->query($query);
    $matched_students = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // 3. Upsert records into matched_student_payments
    $upsert_sql = "
        INSERT INTO matched_student_payments (
            roll_number, student_name, gender, campus, hostel_preference, allocated_hostel, allocated_room,
            new_req_hostel, new_room_request__room_type, new_payment_status, new_room_req_payed_date, transaction_reference, new_hostel_paid, old_check_in_date, old_renewal_date
        ) VALUES (
            :roll_number, :student_name, :gender, :campus, :hostel_preference, :allocated_hostel, :allocated_room,
            :new_req_hostel, :new_room_request__room_type, :new_payment_status, :new_room_req_payed_date, :transaction_reference, :new_hostel_paid, :old_check_in_date, :old_renewal_date
        ) ON DUPLICATE KEY UPDATE
            student_name = VALUES(student_name),
            gender = VALUES(gender),
            campus = VALUES(campus),
            hostel_preference = VALUES(hostel_preference),
            allocated_hostel = VALUES(allocated_hostel),
            allocated_room = VALUES(allocated_room),
            new_req_hostel = VALUES(new_req_hostel),
            new_room_request__room_type = VALUES(new_room_request__room_type),
            new_payment_status = VALUES(new_payment_status),
            new_room_req_payed_date = VALUES(new_room_req_payed_date),
            transaction_reference = VALUES(transaction_reference),
            new_hostel_paid = VALUES(new_hostel_paid),
            old_check_in_date = VALUES(old_check_in_date),
            old_renewal_date = VALUES(old_renewal_date)
    ";
    $stmt_upsert = $conn->prepare($upsert_sql);

    $upserted_count = 0;
    foreach ($matched_students as $student) {
        $stmt_upsert->execute([
            ':roll_number' => $student['roll_number'],
            ':student_name' => $student['student_name'],
            ':gender' => $student['gender'],
            ':campus' => $student['campus'],
            ':hostel_preference' => $student['hostel_preference'],
            ':allocated_hostel' => $student['allocated_hostel'],
            ':allocated_room' => $student['allocated_room'],
            ':new_req_hostel' => $student['new_req_hostel'],
            ':new_room_request__room_type' => $student['new_room_request__room_type'],
            ':new_payment_status' => $student['new_payment_status'],
            ':new_room_req_payed_date' => $student['new_room_req_payed_date'],
            ':transaction_reference' => $student['transaction_reference'],
            ':new_hostel_paid' => $student['new_hostel_paid'],
            ':old_check_in_date' => $student['old_check_in_date'],
            ':old_renewal_date' => $student['old_renewal_date']
        ]);
        $upserted_count++;
    }

    echo json_encode([
        "success" => true,
        "status" => "success",
        "message" => "Matched students synchronization completed successfully",
        "stats" => [
            "matched_records_found" => count($matched_students),
            "records_upserted" => $upserted_count
        ]
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "success" => false,
        "status" => "error",
        "message" => "Matched sync failed: " . $e->getMessage()
    ]);
}
?>
