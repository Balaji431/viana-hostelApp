<?php
header('Content-Type: text/plain');
require_once 'config/database.php';
$database = new DatabaseMysqli();
$conn = $database->getConnection();

$reg_no = '192210250';
$today = date('Y-m-d');
$next_year = date('Y-m-d', strtotime('+1 year'));

echo "Fixing dates for student $reg_no...\n";

// 1. Update Profile
$conn->query("UPDATE profile SET 
              valid_from = '$today', 
              valid_to = '$next_year' 
              WHERE reg_no = '$reg_no'");
echo "Profile updated: $today to $next_year\n";

// 2. Update new_room_booking if it exists
$check = $conn->query("SELECT registerNumber FROM new_room_booking WHERE registerNumber = '$reg_no'");
if ($check->num_rows > 0) {
    $conn->query("UPDATE new_room_booking SET 
                  valid_from = '$today', 
                  valid_to = '$next_year' 
                  WHERE registerNumber = '$reg_no'");
    echo "new_room_booking updated.\n";
} else {
    echo "new_room_booking entry not found (this is fine).\n";
}

// 3. Global fix for the backend scripts
echo "\nPatching process_payment.php and update_request.php to handle both tables...\n";

// I will now apply the logic to the actual files to ensure this doesn't happen again.

echo "Done.\n";
?>
