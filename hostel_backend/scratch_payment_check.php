<?php
require_once __DIR__ . '/config/database.php';
$database = new DatabaseMysqli();
$conn = $database->getConnection();

echo "=== CHECKING payment TABLE ===\n";
$q_pay1 = "SELECT id, registerNumber, name, payment_type, payment_id, amount, status, admin_status FROM payment LIMIT 10";
$res_pay1 = $conn->query($q_pay1);
if ($res_pay1 && $res_pay1->num_rows > 0) {
    echo "Found " . $res_pay1->num_rows . " sample rows in 'payment' table:\n";
    while ($row = $res_pay1->fetch_assoc()) {
        print_r($row);
    }
} else {
    echo "No records found in 'payment' table.\n";
}

echo "\n=== CHECKING payments TABLE ===\n";
$q_pay2 = "SELECT p.id, p.student_id, u.username as reg_no, u.full_name, p.amount, p.status, p.description, p.paid_at FROM payments p JOIN users u ON p.student_id = u.id LIMIT 10";
$res_pay2 = $conn->query($q_pay2);
if ($res_pay2 && $res_pay2->num_rows > 0) {
    echo "Found " . $res_pay2->num_rows . " sample rows in 'payments' table:\n";
    while ($row = $res_pay2->fetch_assoc()) {
        print_r($row);
    }
} else {
    echo "No records found in 'payments' table.\n";
}

echo "\n=== MATCHING REGISTER NUMBERS BETWEEN PAYMENTS AND new_room_booking ===\n";
// Let's match based on registerNumber in 'payment' and 'new_room_booking'
$q_match = "
    SELECT p.registerNumber, p.name as payment_name, p.payment_type, p.amount as paid_amount, 
           b.name as booking_name, b.room_no, b.bed_no, b.room_type, b.valid_status
    FROM payment p
    JOIN new_room_booking b ON TRIM(p.registerNumber) = TRIM(b.registerNumber)
    WHERE p.status = 'Success'
";
$res_match = $conn->query($q_match);
if ($res_match) {
    echo "Total matches found: " . $res_match->num_rows . "\n\n";
    while ($row = $res_match->fetch_assoc()) {
        echo "- Reg: {$row['registerNumber']} | Payment Name: {$row['payment_name']} | Type: {$row['payment_type']} | Paid: ₹{$row['paid_amount']}\n";
        echo "  Room Booking Details -> Name: {$row['booking_name']} | Room: {$row['room_no']} | Bed: {$row['bed_no']} | Room Type: {$row['room_type']} | Status: {$row['valid_status']}\n\n";
    }
} else {
    echo "Error querying matches: " . $conn->error . "\n";
}
?>
