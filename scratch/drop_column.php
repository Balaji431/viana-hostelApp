<?php
require_once __DIR__ . '/../hostel_backend/config/database.php';
$db = new DatabaseMysqli();
$conn = $db->getConnection();

try {
    $conn->query("ALTER TABLE vstudy_payments DROP COLUMN pagination_page");
    echo "Removed pagination_page from vstudy_payments.\n";
} catch (Exception $e) {
    echo "vstudy_payments alter: " . $e->getMessage() . "\n";
}

try {
    $conn->query("ALTER TABLE matched_student_payments DROP COLUMN pagination_page");
    echo "Removed pagination_page from matched_student_payments.\n";
} catch (Exception $e) {
    echo "matched_student_payments alter: " . $e->getMessage() . "\n";
}
