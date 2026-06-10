<?php
require_once 'config/database.php';
$database = new DatabaseMysqli();
$conn = $database->getConnection();

echo "Normalizing and fixing fees...\n";

// 1. Ensure renew_fee table has the specific room type
$room_type = 'AC - B ATTACHED (6 IN 1)';
$amount = 65000.00;

$check = $conn->prepare("SELECT id FROM renew_fee WHERE room_type = ?");
$check->bind_param("s", $room_type);
$check->execute();
if ($check->get_result()->num_rows === 0) {
    echo "Adding missing room type to renew_fee: $room_type\n";
    $ins = $conn->prepare("INSERT INTO renew_fee (room_type, six_month_amount, monthly_amount, hostel_id) VALUES (?, ?, ?, 9)");
    $monthly = $amount / 12;
    $ins->bind_param("sdd", $room_type, $amount, $monthly);
    $ins->execute();
} else {
    echo "Updating existing room type in renew_fee: $room_type\n";
    $upd = $conn->prepare("UPDATE renew_fee SET six_month_amount = ? WHERE room_type = ?");
    $upd->bind_param("ds", $amount, $room_type);
    $upd->execute();
}

// 2. Fix any existing pre_approved or approved requests that have 0 amount
echo "Fixing requests with 0 amount...\n";
$conn->query("UPDATE room_change_requests SET amount_to_pay = 65000.00 
              WHERE (status = 'pre_approved' OR status = 'approved') 
              AND (requested_room_type = '$room_type' OR requested_room_type = 'AC - B ATTACHED')
              AND (amount_to_pay IS NULL OR amount_to_pay = 0)");

// 3. Ensure all requests have a payment status
$conn->query("UPDATE room_change_requests SET payment_status = 'unpaid' WHERE payment_status IS NULL OR payment_status = ''");

echo "Done.\n";
?>
