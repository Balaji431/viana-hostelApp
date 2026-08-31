<?php
/**
 * Sync Parent Emails & Details from VStudy Booked-Rooms API
 * 
 * 1. Ensures `email` and `name` columns exist in `parent_users` table.
 * 2. Fetches all pages from https://vstudy.saveetha.com/api/hostel-settings/booked-rooms/external
 * 3. Extracts Father's email (or Mother's email if Father is absent) and parent contact/name.
 * 4. Upserts into `parent_users` and links in `parent_student_map`.
 */

ini_set('display_errors', 1);
error_reporting(E_ALL);
ini_set('max_execution_time', 600);
ini_set('memory_limit', '512M');

require_once __DIR__ . '/config/database.php';
require_once __DIR__ . '/config/api_config.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    die("Database connection failed.\n");
}

echo "=== STEP 1: Ensuring columns exist in parent_users ===\n";
try {
    $cols = $db->query("SHOW COLUMNS FROM parent_users LIKE 'email'")->fetchAll();
    if (empty($cols)) {
        $db->exec("ALTER TABLE parent_users ADD COLUMN email VARCHAR(255) NULL AFTER parent_id");
        $db->exec("ALTER TABLE parent_users ADD INDEX idx_parent_email (email)");
        echo "  Added 'email' column to parent_users.\n";
    } else {
        echo "  'email' column already exists.\n";
    }

    $nameCols = $db->query("SHOW COLUMNS FROM parent_users LIKE 'name'")->fetchAll();
    if (empty($nameCols)) {
        $db->exec("ALTER TABLE parent_users ADD COLUMN name VARCHAR(255) NULL AFTER email");
        echo "  Added 'name' column to parent_users.\n";
    } else {
        echo "  'name' column already exists.\n";
    }
} catch (\Exception $e) {
    echo "  Column check/alter: " . $e->getMessage() . "\n";
}

echo "\n=== STEP 2: Fetching all students from booked-rooms/external API ===\n";

function fetchAllBookedRooms() {
    $page  = 1;
    $limit = 100;
    $all   = [];

    while (true) {
        $url = "https://vstudy.saveetha.com/api/hostel-settings/booked-rooms/external?page=$page&limit=$limit";
        $ch  = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 30,
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_HTTPHEADER     => [
                'X-Client-Id: '     . VSTUDY_CLIENT_ID,
                'X-Client-Secret: ' . VSTUDY_CLIENT_SECRET,
                'Accept: application/json',
            ],
        ]);
        $res  = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($code !== 200 || !$res) {
            echo "  API page $page returned HTTP $code. Stopping fetch.\n";
            break;
        }

        $json  = json_decode($res, true);
        $batch = $json['data'] ?? [];
        if (empty($batch)) break;

        $all = array_merge($all, $batch);
        echo "  Fetched page $page (" . count($batch) . " records, total so far: " . count($all) . ")\n";

        if (count($batch) < $limit) break;
        $page++;
        usleep(20000); // 20ms rate limit
    }
    return $all;
}

$records = fetchAllBookedRooms();
$totalRecords = count($records);
echo "Total records fetched: $totalRecords\n";

if ($totalRecords === 0) {
    die("No records fetched from API. Aborting.\n");
}

echo "\n=== STEP 3: Processing and Upserting Parent Accounts ===\n";

$pwHash = password_hash('welcome123', PASSWORD_BCRYPT);

