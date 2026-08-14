<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';
require_once __DIR__ . '/../../../hostel_backend/utils/auth_helper.php';

$database = new Database();
$db = $database->getConnection();

$username = '192511250';

$query = "SELECT u.id, u.full_name, u.username as register_no, u.password, u.role, u.conduct, u.conduct_remarks, u.Status, u.HostelType,
                 p.personal_phone as phone, p.room_allocation, p.institution, p.hostel_name as profile_hostel, p.address, p.dob, p.profile_pic,
                 p.valid_from, p.valid_to, u.biometric_id, COALESCE(p.warden, rgd.warden_name) as warden,
                 rgd.room_number as hr_room_no, rgd.hostel_name as block, rgd.group_name as floor_name, '' as wing_name, rgd.hostel_name as room_hostel, rgd.room_type as room_type,
                 '' as room_facility, '' as room_bath_attached, rgd.room_number as room_code
          FROM users u
          LEFT JOIN profile p ON u.username = p.reg_no
          LEFT JOIN rooms_groups_details rgd ON (
              rgd.room_number = COALESCE(NULLIF(p.room_allocation,''), u.RoomId)
              OR REPLACE(REPLACE(TRIM(rgd.room_number), ' ', ''), '-', '') = REPLACE(REPLACE(TRIM(COALESCE(NULLIF(p.room_allocation,''), u.RoomId)), ' ', ''), '-', '')
          )
          WHERE u.username = :username LIMIT 0,1";

$stmt = $db->prepare($query);
$stmt->bindParam(':username', $username);
$stmt->execute();
$row = $stmt->fetch(PDO::FETCH_ASSOC);

echo "=== BACKEND USER DATA RESPONSE FOR 192511250 ===\n";
print_r($row);
