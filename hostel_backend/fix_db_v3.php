<?php
header('Content-Type: text/plain');
require_once 'config/database.php';
$database = new DatabaseMysqli();
$conn = $database->getConnection();

echo "Step 1: Checking room_change_requests schema...\n";
$cols = $conn->query("SHOW COLUMNS FROM room_change_requests");
$has_amount = false;
$has_payment_status = false;
$has_rtype = false;
while($row = $cols->fetch_assoc()) {
    if ($row['Field'] == 'amount_to_pay') $has_amount = true;
    if ($row['Field'] == 'payment_status') $has_payment_status = true;
    if ($row['Field'] == 'requested_room_type') $has_rtype = true;
}

if (!$has_amount) {
    echo "Adding amount_to_pay column...\n";
    $conn->query("ALTER TABLE room_change_requests ADD COLUMN amount_to_pay DECIMAL(10,2) DEFAULT 0.00 AFTER requested_room");
}
if (!$has_payment_status) {
    echo "Adding payment_status column...\n";
    $conn->query("ALTER TABLE room_change_requests ADD COLUMN payment_status VARCHAR(20) DEFAULT 'unpaid' AFTER amount_to_pay");
}
if (!$has_rtype) {
    echo "Adding requested_room_type column...\n";
    $conn->query("ALTER TABLE room_change_requests ADD COLUMN requested_room_type VARCHAR(100) AFTER requested_room");
}

echo "Step 2: Normalizing renew_fee data...\n";
$target_type = 'AC - B ATTACHED (6 IN 1)';
$target_amount = 65000.00;

$check = $conn->prepare("SELECT id FROM renew_fee WHERE UPPER(TRIM(room_type)) = ?");
$norm = strtoupper(trim($target_type));
$check->bind_param("s", $norm);
$check->execute();
if ($check->get_result()->num_rows === 0) {
    echo "Inserting $target_type into renew_fee...\n";
    $ins = $conn->prepare("INSERT INTO renew_fee (room_type, six_month_amount, monthly_amount, hostel_id) VALUES (?, ?, ?, 9)");
    $monthly = $target_amount / 6; // 6 months
    $ins->bind_param("sdd", $target_type, $target_amount, $monthly);
    $ins->execute();
} else {
    echo "Updating $target_type in renew_fee...\n";
    $upd = $conn->prepare("UPDATE renew_fee SET six_month_amount = ? WHERE UPPER(TRIM(room_type)) = ?");
    $upd->bind_param("ds", $target_amount, $norm);
    $upd->execute();
}

echo "Step 3: Fixing existing requests with 0 amount...\n";
// Find room type from hostel_rooms if requested_room_type is missing
$conn->query("UPDATE room_change_requests r 
              JOIN hostel_rooms hr ON r.requested_room = hr.room_code 
              SET r.requested_room_type = hr.room_type 
              WHERE r.requested_room_type IS NULL OR r.requested_room_type = ''");

// Update amounts based on renew_fee
$conn->query("UPDATE room_change_requests r 
              JOIN renew_fee f ON UPPER(TRIM(r.requested_room_type)) = UPPER(TRIM(f.room_type))
              SET r.amount_to_pay = f.six_month_amount 
              WHERE (r.status = 'pre_approved' OR r.status = 'approved') 
              AND (r.amount_to_pay IS NULL OR r.amount_to_pay = 0)");

// Hardcoded fix for the specific room type requested
$conn->query("UPDATE room_change_requests 
              SET amount_to_pay = 65000.00 
              WHERE (status = 'pre_approved' OR status = 'approved') 
              AND (UPPER(TRIM(requested_room_type)) LIKE '%AC - B ATTACHED%')
              AND (amount_to_pay IS NULL OR amount_to_pay = 0)");

echo "Step 4: Ensuring payment_status is set for UI logic...\n";
$conn->query("UPDATE room_change_requests SET payment_status = 'unpaid' WHERE (status = 'pre_approved' OR status = 'approved') AND (payment_status IS NULL OR payment_status = '')");

echo "All DB fixes applied.\n";
?>