$upsertParentStmt = $db->prepare("
    INSERT INTO parent_users (parent_id, email, name, password, contact) 
    VALUES (:parent_id, :email, :name, :password, :contact)
    ON DUPLICATE KEY UPDATE 
        email = COALESCE(NULLIF(VALUES(email), ''), email),
        name = COALESCE(NULLIF(VALUES(name), ''), name),
        contact = COALESCE(NULLIF(VALUES(contact), ''), contact)
");

$updateByStudentMapStmt = $db->prepare("
    UPDATE parent_users pu
    JOIN parent_student_map psm ON (CONVERT(pu.parent_id USING utf8mb4) = CONVERT(psm.parent_id USING utf8mb4))
    SET pu.email = :email,
        pu.name = COALESCE(NULLIF(:name, ''), pu.name),
        pu.contact = COALESCE(NULLIF(:contact, ''), pu.contact)
    WHERE psm.student_id = :student_id
");

$insertMapStmt = $db->prepare("
    INSERT INTO parent_student_map (parent_id, student_id)
    VALUES (?, ?)
    ON DUPLICATE KEY UPDATE parent_id = VALUES(parent_id)
");

$syncedCount = 0;
$emailsFoundCount = 0;

foreach ($records as $item) {
    $regNo = trim($item['registerNumber'] ?? $item['register_number'] ?? '');
    if (empty($regNo)) continue;

    $parentsList = $item['parents'] ?? [];
    $parentEmail = null;
    $parentName  = null;
    $parentPhone = null;

    if (is_array($parentsList) && !empty($parentsList)) {
        // Priority 1: Father
        foreach ($parentsList as $p) {
            $rel = strtolower(trim($p['relation'] ?? ''));
            $em  = trim($p['email'] ?? '');
            if ($rel === 'father' && !empty($em)) {
                $parentEmail = $em;
                $parentName  = trim($p['name'] ?? '');
                $parentPhone = trim($p['phone'] ?? '');
                break;
            }
        }

        // Priority 2: Mother (if Father's email was absent)
        if (empty($parentEmail)) {
            foreach ($parentsList as $p) {
                $rel = strtolower(trim($p['relation'] ?? ''));
                $em  = trim($p['email'] ?? '');
                if ($rel === 'mother' && !empty($em)) {
                    $parentEmail = $em;
                    $parentName  = trim($p['name'] ?? '');
                    $parentPhone = trim($p['phone'] ?? '');
                    break;
                }
            }
        }

        // Priority 3: Any guardian/parent with an email
        if (empty($parentEmail)) {
            foreach ($parentsList as $p) {
                $em = trim($p['email'] ?? '');
                if (!empty($em)) {
                    $parentEmail = $em;
                    $parentName  = trim($p['name'] ?? '');
                    $parentPhone = trim($p['phone'] ?? '');
                    break;
                }
            }
        }
    }

    $parentId = "P_" . $regNo;

    // Clean phone number (strip leading 91, +91, 0)
    if ($parentPhone) {
        $digits = preg_replace('/[^0-9]/', '', $parentPhone);
        if (strlen($digits) > 10 && substr($digits, 0, 2) === '91') {
            $digits = substr($digits, 2);
        }
        if (strlen($digits) === 11 && substr($digits, 0, 1) === '0') {
            $digits = substr($digits, 1);
        }
        $parentPhone = $digits;
    }


    if (!empty($parentEmail)) {
        $parentEmail = strtolower(trim($parentEmail));
        $emailsFoundCount++;
    }

    try {
        $upsertParentStmt->execute([
            ':parent_id' => $parentId,
            ':email'     => $parentEmail,
            ':name'      => $parentName,
            ':password'  => $pwHash,
            ':contact'   => $parentPhone,
        ]);

        // Also update any existing mapped entries for this student
        if (!empty($parentEmail)) {
            $updateByStudentMapStmt->execute([
                ':email'      => $parentEmail,
                ':name'       => $parentName,
                ':contact'    => $parentPhone,
                ':student_id' => $regNo,
            ]);
        }

        $insertMapStmt->execute([$parentId, $regNo]);
        $syncedCount++;
    } catch (\Exception $e) {
        // Continue on individual row errors
    }
}

echo "=== SYNC COMPLETE ===\n";
echo "Total student records processed: $syncedCount\n";
echo "Total parent emails populated: $emailsFoundCount\n";

// Show sample records with emails
$sample = $db->query("SELECT id, parent_id, email, name, contact FROM parent_users WHERE email IS NOT NULL AND email != '' LIMIT 5")->fetchAll(PDO::FETCH_ASSOC);
echo "\n=== SAMPLE UPDATED RECORDS IN parent_users ===\n";
print_r($sample);
