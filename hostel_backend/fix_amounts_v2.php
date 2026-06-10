<?php
header('Content-Type: text/plain');
require_once 'config/database.php';
$database = new DatabaseMysqli();
$conn = $database->getConnection();

echo "--- Room Fee Normalization ---\n";

$target_room_type = 'AC - B ATTACHED (6 IN 1)';
$target_amount = 65000.00;

// 1. Ensure the room type exists in renew_fee with the correct amount
$check_fee = $conn->prepare("SELECT id FROM renew_fee WHERE UPPER(TRIM(room_type)) = ?");
$normalized_search = strtoupper(trim($target_room_type));
$check_fee->bind_param("s", $normalized_search);
$check_fee->execute();
$fee_res = $check_fee->get_result();

if ($fee_res->num_rows === 0) {
    echo "Adding missing fee entry for: $target_room_type\n";
    $ins = $conn->prepare("INSERT INTO renew_fee (room_type, six_month_amount, monthly_amount, hostel_id, facility_description) VALUES (?, ?, ?, 9, 'AC Room with B-Attached bathroom (6 sharing)')");
    $monthly = $target_amount / 12;
    $ins->bind_param("sdd", $target_room_type, $target_amount, $monthly);
    $ins->execute();
} else {
    echo "Updating existing fee entry for: $target_room_type\n";
    $upd = $conn->prepare("UPDATE renew_fee SET six_month_amount = ? WHERE UPPER(TRIM(room_type)) = ?");
    $upd->bind_param("ds", $target_amount, $normalized_search);
    $upd->execute();
}

// 2. Fix hostel_rooms table - ensure the amount matches there too for consistency
echo "Updating hostel_rooms amounts for type: $target_room_type\n";
$upd_rooms = $conn->prepare("UPDATE hostel_rooms SET amount = ? WHERE UPPER(TRIM(room_type)) = ? OR UPPER(TRIM(room_type)) = 'AC - B ATTACHED'");
$upd_rooms->bind_param("ds", $target_amount, $normalized_search);
$upd_rooms->execute();

// 3. Fix existing requests that are stuck with 0 amount
echo "Fixing requests stuck with 0.00 amount...\n";
$conn->query("UPDATE room_change_requests 
              SET amount_to_pay = $target_amount 
              WHERE (status = 'pre_approved' OR status = 'approved') 
              AND (UPPER(TRIM(requested_room_type)) = '$normalized_search' OR UPPER(TRIM(requested_room_type)) = 'AC - B ATTACHED')
              AND (amount_to_pay IS NULL OR amount_to_pay <= 0)");

// 4. Ensure payment_status is set
$conn->query("UPDATE room_change_requests SET payment_status = 'unpaid' WHERE payment_status IS NULL OR payment_status = ''");

echo "Data normalization complete.\n";
?>
