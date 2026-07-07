<?php
require_once __DIR__ . '/config/database.php';
$db = new Database();
$pdo = $db->getConnection();

$username = 'warden1';
$password = 'welcome123';

try {
    $query = "SELECT u.id, u.full_name, u.username as register_no, u.password, u.role, u.conduct, u.conduct_remarks, u.Status, 
                     p.personal_phone as phone, p.room_allocation, p.institution, p.hostel_name as profile_hostel, p.address, p.dob, p.profile_pic,
                     p.valid_from, p.valid_to, u.biometric_id,
                     hr.room_no as hr_room_no, hr.building_code as block, hr.floor as floor_name, hr.wing_code as wing_name, hr.hostel_name as room_hostel, hr.room_type as room_type,
                     hr.facility as room_facility, hr.bath_attached as room_bath_attached
              FROM users u
              LEFT JOIN profile p ON u.username = p.reg_no
              LEFT JOIN hostel_rooms hr ON (hr.id = p.current_room_id OR (COALESCE(p.current_room_id, 0) = 0 AND hr.room_code = p.room_allocation))
              WHERE u.username = :username LIMIT 0,1";

    $stmt = $pdo->prepare($query);
    $stmt->bindParam(':username', $username);
    $stmt->execute();

    if ($stmt->rowCount() > 0) {
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        echo "Found user in database.\n";
        
        $verified = password_verify($password, $row['password']);
        echo "Password verification: " . ($verified ? "PASSED" : "FAILED") . "\n";
        
        if ($verified) {
            if (isset($row['Status']) && (strtolower($row['Status']) == 'inactive' || $row['Status'] == '0') && $row['role'] !== 'admin') {
                echo "Blocked: status is inactive.\n";
            } else {
                echo "Success: Login simulation passed.\n";
            }
        }
    } else {
        echo "User not found in users table.\n";
    }
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
?>
