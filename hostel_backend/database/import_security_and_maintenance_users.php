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
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            "X-API-KEY: $apiKey",
            "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
        ]);

        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($httpCode !== 200 || !$response) {
            break;
        }

        $json = json_decode($response, true);
        if ($json && isset($json['success']) && $json['success'] === true) {
            $totalPages = $json['total_pages'] ?? 1;
            $items = $json['data'] ?? [];
            $allRecords = array_merge($allRecords, $items);
            $page++;
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

    // 1. Fetch and Import Security Users (approx 129)
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

    $secCount = 0;
    foreach ($securityRecords as $row) {
        $bioId = trim($row['bio_id'] ?? '');
        if (empty($bioId)) continue;

        $secStmt->execute([
            ':bio_id' => $bioId,
            ':employee_name' => trim($row['employee_name'] ?? 'Security Staff'),
            ':email' => trim($row['email'] ?? ''),
            ':phone' => trim($row['phone'] ?? ''),
            ':department' => trim($row['department'] ?? 'Security'),
            ':gender' => trim($row['gender'] ?? ''),
            ':dob' => trim($row['dob'] ?? '')
        ]);
        $secCount++;
    }

    // 2. Fetch and Import Maintenance Users (approx 139)
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

    $maintCount = 0;
    foreach ($maintRecords as $row) {
        $bioId = trim($row['bio_id'] ?? '');
        if (empty($bioId)) continue;

        $maintStmt->execute([
            ':bio_id' => $bioId,
            ':employee_name' => trim($row['employee_name'] ?? 'Maintenance Staff'),
            ':email' => trim($row['email'] ?? ''),
            ':phone' => trim($row['phone'] ?? ''),
            ':department' => trim($row['department'] ?? 'Maintenance'),
            ':gender' => trim($row['gender'] ?? ''),
            ':dob' => trim($row['dob'] ?? '')
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
