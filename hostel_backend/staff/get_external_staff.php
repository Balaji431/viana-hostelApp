<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/api_config.php';

// Role classification configurations (case-insensitive keywords)
$SECURITY_KEYWORDS = ['security', 'guard', 'watchman', 'patrol'];
$MAINTENANCE_KEYWORDS = ['maintenance', 'house keeping', 'plumber', 'electrician', 'carpenter', 'cleaner', 'sweeper', 'mechanic', 'technician'];

function determineRole($department, $designation) {
    global $SECURITY_KEYWORDS, $MAINTENANCE_KEYWORDS;
    
    $combined = strtolower(trim($department . ' ' . $designation));
    
    foreach ($SECURITY_KEYWORDS as $kw) {
        if (strpos($combined, $kw) !== false) return 'security';
    }
    foreach ($MAINTENANCE_KEYWORDS as $kw) {
        if (strpos($combined, $kw) !== false) return 'maintenance';
    }
    
    // Default fallback - allow them to be assigned as warden if needed, or just return 'staff'
    return 'staff';
}

$db_class = new Database();
$db = $db_class->getConnection();

$url = EXTERNAL_EMP_API_URL;
$key = EXTERNAL_EMP_API_KEY;

if (!isset($_GET['sync']) || $_GET['sync'] !== 'true') {
    // 1. Security Users
    $sec1 = $db->query("SELECT bio_id, employee_name as name, email, phone, department, 'Security' as designation, 'security' as role FROM security_users")->fetchAll(PDO::FETCH_ASSOC);
    $sec2 = $db->query("SELECT username as bio_id, full_name as name, email, phone_number as phone, 'Security' as department, COALESCE(Designation, 'Security Guard') as designation, 'security' as role FROM users WHERE LOWER(role) = 'security'")->fetchAll(PDO::FETCH_ASSOC);
    $sec3 = $db->query("SELECT bio_id, name, email, phone, dept as department, desig as designation, 'security' as role FROM staff_users WHERE LOWER(role) = 'security'")->fetchAll(PDO::FETCH_ASSOC);

    $secList = [];
    $seenSec = [];
    foreach (array_merge($sec1, $sec2, $sec3) as $s) {
        $id = trim($s['bio_id'] ?? '');
        if (!$id || isset($seenSec[$id])) continue;
        $seenSec[$id] = true;
        $secList[] = $s;
    }

    // 2. Maintenance Users
    $maint1 = $db->query("SELECT bio_id, employee_name as name, email, phone, department, 'Maintenance' as designation, 'maintenance' as role FROM maintenance_users")->fetchAll(PDO::FETCH_ASSOC);
    $maint2 = $db->query("SELECT username as bio_id, full_name as name, email, phone_number as phone, 'Maintenance' as department, COALESCE(Designation, 'Maintenance Staff') as designation, 'maintenance' as role FROM users WHERE LOWER(role) = 'maintenance'")->fetchAll(PDO::FETCH_ASSOC);
    $maint3 = $db->query("SELECT bio_id, name, email, phone, dept as department, desig as designation, 'maintenance' as role FROM staff_users WHERE LOWER(role) = 'maintenance'")->fetchAll(PDO::FETCH_ASSOC);

    $maintList = [];
    $seenMaint = [];
    foreach (array_merge($maint1, $maint2, $maint3) as $m) {
        $id = trim($m['bio_id'] ?? '');
        if (!$id || isset($seenMaint[$id])) continue;
        $seenMaint[$id] = true;
        $maintList[] = $m;
    }

    // 3. Wardens
    $ward1 = $db->query("SELECT username as bio_id, full_name as name, email, phone_number as phone, 'Warden' as department, 'Warden' as designation, 'warden' as role FROM users WHERE LOWER(role) = 'warden'")->fetchAll(PDO::FETCH_ASSOC);
    $ward2 = $db->query("SELECT bio_id, name, email, phone, dept as department, desig as designation, 'warden' as role FROM staff_users WHERE LOWER(role) = 'warden'")->fetchAll(PDO::FETCH_ASSOC);

    $wardList = [];
    $seenWard = [];
    foreach (array_merge($ward1, $ward2) as $w) {
        $id = trim($w['bio_id'] ?? '');
        if (!$id || isset($seenWard[$id])) continue;
        $seenWard[$id] = true;
        $wardList[] = $w;
    }

    $combined_staff = array_merge($secList, $maintList, $wardList);

    echo json_encode([
        'success' => true, 
        'source' => 'local_tables',
        'data' => $combined_staff
    ]);
    exit();
}

