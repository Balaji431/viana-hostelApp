<?php
/**
 * Seeder script for Demo Student, Room Allocation, and 30-day Biometric Attendance.
 */

ini_set('display_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json; charset=UTF-8');

require_once __DIR__ . '/config/database.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo json_encode(["status" => false, "message" => "Database connection failed."]);
    exit();
}

$results = [];

try {
    $demoStudentId = 999999;
    $regNo = '192524999';
    $fullName = 'Alex Rivera (Demo)';
    $passwordPlain = 'demo';
    $passwordHash = password_hash($passwordPlain, PASSWORD_BCRYPT);
    $hostelName = 'Emerald Block - Deluxe';
    $roomNo = 'E-304';
    $floor = '3rd Floor';
    $wardenName = 'Mr. K. Venkatesh';

    // 1. Insert / Update `users` table
    $userSql = "INSERT INTO users (id, username, full_name, password, role, Status, HostelName, HostelType, RoomType, RoomId, biometric_id, Gender, Academic, Institution, department, is_active, IsBiometric)
                VALUES (:id, :username, :full_name, :password, 'student', 'active', :hostel, 'Boys', '2-Sharing AC with Attached Bath', :room_id, 'BIO-99999', 'Male', '3rd Year', 'SIMATS Engineering', 'Computer Science & Engineering', 1, 'Yes')
                ON DUPLICATE KEY UPDATE
                    full_name = VALUES(full_name),
                    password = VALUES(password),
                    role = VALUES(role),
                    Status = VALUES(Status),
                    HostelName = VALUES(HostelName),
                    HostelType = VALUES(HostelType),
                    RoomType = VALUES(RoomType),
                    RoomId = VALUES(RoomId),
                    biometric_id = VALUES(biometric_id),
                    Gender = VALUES(Gender),
                    Academic = VALUES(Academic),
                    Institution = VALUES(Institution),
                    department = VALUES(department),
                    is_active = 1,
                    IsBiometric = 'Yes'";
    
    $stmtUser = $db->prepare($userSql);
    $stmtUser->execute([
        ':id' => $demoStudentId,
        ':username' => $regNo,
        ':full_name' => $fullName,
        ':password' => $passwordHash,
        ':hostel' => $hostelName,
        ':room_id' => $roomNo,
    ]);
    $results['user'] = "User $regNo (ID: $demoStudentId) created/updated successfully with password '$passwordPlain'.";

    // 2. Insert / Update `profile` table
    $profileSql = "INSERT INTO profile (id, reg_no, user_id, full_name, personal_phone, room_allocation, institution, hostel_name, address, dob, valid_from, valid_to, warden, bed_no)
                   VALUES (:id, :reg_no, :user_id, :full_name, :phone, :room, :institution, :hostel, :address, :dob, :valid_from, :valid_to, :warden, :bed_no)
                   ON DUPLICATE KEY UPDATE
                       full_name = VALUES(full_name),
                       personal_phone = VALUES(personal_phone),
                       room_allocation = VALUES(room_allocation),
                       institution = VALUES(institution),
                       hostel_name = VALUES(hostel_name),
                       address = VALUES(address),
                       dob = VALUES(dob),
                       valid_from = VALUES(valid_from),
                       valid_to = VALUES(valid_to),
                       warden = VALUES(warden),
                       bed_no = VALUES(bed_no)";
    
    $stmtProfile = $db->prepare($profileSql);
    $stmtProfile->execute([
        ':id' => $demoStudentId,
        ':reg_no' => $regNo,
        ':user_id' => $demoStudentId,
        ':full_name' => $fullName,
        ':phone' => '+91 98765 43210',
        ':room' => $roomNo,
        ':institution' => 'SIMATS Engineering',
        ':hostel' => $hostelName,
        ':address' => '123, Green Valley Campus Rd, Chennai, TN 602105',
        ':dob' => '2004-05-15',
        ':valid_from' => '2024-07-01',
        ':valid_to' => '2027-05-31',
        ':warden' => $wardenName,
        ':bed_no' => 'Bed 2',
    ]);
    $results['profile'] = "Profile for $regNo created/updated successfully.";

    // 3. Insert / Update `rooms_groups_details` table
    $roomSql = "INSERT INTO rooms_groups_details (id, room_number, hostel_name, group_name, room_type, warden_name, total_beds, occupied_beds, available_beds, amount, food, caution_deposit, gender, active)
                VALUES (:id, :room_no, :hostel, :floor, :room_type, :warden, 2, 1, 1, 120000, 50000, 5000, 'Boys', 1)
                ON DUPLICATE KEY UPDATE
                    hostel_name = VALUES(hostel_name),
                    group_name = VALUES(group_name),
                    room_type = VALUES(room_type),
                    warden_name = VALUES(warden_name),
                    total_beds = 2,
                    occupied_beds = 1,
                    available_beds = 1,
                    active = 1";
    
    $stmtRoom = $db->prepare($roomSql);
    $stmtRoom->execute([
        ':id' => 'EMERALD_' . $roomNo,
        ':room_no' => $roomNo,
        ':hostel' => $hostelName,
        ':floor' => $floor,
        ':room_type' => '2-Sharing AC with Attached Bath',
        ':warden' => $wardenName,
    ]);
    $results['room'] = "Room $roomNo in $hostelName configured.";

    // 4. Insert 30 Days of Attendance & Biometric Logs
    $db->prepare("DELETE FROM attendance WHERE student_id = :student_id")->execute([':student_id' => $demoStudentId]);

    $attSql = "INSERT INTO attendance (id, student_id, status, log_time, source, source_type)
               VALUES (:id, :student_id, :status, :log_time, :source, :source_type)";
    $stmtAtt = $db->prepare($attSql);

    $insertedAttendanceCount = 0;
    $baseAttId = 990000;

    for ($i = 0; $i < 30; $i++) {
        $dateObj = new DateTime("-$i days");
        $dateStr = $dateObj->format('Y-m-d');
        $dayOfWeek = (int)$dateObj->format('N'); // 1 (Mon) to 7 (Sun)

        if ($dayOfWeek == 7) { // Sunday (Evening return)
            $logTime = "$dateStr 20:15:00";
            $status = 'present';
            $source = 'Biometric Gate 01';
            $sourceType = 'biometric';
        } elseif ($dayOfWeek == 6 && $i == 8) { // Leave Day
            $logTime = "$dateStr 09:00:00";
            $status = 'absent';
            $source = 'Portal';
            $sourceType = 'manual';
        } else { // Regular College Day (Morning check-in)
            $logTime = "$dateStr 08:15:00";
            $status = 'present';
            $source = 'Biometric Terminal';
            $sourceType = 'biometric';
        }

        $baseAttId++;
        $stmtAtt->execute([
            ':id' => $baseAttId,
            ':student_id' => $demoStudentId,
            ':status' => $status,
            ':log_time' => $logTime,
            ':source' => $source,
            ':source_type' => $sourceType,
        ]);
        $insertedAttendanceCount++;
    }

    $results['attendance'] = "$insertedAttendanceCount attendance & biometric records created for demo student.";

    echo json_encode([
        "status" => true,
        "message" => "Demo student, allocation, biometric records, and settings seeded successfully into backend database!",
        "login_credentials" => [
            "username" => $regNo,
            "password" => $passwordPlain,
            "bio_id" => "BIO-99999",
            "role" => "student"
        ],
        "details" => $results
    ], JSON_PRETTY_PRINT);

} catch (Exception $e) {
    echo json_encode([
        "status" => false,
        "message" => "Error during seeding: " . $e->getMessage()
    ], JSON_PRETTY_PRINT);
}
?>
