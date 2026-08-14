<?php
header('Content-Type: application/json; charset=UTF-8');
require_once __DIR__ . '/../config/database.php';

$apiKey = "nxB8jaBKJH0WAsQNLgtZFssGAqoAGtGQQictKQ0+0nI=";
$baseUrl = "https://360.saveetha.com/api/external/get-emp-lists.php";

function fetchAllFromApi($search, $apiKey, $baseUrl) {
    $allRecords = [];
    $page = 1;
    $totalPages = 1;

    do {
        $url = $baseUrl . "?search=" . urlencode($search) . "&page=" . $page;
        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 30,
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_SSL_VERIFYHOST => false,
            CURLOPT_HTTPHEADER => [
                "X-API-KEY: $apiKey",
                "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
                "Accept: application/json"
            ]
        ]);

        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($httpCode !== 200 || !$response) {
            break;
        }

        $json = json_decode($response, true);
        if (is_array($json)) {
            if (isset($json['success']) && $json['success'] === true) {
                $totalPages = $json['total_pages'] ?? 1;
                $items = $json['data'] ?? [];
                $allRecords = array_merge($allRecords, $items);
                $page++;
            } else if (isset($json[0]) && is_array($json[0])) {
                // Direct JSON array of employee objects
                $allRecords = array_merge($allRecords, $json);
                break;
            } else {
                break;
            }
        } else {
            break;
        }
    } while ($page <= $totalPages);

    return $allRecords;
}

try {
    $database = new Database();
    $db = $database->getConnection();

    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $defaultPassword = password_hash('welcome123', PASSWORD_DEFAULT);

    // 1. Fetch and Import Security Users
    $securityRecords = fetchAllFromApi("security", $apiKey, $baseUrl);
    $secStmt = $db->prepare("
        INSERT INTO security_users (bio_id, employee_name, email, phone, department, gender, dob)
        VALUES (:bio_id, :employee_name, :email, :phone, :department, :gender, :dob)
        ON DUPLICATE KEY UPDATE
            employee_name = VALUES(employee_name),
            email = VALUES(email),
            phone = VALUES(phone),
            department = VALUES(department),
            gender = VALUES(gender),
            dob = VALUES(dob)
    ");

    $userSecUpsert = $db->prepare("
        INSERT INTO users (username, full_name, email, phone_number, role, password, Designation, Status, is_active, Institution)
        VALUES (:username, :name, :email, :phone, 'security', :pw, 'Security Guard', '1', 1, 'SIMATS')
        ON DUPLICATE KEY UPDATE
            full_name = VALUES(full_name),
            email = VALUES(email),
            phone_number = VALUES(phone_number),
            role = 'security',
            Status = '1',
            is_active = 1
    ");

    $staffSecUpsert = $db->prepare("
        INSERT INTO staff_users (bio_id, password, name, email, phone, dept, desig, role)
        VALUES (:bio_id, :pw, :name, :email, :phone, :dept, 'Security Guard', 'security')
        ON DUPLICATE KEY UPDATE
            name = VALUES(name),
            email = VALUES(email),
            phone = VALUES(phone),
            role = 'security'
    ");

    $secCount = 0;
    foreach ($securityRecords as $row) {
        $bioId = trim($row['bio_id'] ?? '');
        if (empty($bioId)) continue;

        $name  = trim($row['employee_name'] ?? 'Security Staff');
        $email = trim($row['email'] ?? '');
        $phone = trim($row['phone'] ?? '');
        $dept  = trim($row['department'] ?? 'Security');
        $gender= trim($row['gender'] ?? '');
        $dob   = trim($row['dob'] ?? '');

        $secStmt->execute([
            ':bio_id' => $bioId,
            ':employee_name' => $name,
            ':email' => $email,
            ':phone' => $phone,
            ':department' => $dept,
            ':gender' => $gender,
            ':dob' => $dob
        ]);

        $userSecUpsert->execute([
            ':username' => $bioId,
            ':name'     => $name,
            ':email'    => $email,
            ':phone'    => $phone,
            ':pw'       => $defaultPassword
        ]);

        $staffSecUpsert->execute([
            ':bio_id' => $bioId,
            ':pw'     => $defaultPassword,
            ':name'   => $name,
            ':email'  => $email,
            ':phone'  => $phone,
            ':dept'   => $dept
        ]);

        $secCount++;
    }

    // 2. Fetch and Import Maintenance Users
    $maintRecords = fetchAllFromApi("maintenance", $apiKey, $baseUrl);
    $maintStmt = $db->prepare("
        INSERT INTO maintenance_users (bio_id, employee_name, email, phone, department, gender, dob)
        VALUES (:bio_id, :employee_name, :email, :phone, :department, :gender, :dob)
        ON DUPLICATE KEY UPDATE
            employee_name = VALUES(employee_name),
            email = VALUES(email),
            phone = VALUES(phone),
            department = VALUES(department),
            gender = VALUES(gender),
            dob = VALUES(dob)
    ");

    $userMaintUpsert = $db->prepare("
        INSERT INTO users (username, full_name, email, phone_number, role, password, Designation, Status, is_active, Institution)
        VALUES (:username, :name, :email, :phone, 'maintenance', :pw, 'Maintenance Staff', '1', 1, 'SIMATS')
        ON DUPLICATE KEY UPDATE
            full_name = VALUES(full_name),
            email = VALUES(email),
            phone_number = VALUES(phone_number),
            role = 'maintenance',
            Status = '1',
            is_active = 1
    ");

    $staffMaintUpsert = $db->prepare("
        INSERT INTO staff_users (bio_id, password, name, email, phone, dept, desig, role)
        VALUES (:bio_id, :pw, :name, :email, :phone, :dept, 'Maintenance Staff', 'maintenance')
        ON DUPLICATE KEY UPDATE
            name = VALUES(name),
            email = VALUES(email),
            phone = VALUES(phone),
            role = 'maintenance'
    ");

    $maintCount = 0;
    foreach ($maintRecords as $row) {
        $bioId = trim($row['bio_id'] ?? '');
        if (empty($bioId)) continue;

        $name  = trim($row['employee_name'] ?? 'Maintenance Staff');
        $email = trim($row['email'] ?? '');
        $phone = trim($row['phone'] ?? '');
        $dept  = trim($row['department'] ?? 'Maintenance');
        $gender= trim($row['gender'] ?? '');
        $dob   = trim($row['dob'] ?? '');

        $maintStmt->execute([
            ':bio_id' => $bioId,
            ':employee_name' => $name,
            ':email' => $email,
            ':phone' => $phone,
            ':department' => $dept,
            ':gender' => $gender,
            ':dob' => $dob
        ]);

        $userMaintUpsert->execute([
            ':username' => $bioId,
            ':name'     => $name,
            ':email'    => $email,
            ':phone'    => $phone,
            ':pw'       => $defaultPassword
        ]);

        $staffMaintUpsert->execute([
            ':bio_id' => $bioId,
            ':pw'     => $defaultPassword,
            ':name'   => $name,
            ':email'  => $email,
            ':phone'  => $phone,
            ':dept'   => $dept
        ]);

        $maintCount++;
    }

    echo json_encode([
        'success' => true,
        'message' => 'Security and Maintenance users imported successfully',
        'counts' => [
            'security_imported' => $secCount,
            'maintenance_imported' => $maintCount
        ]
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage()
    ]);
}
?>
