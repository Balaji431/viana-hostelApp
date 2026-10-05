<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header("Content-Type: application/json; charset=UTF-8");

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../utils/auth_helper.php';

$authUser = requireAuth(['admin', 'super_admin']);

try {
    $db = (new Database())->getConnection();
    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true) ?: $_POST;

    $readingId = isset($input['reading_id']) ? (int)$input['reading_id'] : 0;
    $ratePerUnit = isset($input['rate_per_unit']) ? (float)$input['rate_per_unit'] : 0.00;
    $penaltyAmount = isset($input['penalty_amount']) ? (float)$input['penalty_amount'] : 0.00;
    $billingCycle = trim($input['billing_cycle'] ?? date('F Y'));
    $adminUsername = trim($input['admin_username'] ?? 'admin');
    $adminRemarks = trim($input['admin_remarks'] ?? '');
    $selectedStudents = isset($input['students']) && is_array($input['students']) ? $input['students'] : [];

    if ($readingId <= 0) {
        echo json_encode(["status" => "error", "message" => "Valid Reading ID is required"]);
        exit();
    }

    if ($ratePerUnit <= 0) {
        echo json_encode(["status" => "error", "message" => "Rate per unit must be greater than zero"]);
        exit();
    }

    // 1. Fetch the reading
    $rStmt = $db->prepare("SELECT * FROM eb_meter_readings WHERE id = ?");
    $rStmt->execute([$readingId]);
    $reading = $rStmt->fetch(PDO::FETCH_ASSOC);

    if (!$reading) {
        echo json_encode(["status" => "error", "message" => "Reading not found"]);
        exit();
    }

    $unitsConsumed = (float)$reading['units_consumed'];
    $roomNo = $reading['room_no'];
    $hostelName = $reading['hostel_name'];

    $baseAmount = round($unitsConsumed * $ratePerUnit, 2);
    $totalAmount = round($baseAmount + $penaltyAmount, 2);

    // 2. Determine students if not passed
    if (empty($selectedStudents)) {
        $studentStmt = $db->prepare("
            SELECT DISTINCT p.reg_no, p.full_name 
            FROM profile p
            WHERE p.room_allocation = ? OR p.room_allocation LIKE ?
        ");
        $studentStmt->execute([$roomNo, "%$roomNo%"]);
        $occupants = $studentStmt->fetchAll(PDO::FETCH_ASSOC);

        $splitCount = max(1, count($occupants));
        $perStudentAmount = round($totalAmount / $splitCount, 2);

        foreach ($occupants as $occ) {
            $selectedStudents[] = [
                'student_username' => $occ['reg_no'],
                'student_name' => $occ['full_name'],
                'amount' => $perStudentAmount
            ];
        }
    } else {
        $splitCount = max(1, count($selectedStudents));
        $perStudentAmount = round($totalAmount / $splitCount, 2);
    }

    // Begin transaction
    $db->beginTransaction();

    // 3. Insert into eb_bills
    $billStmt = $db->prepare("
        INSERT INTO eb_bills (
            reading_id, hostel_name, room_no, billing_cycle,
            units_consumed, rate_per_unit, base_amount, penalty_amount,
            total_amount, split_count, per_student_amount, status, created_by
        ) VALUES (
            ?, ?, ?, ?,
            ?, ?, ?, ?,
            ?, ?, ?, 'issued', ?
        )
    ");

    $billStmt->execute([
        $readingId,
        $hostelName,
        $roomNo,
        $billingCycle,
        $unitsConsumed,
        $ratePerUnit,
        $baseAmount,
        $penaltyAmount,
        $totalAmount,
        $splitCount,
        $perStudentAmount,
        $adminUsername
    ]);

    $billId = $db->lastInsertId();

    // 4. Insert into eb_bill_students
    $studStmt = $db->prepare("
        INSERT INTO eb_bill_students (
            bill_id, student_username, student_name, amount, payment_status
        ) VALUES (?, ?, ?, ?, 'unpaid')
    ");

    foreach ($selectedStudents as $stu) {
        $uName = $stu['student_username'] ?? $stu['reg_no'] ?? '';
        $fName = $stu['student_name'] ?? $stu['full_name'] ?? '';
        $amt = isset($stu['amount']) ? (float)$stu['amount'] : $perStudentAmount;

        if (!empty($uName)) {
            $studStmt->execute([$billId, $uName, $fName, $amt]);
        }
    }

    // 5. Update reading status to billed
    $updStmt = $db->prepare("
        UPDATE eb_meter_readings 
        SET status = 'billed', 
            admin_remarks = ?, 
            reviewed_by = ?, 
            reviewed_at = NOW() 
        WHERE id = ?
    ");
    $updStmt->execute([$adminRemarks, $adminUsername, $readingId]);

    $db->commit();

    echo json_encode([
        "status" => "success",
        "message" => "EB Bill generated successfully",
        "data" => [
            "bill_id" => (int)$billId,
            "room_no" => $roomNo,
            "units_consumed" => $unitsConsumed,
            "rate_per_unit" => $ratePerUnit,
            "base_amount" => $baseAmount,
            "penalty_amount" => $penaltyAmount,
            "total_amount" => $totalAmount,
            "split_count" => $splitCount,
            "per_student_amount" => $perStudentAmount,
            "students_billed" => count($selectedStudents)
        ]
    ]);
} catch (Exception $e) {
    if (isset($db) && $db->inTransaction()) {
        $db->rollBack();
    }
    echo json_encode([
        "status" => "error",
        "message" => $e->getMessage()
    ]);
}
