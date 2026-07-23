<?php
require_once __DIR__ . '/config/database.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    die("Database connection failed\n");
}

$defaultPasswordHash = password_hash('123456', PASSWORD_BCRYPT);

// 1. Sync all students from users table
$stmt = $db->query("SELECT id, username, full_name, phone_number, ParentContact FROM users WHERE role = 'student'");
$students = $stmt->fetchAll(PDO::FETCH_ASSOC);

$parentCount = 0;
$mapCount = 0;

foreach ($students as $student) {
    $regNo = trim($student['username']);
    if (empty($regNo)) continue;

    $parentId = "p-" . strtolower($regNo);
    $phone = !empty($student['ParentContact']) ? $student['ParentContact'] : ($student['phone_number'] ?? '');

    // Insert parent_users
    $pStmt = $db->prepare("INSERT INTO parent_users (parent_id, password, contact) 
                           VALUES (:parent_id, :password, :contact) 
                           ON DUPLICATE KEY UPDATE password = VALUES(password)");
    $pStmt->execute([
        ':parent_id' => $parentId,
        ':password' => $defaultPasswordHash,
        ':contact' => $phone
    ]);
    $parentCount++;

    // Insert parent_student_map
    $mStmt = $db->prepare("INSERT IGNORE INTO parent_student_map (parent_id, student_id) VALUES (:parent_id, :student_id)");
    $mStmt->execute([
        ':parent_id' => $parentId,
        ':student_id' => $regNo
    ]);
    $mapCount++;
}

echo "Successfully synchronized {$parentCount} parent accounts and {$mapCount} parent-student mappings.\n";