// Fetch paginated data from external API only if ?sync=true is passed
$current_page = 1;
$total_pages = 1;
$staff_list = [];

do {
    $paged_url = $url . (strpos($url, '?') !== false ? "&page=$current_page" : "?page=$current_page");
    
    $ch = curl_init();
    curl_setopt_array($ch, [
        CURLOPT_URL => $paged_url,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 30,
        CURLOPT_SSL_VERIFYPEER => false,
        CURLOPT_USERAGENT => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        CURLOPT_HTTPHEADER => [
            "Authorization: Bearer $key",
            "X-Api-Key: $key",
            "api-key: $key",
            "token: $key",
            "X-Tunnel-Skip-Anti-Spam-Page: true"
        ]
    ]);

    $response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);

    if ($http_code != 200 || !$response) {
        // If first page fails, fallback to cache. If subsequent fail, just break and save what we have.
        if ($current_page == 1) {
            $stmt = $db->query("SELECT bio_id, name, email, phone, department, designation, role FROM staff_users WHERE is_active = 1");
            $cached_staff = $stmt->fetchAll(PDO::FETCH_ASSOC);
            
            echo json_encode([
                'success' => true, 
                'source' => 'cache (api failed)',
                'api_error' => "HTTP $http_code: $err",
                'data' => $cached_staff
            ]);
            exit();
        }
        break;
    }

    $data = json_decode($response, true);
    $page_data = $data['data'] ?? $data ?? [];
    
    if (is_array($page_data)) {
        $staff_list = array_merge($staff_list, $page_data);
    }
    
    $total_pages = $data['total_pages'] ?? 1;
    $current_page++;
    
} while ($current_page <= $total_pages);

if (empty($staff_list)) {
    echo json_encode(['success' => false, 'message' => 'No staff found or invalid API response format']);
    exit();
}

$synced_staff = [];
$default_password = password_hash('welcome123', PASSWORD_DEFAULT);

try {
    $db->beginTransaction();
    
    $upsert_stmt = $db->prepare("
        INSERT INTO staff_users (bio_id, password, name, email, phone, department, designation, role, raw_api_data)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE 
            name = VALUES(name),
            email = VALUES(email),
            phone = VALUES(phone),
            department = VALUES(department),
            designation = VALUES(designation),
            role = VALUES(role),
            raw_api_data = VALUES(raw_api_data),
            updated_at = CURRENT_TIMESTAMP
    ");

    $profile_update = $db->prepare("
        UPDATE profile 
        SET personal_phone = ?
        WHERE reg_no = ?
    ");

    foreach ($staff_list as $emp) {
        $bio_id = $emp['bio_id'] ?? $emp['id'] ?? null;
        if (!$bio_id) continue;
        
        // Prioritize employee_name over name since the external API was just updated
        $name = $emp['employee_name'] ?? $emp['name'] ?? $emp['emp_name'] ?? $bio_id;
        $email = $emp['email'] ?? null;
        $phone = $emp['phone'] ?? $emp['mobile'] ?? null;
        $dept = $emp['department'] ?? null;
        $desig = $emp['designation'] ?? null;
        
        $role = determineRole($dept, $desig);
        $raw_json = json_encode($emp);
        
        $upsert_stmt->execute([
            $bio_id,
            $default_password,
            $name,
            $email,
            $phone,
            $dept,
            $desig,
            $role,
            $raw_json
        ]);
        
        // Upsert phone in profile if needed (assuming bio_id = reg_no for staff profiles, if they have one)
        if ($phone) {
            $profile_update->execute([$phone, $bio_id]);
        }
        
        $synced_staff[] = [
            'bio_id' => $bio_id,
            'name' => $name,
            'phone' => $phone,
            'department' => $dept,
            'designation' => $desig,
            'role' => $role
        ];
    }
    
    $db->commit();
    
    echo json_encode([
        'success' => true,
        'source' => 'external_api',
        'data' => $synced_staff
    ]);

} catch (Exception $e) {
    if ($db->inTransaction()) $db->rollBack();
    echo json_encode(['success' => false, 'message' => 'DB sync error: ' . $e->getMessage()]);
}
?>
