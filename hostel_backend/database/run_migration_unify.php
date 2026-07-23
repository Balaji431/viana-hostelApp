<?php
require_once __DIR__ . '/../config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();

    echo "Starting DB Unification Migration...\n";

    // 1. Add missing staff columns to users table safely
    $columnsToAdd = [
        'department' => "VARCHAR(255) NULL AFTER Institution",
        'is_active' => "TINYINT(1) DEFAULT 1 AFTER Status",
        'raw_api_data' => "JSON NULL"
    ];

    foreach ($columnsToAdd as $col => $definition) {
        $check = $db->query("SHOW COLUMNS FROM users LIKE '$col'");
        if ($check->rowCount() === 0) {
            $db->exec("ALTER TABLE users ADD COLUMN $col $definition");
            echo "Added column '$col' to users table.\n";
        } else {
            echo "Column '$col' already exists in users table.\n";
        }
    }

    // 2. Fetch all staff_users
    $staffQuery = $db->query("SELECT * FROM staff_users");
    $staffList = $staffQuery->fetchAll(PDO::FETCH_ASSOC);
    echo "Fetched " . count($staffList) . " records from staff_users.\n";

    // 3. Migrate each staff member to users table
    $insertedCount = 0;
    $skippedCount = 0;

    $checkStmt = $db->prepare("SELECT id FROM users WHERE username = :username LIMIT 1");
    $insertStmt = $db->prepare("
        INSERT INTO users (
            username, RegisterNumber, biometric_id, full_name, password, 
            email, phone_number, role, Institution, department, 
            Designation, Status, is_active, raw_api_data, Created_On
        ) VALUES (
            :username, :register_no, :biometric_id, :full_name, :password, 
            :email, :phone, :role, :institution, :department, 
            :designation, 'active', :is_active, :raw_api_data, :created_at
        )
    ");

    foreach ($staffList as $staff) {
        $checkStmt->execute([':username' => $staff['bio_id']]);
        if ($checkStmt->rowCount() > 0) {
            $skippedCount++;
            continue;
        }

        // Insert
        $insertStmt->execute([
            ':username' => $staff['bio_id'],
            ':register_no' => $staff['bio_id'],
            ':biometric_id' => $staff['bio_id'],
            ':full_name' => $staff['name'],
            ':password' => $staff['password'],
            ':email' => $staff['email'],
            ':phone' => $staff['phone'],
            ':role' => $staff['role'] ?: 'staff',
            ':institution' => $staff['department'], // Mapped to Institution
            ':department' => $staff['department'],
            ':designation' => $staff['designation'],
            ':is_active' => $staff['is_active'],
            ':raw_api_data' => $staff['raw_api_data'],
            ':created_at' => $staff['created_at']
        ]);
        $insertedCount++;
    }

    echo "Migration completed successfully!\n";
    echo "Inserted: $insertedCount staff users into users table.\n";
    echo "Skipped (already exists): $skippedCount users.\n";

} catch (Exception $e) {
    echo "Migration failed: " . $e->getMessage() . "\n";
}
?>
