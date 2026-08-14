<?php
require_once __DIR__ . '/../../../hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    echo "DB Connection failed!\n";
    exit(1);
}
echo "DB Connection successful!\n\n";

$test_credentials = [
    [
        'label' => 'admin login',
        'username' => 'admin1',
        'password' => 'welcome123'
    ],
    [
        'label' => 'main warden',
        'username' => 'warden1',
        'password' => 'welcome123'
    ],
    [
        'label' => 'parent login',
        'username' => 'p-2414260003',
        'password' => 'welcome123'
    ],
    [
        'label' => 'Floor warden',
        'username' => '29066',
        'password' => 'welcome123'
    ],
    [
        'label' => 'security login',
        'username' => '27034',
        'password' => 'welcome123'
    ],
    [
        'label' => 'maintenance login',
        'username' => '29699',
        'password' => 'welcome123'
    ],
    [
        'label' => 'student login',
        'username' => '192511250.simats@saveetha.com',
        'password' => '123user123'
    ],
];

echo "=========================================================\n";
echo "CHECKING CREDENTIALS VIA DATABASE & LOGIN LOGIC\n";
echo "=========================================================\n\n";

foreach ($test_credentials as $item) {
    $label = $item['label'];
    $username = $item['username'];
    $password = $item['password'];
    
    echo "---------------------------------------------------------\n";
    echo "Testing [$label] Username: '$username', Password: '$password'\n";
    
    // Check in users table
    $stmt = $db->prepare("SELECT id, username, full_name, password, role, Status FROM users WHERE username = :username OR email = :username LIMIT 1");
    $stmt->execute([':username' => $username]);
    $userRow = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if ($userRow) {
        echo "Found in `users` table:\n";
        echo "  ID: " . $userRow['id'] . "\n";
        echo "  Username: " . $userRow['username'] . "\n";
        echo "  Full Name: " . $userRow['full_name'] . "\n";
        echo "  Role: " . $userRow['role'] . "\n";
        echo "  Status: " . ($userRow['Status'] ?? 'N/A') . "\n";
        
        $pwdMatch = password_verify($password, $userRow['password']);
        if ($pwdMatch) {
            echo "  Password Verify: MATCH\n";
            
            // Check student restriction
            if (strtolower($userRow['role']) === 'student' && trim($userRow['username']) !== '192211929') {
                echo "  Login Status: BLOCKED (Students must log in using 'Sign in with Google')\n";
            } elseif (isset($userRow['Status']) && (strtolower($userRow['Status']) == 'inactive' || $userRow['Status'] == '0') && $userRow['role'] !== 'admin') {
                echo "  Login Status: BLOCKED (Account is inactive)\n";
            } else {
                echo "  Login Status: SUCCESSFUL\n";
            }
        } else {
            echo "  Password Verify: FAILED (Stored hash: " . substr($userRow['password'], 0, 15) . "...)\n";
            echo "  Login Status: FAILED (Invalid credentials)\n";
        }
    } else {
        echo "Not found in `users` table by username or email.\n";
        
        // Check in vstudy_payments
        $stmtPay = $db->prepare("SELECT * FROM vstudy_payments WHERE roll_number = :username OR email = :username LIMIT 1");
        $stmtPay->execute([':username' => $username]);
        $payRow = $stmtPay->fetch(PDO::FETCH_ASSOC);
        
        if ($payRow) {
            echo "Found in `vstudy_payments` table:\n";
            echo "  Roll Number: " . $payRow['roll_number'] . "\n";
            echo "  Student Name: " . $payRow['student_name'] . "\n";
            if ($password === 'welcome123') {
                if (trim($username) !== '192211929') {
                    echo "  Login Status: BLOCKED (Students must log in using 'Sign in with Google')\n";
                } else {
                    echo "  Login Status: SUCCESSFUL (Auto-creates student user)\n";
                }
            } else {
                echo "  Login Status: FAILED (Default password 'welcome123' expected, got '$password')\n";
            }
        } else {
            // Check in parent_users
            $p_stmt = $db->prepare("SELECT p.*, s.full_name as student_name FROM parent_users p LEFT JOIN parent_student_map psm ON (p.parent_id = psm.parent_id) LEFT JOIN users s ON (psm.student_id = s.username) WHERE LOWER(p.parent_id) = LOWER(?) LIMIT 1");
            $p_stmt->execute([$username]);
            $pRow = $p_stmt->fetch(PDO::FETCH_ASSOC);
            
            if ($pRow) {
                echo "Found in `parent_users` table:\n";
                echo "  Parent ID: " . $pRow['parent_id'] . "\n";
                $db_pass = $pRow['password'];
                $verify = false;
                if (strpos($db_pass, '$2y$') === 0) {
                    $verify = password_verify($password, $db_pass);
                } else {
                    $verify = ($password === $db_pass);
                }
                if (!$verify && $password === 'welcome123') {
                    $verify = true;
                }
                if ($verify) {
                    echo "  Login Status: SUCCESSFUL (Parent login)\n";
                } else {
                    echo "  Login Status: FAILED (Incorrect password)\n";
                }
            } else if (preg_match('/^(p-|p_|parent[-_]?)(.+)$/i', $username, $matches)) {
                $std_reg = trim($matches[2]);
                echo "Attempting dynamic parent prefix lookup for reg_no: '$std_reg'...\n";
                $s_stmt = $db->prepare("SELECT id, username, full_name FROM users WHERE LOWER(username) = LOWER(:reg) LIMIT 1");
                $s_stmt->execute([':reg' => $std_reg]);
                $s_row = $s_stmt->fetch(PDO::FETCH_ASSOC);
                if ($s_row) {
                    echo "  Found target student: " . $s_row['username'] . " (" . $s_row['full_name'] . ")\n";
                    if ($password === 'welcome123') {
                        echo "  Login Status: SUCCESSFUL (Dynamic parent creation & login)\n";
                    } else {
                        echo "  Login Status: FAILED (Incorrect password, welcome123 expected)\n";
                    }
                } else {
                    echo "  Target student '$std_reg' not found in users.\n";
                    echo "  Login Status: FAILED (User not found)\n";
                }
            } else {
                echo "  Login Status: FAILED (User not found in database)\n";
            }
        }
    }
}
