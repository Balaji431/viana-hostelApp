<?php
header('Content-Type: text/plain; charset=utf-8');
require_once __DIR__ . '/config/database.php';
require_once __DIR__ . '/config/api_config.php';

$db = new Database();
$pdo = $db->getConnection();

if (!$pdo) {
    die("Database connection failed!\n");
}

echo "=== IMPORTING THREE ACTIVE HOSTELS ===\n\n";

if (!function_exists('tableExists')) {
    function tableExists($pdo, $table) {
        try {
            $result = $pdo->query("SELECT 1 FROM `$table` LIMIT 1");
            return $result !== false;
        } catch (Exception $e) {
            return false;
        }
    }
}

function fetchApiRooms($groupCode) {
    $url = 'https://360.saveetha.com/api/external/get-locations-vstay.php?group_code=' . urlencode($groupCode);
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 30);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'X-API-Key: ' . VSTAAY_API_KEY,
        'X-Tunnel-Skip-Anti-Spam-Page: true'
    ]);
    $response = curl_exec($ch);
    curl_close($ch);
    if ($response) {
        $data = json_decode($response, true);
        return $data['data']['items'] ?? [];
    }
    return [];
}

function parseXlsx($filePath) {
    $zip = new ZipArchive();
    if ($zip->open($filePath) !== TRUE) {
        throw new Exception("Cannot open ZIP file: " . $filePath);
    }
    
    $sharedStrings = [];
    $stringsData = $zip->getFromName('xl/sharedStrings.xml');
    if ($stringsData) {
        $xml = simplexml_load_string($stringsData);
        if ($xml && $xml->si) {
            foreach ($xml->si as $si) {
                $sharedStrings[] = (string)$si->t;
            }
        }
    }
    
    $sheetData = $zip->getFromName('xl/worksheets/sheet1.xml');
    if (!$sheetData) {
        $zip->close();
        throw new Exception("Cannot read sheet1.xml");
    }
    
    $xml = simplexml_load_string($sheetData);
    $rows = [];
    
    if ($xml && $xml->sheetData) {
        foreach ($xml->sheetData->row as $row) {
            $rowNum = (int)$row['r'];
            $currentRow = ['_rowNum' => $rowNum];
            
            foreach ($row->c as $cell) {
                $cellRef = (string)$cell['r'];
                $cellType = (string)$cell['t'];
                preg_match('/^[A-Z]+/', $cellRef, $matches);
                $colLetter = $matches[0];
                
                $val = '';
                if (isset($cell->v)) {
                    $valIdx = (string)$cell->v;
                    if ($cellType === 's') {
                        $val = $sharedStrings[(int)$valIdx] ?? '';
                    } else {
                        $val = $valIdx;
                    }
                }
                $currentRow[$colLetter] = trim($val);
            }
            $rows[] = $currentRow;
        }
    }
    
    $zip->close();
    return $rows;
}

function normalizeRoomType($type, $hostel) {
    $type = trim($type);
    $type = preg_replace('/\s+/', ' ', $type); // Clean extra spaces
    $hostel = strtolower($hostel);
    
    if (strpos($hostel, 'noyyal') !== false) {
        if (stripos($type, '3 IN 1') !== false) {
            return 'Super Deluxe 3 IN 1 Bath Attached AC';
        }
        if (stripos($type, '4 IN 1') !== false) {
            return 'Super Deluxe 4 IN 1 Bath Attached AC';
        }
        return $type;
    }
    
    if (strpos($hostel, 'ponni') !== false) {
        $clean = strtoupper($type);
        if (strpos($clean, '3 IN 1') !== false || strpos($clean, '3 IN1') !== false) {
            return (stripos($clean, 'AC') !== false && stripos($clean, 'NON') === false) ? '3 IN 1 AC' : '3 IN 1 Non AC';
        }
        if (strpos($clean, '4 IN 1') !== false || strpos($clean, '4 IN1') !== false) {
            return (stripos($clean, 'AC') !== false && stripos($clean, 'NON') === false) ? '4 IN 1 AC' : '4 IN 1 Non AC';
        }
        if (strpos($clean, '5 IN 1') !== false || strpos($clean, '5 IN1') !== false) {
            return (stripos($clean, 'AC') !== false && stripos($clean, 'NON') === false) ? '5 IN 1 AC' : '5 IN 1 Non AC';
        }
        if (strpos($clean, '1 IN 1') !== false || strpos($clean, '1 IN1') !== false) {
            return (stripos($clean, 'AC') !== false && stripos($clean, 'NON') === false) ? '1 IN 1 AC' : '1 IN 1 Non AC';
        }
        if (strpos($clean, 'DORM 19') !== false) {
            return 'DORM 19 - Non AC';
        }
        if (strpos($clean, 'DORM 20') !== false) {
            return 'DORM 20 - Non AC';
        }
        return $type;
    }

    if (strpos($hostel, 'palar') !== false) {
        return $type;
    }
    
    return $type;
}

function getRoomAmountDetails($roomType) {
    $type = strtoupper($roomType);
    $amount = 85000.00;
    $caution = 5000.00;
    $facility = 'Non AC';
    $bathAttached = 'No';

    if (strpos($type, 'AC') !== false && strpos($type, 'NON') === false) {
        $facility = 'AC';
    }

    if (strpos($type, 'BATH ATTACHED') !== false || strpos($type, 'B ATTACHED') !== false || strpos($type, 'B AND T ATTACHED') !== false || strpos($type, 'SUPER DELUXE') !== false) {
        $bathAttached = 'Yes';
    }

    if (strpos($type, 'SUPER DELUXE 3 IN 1') !== false) {
        $amount = 170000.00;
        $caution = 10000.00;
    } elseif (strpos($type, 'SUPER DELUXE 4 IN 1') !== false) {
        $amount = 155000.00;
        $caution = 10000.00;
    } elseif (strpos($type, '4 IN 1 BATH ATTACHED AC') !== false || strpos($type, '4 IN 1 B AND T ATTACHED AC') !== false) {
        $amount = 130000.00;
        $caution = 5000.00;
    } elseif (strpos($type, '6 IN 1 BATH ATTACHED AC') !== false || strpos($type, '6 IN 1 B AND T ATTACHED AC') !== false) {
        $amount = 120000.00;
        $caution = 5000.00;
    } elseif (strpos($type, '6 IN 1 AC') !== false) {
        $amount = 115000.00;
        $caution = 5000.00;
    } elseif (strpos($type, '4 IN 1 AC') !== false) {
        $amount = 125000.00;
        $caution = 5000.00;
    } elseif (strpos($type, '8 IN 1 AC') !== false) {
        $amount = 110000.00;
        $caution = 5000.00;
    } elseif (strpos($type, '3 IN 1 NON AC') !== false || strpos($type, '3 IN 1 NON-AC') !== false) {
        $amount = 90000.00;
        $caution = 5000.00;
    } elseif (strpos($type, '4 IN 1 NON AC') !== false || strpos($type, '4 IN 1 NON-AC') !== false) {
        $amount = 89000.00;
        $caution = 5000.00;
    } elseif (strpos($type, '5 IN 1 NON AC') !== false || strpos($type, '5 IN 1 NON-AC') !== false) {
        $amount = 88000.00;
        $caution = 5000.00;
    } elseif (strpos($type, '6 IN 1 NON AC') !== false || strpos($type, '6 IN 1 NON-AC') !== false) {
        $amount = 87000.00;
        $caution = 5000.00;
    } elseif (strpos($type, '7 IN 1 NON AC') !== false || strpos($type, '7 IN 1 NON-AC') !== false) {
        $amount = 86000.00;
        $caution = 5000.00;
    } elseif (strpos($type, '2 IN 1 NON AC') !== false || strpos($type, 'DOUBLE NON AC') !== false) {
        $amount = 95000.00;
        $caution = 5000.00;
    } elseif (strpos($type, '1 IN 1 NON AC') !== false || strpos($type, '1 IN 1 NON-AC') !== false) {
        $amount = 100000.00;
        $caution = 5000.00;
    } elseif (strpos($type, '3 IN 1 AC') !== false) {
        $amount = 135000.00;
        $caution = 5000.00;
    } elseif (strpos($type, 'DORM') !== false) {
        $amount = 70000.00;
        $caution = 5000.00;
    }

    return [$amount, $caution, $facility, $bathAttached];
}

function parseDate($dateStr) {
    if (empty($dateStr)) return null;
    $dateStr = trim($dateStr);
    $dateStr = str_replace(['/', '.'], '-', $dateStr);
    $parts = explode('-', $dateStr);
    if (count($parts) === 3) {
        $d = (int)$parts[0];
        $m = (int)$parts[1];
        $y = (int)$parts[2];
        if ($y < 100) {
            $y = 2000 + $y;
        }
        
        // Month boundary validation
        if ($m < 1 || $m > 12) return null;
        
        // Day boundary validation
        $daysInMonths = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        $maxDays = $daysInMonths[$m - 1];
        
        // Handle leap year for February
        if ($m === 2) {
            $isLeap = ($y % 4 === 0 && ($y % 100 !== 0 || $y % 400 === 0));
            if ($isLeap) $maxDays = 29;
            else $maxDays = 28;
        }
        
        if ($d < 1 || $d > $maxDays) {
            return null;
        }
        
        $dStr = str_pad($d, 2, '0', STR_PAD_LEFT);
        $mStr = str_pad($m, 2, '0', STR_PAD_LEFT);
        return "$y-$mStr-$dStr";
    }
    return null;
}

$filesConfig = [
    'Noyyal' => [
        'path' => 'HOSTEL FINAL - NOYYAL.xlsx',
        'hostel_name' => 'Noyyal Hostel',
        'hostel_type' => 'Boys',
        'reg_col' => 'C',
        'name_col' => 'D',
        'room_col' => 'H',
        'room_type_col' => 'G',
        'inst_col' => 'E',
        'course_col' => 'F',
        'start_row' => 2,
        'building_code' => 'T22',
        'renewal_date_col' => 'I',
        'years_paid_col' => null
    ],
    'Krishna' => [
        'path' => 'HOSTEL - KRISHNA.xlsx',
        'hostel_name' => 'Krishna Hostel',
        'hostel_type' => 'Boys',
        'reg_col' => 'C',
        'name_col' => 'D',
        'room_col' => 'G',
        'room_type_col' => 'F',
        'inst_col' => null,
        'course_col' => 'E',
        'start_row' => 2,
        'building_code' => 'T-30',
        'renewal_date_col' => 'H',
        'years_paid_col' => null
    ],
    'Ponni' => [
        'path' => 'HOSTEL PONNI.xlsx',
        'hostel_name' => 'Ponni Hostel',
        'hostel_type' => 'Girls',
        'reg_col' => 'D',
        'name_col' => 'C',
        'room_col' => 'H',
        'room_type_col' => 'G',
        'inst_col' => 'E',
        'course_col' => 'F',
        'start_row' => 2,
        'building_code' => 'T09',
        'renewal_date_col' => 'I',
        'years_paid_col' => 'L'
    ],
    'Palar' => [
        'path' => 'HOSTEL FINAL - PALAR.xlsx',
        'hostel_name' => 'Palar Hostel',
        'hostel_type' => 'Boys',
        'reg_col' => 'D',
        'name_col' => 'C',
        'room_col' => 'G',
        'room_type_col' => 'F',
        'inst_col' => 'E',
        'course_col' => 'E',
        'start_row' => 3,
        'building_code' => 'T10',
        'renewal_date_col' => 'H',
        'years_paid_col' => 'J'
    ],
    'Vaigai' => [
        'path' => 'HOSTEL -VAIGAI.xlsx',
        'hostel_name' => 'Vaigai Hostel',
        'hostel_type' => 'Girls',
        'reg_col' => 'C',
        'name_col' => 'D',
        'room_col' => 'G',
        'room_type_col' => 'F',
        'inst_col' => 'E',
        'course_col' => 'E',
        'start_row' => 2,
        'building_code' => 'T-32',
        'renewal_date_col' => 'H',
        'years_paid_col' => null
    ]
];

try {
    $pdo->beginTransaction();

    echo "=== DISABLING FOREIGN KEY CHECKS ===\n";
    $pdo->exec("SET FOREIGN_KEY_CHECKS = 0");

    // 1. Check/Add relationship columns
    echo "Checking profile.user_id column...\n";
    $stmt = $pdo->query("SHOW COLUMNS FROM `profile` LIKE 'user_id'");
    if (!$stmt->fetch()) {
        $pdo->exec("ALTER TABLE `profile` ADD COLUMN `user_id` INT NULL AFTER `reg_no`");
        $pdo->exec("ALTER TABLE `profile` ADD INDEX `idx_profile_user_id` (`user_id`)");
    }

    echo "Checking room_master.hostel_room_id column...\n";
    $stmt = $pdo->query("SHOW COLUMNS FROM `room_master` LIKE 'hostel_room_id'");
    if (!$stmt->fetch()) {
        $pdo->exec("ALTER TABLE `room_master` ADD COLUMN `hostel_room_id` INT NULL AFTER `room_code`");
        $pdo->exec("ALTER TABLE `room_master` ADD INDEX `idx_room_master_hostel_room_id` (`hostel_room_id`)");
    }

    // 2. Backup existing manually created staff & parent records
    echo "Backing up staff and parent records...\n";
    $staffUsers = $pdo->query("SELECT * FROM `users` WHERE `role` IN ('admin', 'warden') ORDER BY `id`")->fetchAll(PDO::FETCH_ASSOC);
    if (empty($staffUsers)) {
        echo "No staff users found in current table, loading hardcoded fallback...\n";
        $staffUsers = [
            [
                'username' => 'admin1',
                'password' => '$2y$10$M8IpO8.87xjrtzu2x6.NoeYRdQd/LHBBEzIF2OBU7JF08rLpCpnqu',
                'full_name' => 'System Admin',
                'role' => 'admin',
                'email' => null,
                'phone_number' => '9878690765',
                'Campus' => 'SIMATS1',
                'Institution' => null,
                'HostelName' => null,
                'HostelType' => 'Girls',
                'RoomType' => null,
                'RoomId' => null,
                'Academic' => '1st Year',
                'conduct' => 'Satisfactory',
                'Status' => 'active',
                'fcm_token' => 'e29VTT14TLF2w34njnL82B:APA91bFmK8Zmeet0772ANaXpax0SM1iJyXr9FcE-cuSVx-cWZ6r733ZK5PgXK-PYAPldUZhcSZ1q2rVOf_WtdhtPI-DPzzJtMgVSgKe18DOQlzb4wK9-k3k'
            ],
            [
                'username' => 'warden1',
                'password' => '$2y$10$hk6ENKqC1vXmLF1dRtxFIu/ej8r7z1S5U2nhvHnkTI2CD4mRk9AXG',
                'full_name' => 'Venkatesh',
                'role' => 'warden',
                'email' => null,
                'phone_number' => '9676607394',
                'Campus' => 'SIMATS1',
                'Institution' => 'Main Warden',
                'HostelName' => null,
                'HostelType' => 'Girls',
                'RoomType' => null,
                'RoomId' => null,
                'Academic' => '1st Year',
                'conduct' => 'Poor',
                'Status' => 'active',
                'fcm_token' => null
            ],
            [
                'username' => 'rajesh1',
                'password' => '$2y$10$hk6ENKqC1vXmLF1dRtxFIu/ej8r7z1S5U2nhvHnkTI2CD4mRk9AXG',
                'full_name' => 'Rajesh Kumar',
                'role' => 'warden',
                'email' => 'rajesh@warden.com',
                'phone_number' => '8978690147',
                'Campus' => 'SIMATS1',
                'Institution' => null,
                'HostelName' => null,
                'HostelType' => 'Girls',
                'RoomType' => null,
                'RoomId' => null,
                'Academic' => '1st Year',
                'conduct' => 'Good',
                'Status' => 'active',
                'fcm_token' => null
            ],
            [
                'username' => 'anitha1',
                'password' => '$2y$10$hk6ENKqC1vXmLF1dRtxFIu/ej8r7z1S5U2nhvHnkTI2CD4mRk9AXG',
                'full_name' => 'Anitha S',
                'role' => 'warden',
                'email' => 'anitha@warden.com',
                'phone_number' => '9876543211',
                'Campus' => 'SIMATS1',
                'Institution' => null,
                'HostelName' => null,
                'HostelType' => 'Girls',
                'RoomType' => null,
                'RoomId' => null,
                'Academic' => '1st Year',
                'conduct' => 'Good',
                'Status' => 'active',
                'fcm_token' => null
            ],
            [
                'username' => 'suresh1',
                'password' => '$2y$10$hk6ENKqC1vXmLF1dRtxFIu/ej8r7z1S5U2nhvHnkTI2CD4mRk9AXG',
                'full_name' => 'Suresh V',
                'role' => 'warden',
                'email' => 'suresh@warden.com',
                'phone_number' => '9876543212',
                'Campus' => 'SIMATS1',
                'Institution' => null,
                'HostelName' => null,
                'HostelType' => 'Girls',
                'RoomType' => null,
                'RoomId' => null,
                'Academic' => '1st Year',
                'conduct' => 'Good',
                'Status' => 'active',
                'fcm_token' => null
            ],
            [
                'username' => '192211929',
                'password' => '$2y$10$hk6ENKqC1vXmLF1dRtxFIu/ej8r7z1S5U2nhvHnkTI2CD4mRk9AXG',
                'full_name' => 'Balaji ',
                'role' => 'warden',
                'email' => null,
                'phone_number' => '7995376840',
                'Campus' => 'SIMATS1',
                'Institution' => null,
                'HostelName' => null,
                'HostelType' => 'Girls',
                'RoomType' => null,
                'RoomId' => null,
                'Academic' => '1st Year',
                'conduct' => 'Good',
                'fcm_token' => 'epE1Ecm9R5yz8tJWtubPj3:APA91bHk0kNO4Phvx4i23raM40NxA6mBmxlwXPlyCn9ybRNy9_LdE5Q3WEhv3mcXuVYNUlbJWUKy0I2prxBhzuyWTHv_TCFzbUQb_zdXIY705YlY_GALpGE'
            ],
            [
                'username' => '192224241',
                'password' => '$2y$10$hk6ENKqC1vXmLF1dRtxFIu/ej8r7z1S5U2nhvHnkTI2CD4mRk9AXG',
                'full_name' => 'Vishal',
                'role' => 'warden',
                'email' => null,
                'phone_number' => '1234567890',
                'Campus' => 'SIMATS1',
                'Institution' => null,
                'HostelName' => null,
                'HostelType' => 'Girls',
                'RoomType' => null,
                'RoomId' => null,
                'Academic' => '1st Year',
                'conduct' => 'Good',
                'Status' => 'active',
                'fcm_token' => null
            ],
            [
                'username' => '123456',
                'password' => '$2y$10$hk6ENKqC1vXmLF1dRtxFIu/ej8r7z1S5U2nhvHnkTI2CD4mRk9AXG',
                'full_name' => 'Gautham',
                'role' => 'warden',
                'email' => null,
                'phone_number' => '8122465353',
                'Campus' => 'SIMATS1',
                'Institution' => null,
                'HostelName' => null,
                'HostelType' => 'Girls',
                'RoomType' => null,
                'RoomId' => null,
                'Academic' => '1st Year',
                'conduct' => 'Good',
                'Status' => 'active',
                'fcm_token' => null
            ],
            [
                'username' => 'shesha1',
                'password' => '$2y$10$hk6ENKqC1vXmLF1dRtxFIu/ej8r7z1S5U2nhvHnkTI2CD4mRk9AXG',
                'full_name' => 'shesha',
                'role' => 'warden',
                'email' => null,
                'phone_number' => '7995376849',
                'Campus' => 'SIMATS1',
                'Institution' => null,
                'HostelName' => null,
                'HostelType' => 'Girls',
                'RoomType' => null,
                'RoomId' => null,
                'Academic' => '1st Year',
                'conduct' => 'Good',
                'Status' => 'active',
                'fcm_token' => null
            ]
        ];
    }
    $parentUsers = $pdo->query("SELECT * FROM `parent_users` ORDER BY `id`")->fetchAll(PDO::FETCH_ASSOC);
    $parentStudentMap = $pdo->query("SELECT * FROM `parent_student_map` ORDER BY `id`")->fetchAll(PDO::FETCH_ASSOC);

    // Backup other dynamic tables to remap their student/room ID references later
    $oldComplaints = tableExists($pdo, 'complaints') ? $pdo->query("SELECT * FROM `complaints`")->fetchAll(PDO::FETCH_ASSOC) : [];
    $oldFeedbacks = tableExists($pdo, 'feedbacks') ? $pdo->query("SELECT * FROM `feedbacks`")->fetchAll(PDO::FETCH_ASSOC) : [];
    $oldRenewals = tableExists($pdo, 'renewal_requests') ? $pdo->query("SELECT * FROM `renewal_requests`")->fetchAll(PDO::FETCH_ASSOC) : [];
    $oldRoomChangeRequests = tableExists($pdo, 'room_change_requests') ? $pdo->query("SELECT * FROM `room_change_requests`")->fetchAll(PDO::FETCH_ASSOC) : [];
    $oldRoomAllocations = tableExists($pdo, 'room_allocations') ? $pdo->query("SELECT * FROM `room_allocations`")->fetchAll(PDO::FETCH_ASSOC) : [];
    $oldAllocationRequests = tableExists($pdo, 'allocation_requests') ? $pdo->query("SELECT * FROM `allocation_requests`")->fetchAll(PDO::FETCH_ASSOC) : [];

    // Keep map of old user ID -> register no
    $oldUserMap = $pdo->query("SELECT id, username FROM `users`")->fetchAll(PDO::FETCH_KEY_PAIR);
    // Keep map of old room ID -> room code
    $oldRoomMap = $pdo->query("SELECT id, room_code FROM `hostel_rooms`")->fetchAll(PDO::FETCH_KEY_PAIR);

    // 3. Clear tables
    echo "Clearing active database tables...\n";
    $tablesToClear = ['users', 'profile', 'hostel_rooms', 'room_master', 'parent_users', 'parent_student_map', 'hostel_type'];
    foreach ($tablesToClear as $tbl) {
        $pdo->exec("DELETE FROM `$tbl`");
        $pdo->exec("ALTER TABLE `$tbl` AUTO_INCREMENT = 1");
    }

    // 4. Populate hostel_type
    echo "Populating hostel_type...\n";
    $stmtHostelType = $pdo->prepare("
        INSERT INTO hostel_type (campus, hostel_name, hostel_type, building_code)
        VALUES (:campus, :hostel_name, :hostel_type, :building_code)
    ");
    
    $hostelIds = [];
    foreach ($filesConfig as $key => $conf) {
        $stmtHostelType->execute([
            ':campus' => 'Thandalam Campus',
            ':hostel_name' => $conf['hostel_name'],
            ':hostel_type' => $conf['hostel_type'],
            ':building_code' => $conf['building_code']
        ]);
        $hostelIds[$key] = $pdo->lastInsertId();
        echo "Inserted Hostel: {$conf['hostel_name']} with ID: {$hostelIds[$key]}\n";
    }

    // 5. Parse sheets and group rooms & students
    $roomsData = []; // room_code => room_details
    $studentsData = []; // reg_no => student_details

    foreach ($filesConfig as $key => $conf) {
        $path = __DIR__ . '/' . $conf['path'];
        echo "Parsing Excel: $path...\n";
        $rows = parseXlsx($path);
        
        foreach ($rows as $row) {
            if ($row['_rowNum'] < $conf['start_row']) {
                continue;
            }
            
            $regNo = trim($row[$conf['reg_col']] ?? '');
            $fullName = trim($row[$conf['name_col']] ?? '');
            $roomCode = trim($row[$conf['room_col']] ?? '');
            $rawRoomType = trim($row[$conf['room_type_col']] ?? '');
            $institution = $conf['inst_col'] ? trim($row[$conf['inst_col']] ?? '') : 'SIMATS';
            $course = trim($row[$conf['course_col']] ?? '');
            // Calculate valid_from and valid_to based on renewal_date_col and years_paid_col
            $rawDate = isset($row[$conf['renewal_date_col']]) ? trim($row[$conf['renewal_date_col']]) : '';
            $parsedDate = parseDate($rawDate);
            if (!$parsedDate) {
                $parsedDate = '2026-06-01'; // Fallback
            }

            // Determine years paid
            $years = 1;
            if ($conf['years_paid_col'] && isset($row[$conf['years_paid_col']])) {
                $jVal = trim($row[$conf['years_paid_col']]);
                if (preg_match('/(\d+)\s*Year/i', $jVal, $matches)) {
                    $years = (int)$matches[1];
                } elseif (stripos($jVal, 'one') !== false) {
                    $years = 1;
                } elseif (stripos($jVal, 'two') !== false) {
                    $years = 2;
                } elseif (stripos($jVal, 'three') !== false) {
                    $years = 3;
                }
            }

            if ($conf['years_paid_col'] === null) {
                // For Krishna, Noyyal, and Vaigai: Date of Fee Renewal is the renewal due date (valid_to)
                $validTo = $parsedDate;
                $date = new DateTime($validTo);
                $date->modify("-1 year");
                $validFrom = $date->format('Y-m-d');
            } else {
                // For Ponni and Palar: Date of Fee Renewal is the check-in date (valid_from)
                $validFrom = $parsedDate;
                $date = new DateTime($validFrom);
                $date->modify("+$years years");
                $validTo = $date->format('Y-m-d');
            }

            if (empty($roomCode)) {
                continue;
            }

            // Clean & normalize roomCode
            $roomCode = str_replace('=', '-', $roomCode);
            $roomCode = str_replace(' ', '-', $roomCode);
            $roomCode = preg_replace('/-+/', '-', $roomCode);

            $normRoomType = normalizeRoomType($rawRoomType, $conf['hostel_name']);

            // Compile unique room entries
            if (!isset($roomsData[$roomCode])) {
                $roomsData[$roomCode] = [
                    'hostel_key' => $key,
                    'room_code' => $roomCode,
                    'room_type' => $normRoomType,
                    'beds' => [],
                    'occupied_count' => 0
                ];
            }
            
            // Occupied definition:
            // - Student Name exists, is NOT NULL, is NOT EMPTY, is NOT "VACANT"
            // - Registration Number exists, is NOT NULL, is NOT EMPTY, is NOT "VACANT"
            $nameClean = trim($fullName);
            $regClean  = trim($regNo);
            
            $isOccupied = (
                $nameClean !== '' && 
                strcasecmp($nameClean, 'vacant') !== 0 && 
                $regClean !== '' && 
                strcasecmp($regClean, 'vacant') !== 0 &&
                stripos($nameClean, 'warden') === false &&
                stripos($regClean, 'warden') === false
            );
            $isVacant = !$isOccupied;
            
            $roomsData[$roomCode]['beds'][] = [
                'reg_no' => $regNo,
                'full_name' => $fullName,
                'is_vacant' => $isVacant
            ];

            if ($isOccupied) {
                $roomsData[$roomCode]['occupied_count']++;
                
                // Save student record
                $studentsData[$regNo] = [
                    'reg_no' => $regNo,
                    'full_name' => $fullName,
                    'institution' => $institution ?: 'SIMATS',
                    'course' => $course,
                    'hostel_name' => $conf['hostel_name'],
                    'hostel_type' => $conf['hostel_type'],
                    'room_type' => $normRoomType,
                    'room_code' => $roomCode,
                    'valid_from' => $validFrom,
                    'valid_to' => $validTo
                ];
            }
        }
    }


    // 6. Populate hostel_rooms and room_master
    echo "Populating hostel_rooms and room_master...\n";
    
    $stmtRoom = $pdo->prepare("
        INSERT INTO hostel_rooms (
            hostel_id, campus, campus_code, hostel_name, building_code, hostel_type,
            room_type, location_name, floor_code, floor, room_no, wing_code, room_code,
            facility, bath_attached, amount, caution_dept, total_capacity, available_rooms, occupied_rooms
        ) VALUES (
            :hostel_id, 'Thandalam Campus', 'TC', :hostel_name, :building_code, :hostel_type,
            :room_type, :location_name, :floor_code, :floor, :room_no, :wing_code, :room_code,
            :facility, :bath_attached, :amount, :caution_dept, :total_capacity, :available_rooms, :occupied_rooms
        )
    ");

    $stmtMaster = $pdo->prepare("
        INSERT INTO room_master (
            location_name, building_code, floor_no, block_no, room_no, room_code, hostel_room_id, room_type, room_capacity
        ) VALUES (
            :location_name, :building_code, :floor_no, :block_no, :room_no, :room_code, :hostel_room_id, :room_type, :room_capacity
        )
    ");

    $newRoomsMap = []; // room_code => new_room_id

    foreach ($roomsData as $roomCode => $r) {
        $conf = $filesConfig[$r['hostel_key']];
        $totalCapacity = count($r['beds']);
        $occupied = $r['occupied_count'];
        $available = $totalCapacity - $occupied;

        // Final Validation Gate
        if (($occupied + $available) !== $totalCapacity) {
            throw new Exception("Validation Error: Room Code '{$roomCode}' has total_capacity = {$totalCapacity}, occupied_rooms = {$occupied}, and available_rooms = {$available}. They do not sum up correctly!");
        }
        
        list($amount, $caution, $facility, $bathAttached) = getRoomAmountDetails($r['room_type']);

        // Parse floor, wing, room number from code (e.g. T22-F04-W0-R01 or T-30-F00-WA0-R01)
        $parts = explode('-', $roomCode);
        if (count($parts) === 5) {
            $floorCode = $parts[2];
            $wingCode = $parts[3];
            $roomNo = $parts[4];
        } else {
            $floorCode = $parts[1] ?? 'F00';
            $wingCode = $parts[2] ?? 'W0';
            $roomNo = $parts[3] ?? 'R01';
        }

        $floorNo = $floorCode;
        switch (strtoupper($floorCode)) {
            case 'F00': $floorNo = 'Ground'; break;
            case 'F01': $floorNo = 'First'; break;
            case 'F02': $floorNo = 'Second'; break;
            case 'F03': $floorNo = 'Third'; break;
            case 'F04': $floorNo = 'Fourth'; break;
            case 'F05': $floorNo = 'Fifth'; break;
            case 'F06': $floorNo = 'Sixth'; break;
            case 'F07': $floorNo = 'Seventh'; break;
            case 'F08': $floorNo = 'Eighth'; break;
            case 'F09': $floorNo = 'Ninth'; break;
            case 'F10': $floorNo = 'Tenth'; break;
        }

        $locationName = "{$conf['hostel_name']} {$floorNo} Floor {$roomNo}";

        // Insert Room
        $stmtRoom->execute([
            ':hostel_id' => $hostelIds[$r['hostel_key']],
            ':hostel_name' => $conf['hostel_name'],
            ':building_code' => $conf['building_code'],
            ':hostel_type' => $conf['hostel_type'],
            ':room_type' => $r['room_type'],
            ':location_name' => $locationName,
            ':floor_code' => $floorCode,
            ':floor' => $floorNo,
            ':room_no' => $roomNo,
            ':wing_code' => $wingCode,
            ':room_code' => $roomCode,
            ':facility' => $facility,
            ':bath_attached' => $bathAttached,
            ':amount' => $amount,
            ':caution_dept' => $caution,
            ':total_capacity' => $totalCapacity,
            ':available_rooms' => $available,
            ':occupied_rooms' => $occupied
        ]);
        
        $newRoomId = $pdo->lastInsertId();
        $newRoomsMap[$roomCode] = $newRoomId;

        // Insert Room Master
        $stmtMaster->execute([
            ':location_name' => $locationName,
            ':building_code' => $conf['building_code'],
            ':floor_no' => $floorNo,
            ':block_no' => $wingCode,
            ':room_no' => $roomNo,
            ':room_code' => $roomCode,
            ':hostel_room_id' => $newRoomId,
            ':room_type' => $r['room_type'],
            ':room_capacity' => $totalCapacity
        ]);
    }
    echo "Inserted " . count($roomsData) . " unique rooms into hostel_rooms and room_master.\n";

    // 7. Insert Staff and Admins
    echo "Restoring staff and admin users...\n";
    $stmtUser = $pdo->prepare("
        INSERT INTO users (
            username, password, full_name, role, email, phone_number, Campus, Institution, HostelName, HostelType, RoomType, RoomId, Academic, conduct, Status, fcm_token
        ) VALUES (
            :username, :password, :full_name, :role, :email, :phone_number, :campus, :institution, :hostel_name, :hostel_type, :room_type, :room_id, :academic, :conduct, :status, :fcm_token
        )
    ");

    foreach ($staffUsers as $s) {
        $stmtUser->execute([
            ':username' => $s['username'],
            ':password' => $s['password'],
            ':full_name' => $s['full_name'],
            ':role' => $s['role'],
            ':email' => $s['email'],
            ':phone_number' => $s['phone_number'] ?? null,
            ':campus' => $s['Campus'],
            ':institution' => $s['Institution'],
            ':hostel_name' => $s['HostelName'],
            ':hostel_type' => $s['HostelType'],
            ':room_type' => $s['RoomType'],
            ':room_id' => $s['RoomId'],
            ':academic' => $s['Academic'],
            ':conduct' => $s['conduct'],
            ':status' => $s['Status'] ?? '1',
            ':fcm_token' => $s['fcm_token']
        ]);
    }

    // 8. Insert Students and Profiles
    echo "Populating student users and profiles...\n";
    
    $stmtProfile = $pdo->prepare("
        INSERT INTO profile (
            user_id, reg_no, full_name, institution, hostel_name, current_room_id, room_allocation, valid_from, valid_to, check_in_date, renewal_date
        ) VALUES (
            :user_id, :reg_no, :full_name, :institution, :hostel_name, :current_room_id, :room_allocation, :valid_from, :valid_to, :check_in_date, :renewal_date
        )
    ");

    $defaultPasswordHash = '$2y$10$hk6ENKqC1vXmLF1dRtxFIu/ej8r7z1S5U2nhvHnkTI2CD4mRk9AXG'; // hash for welcome123

    foreach ($studentsData as $regNo => $st) {
        $roomCode = $st['room_code'];
        $roomId = $newRoomsMap[$roomCode] ?? null;

        // Insert Student User
        $stmtUser->execute([
            ':username' => $st['reg_no'],
            ':password' => $defaultPasswordHash,
            ':full_name' => $st['full_name'],
            ':role' => 'student',
            ':email' => strtolower(str_replace(' ', '', $st['full_name'])) . '@saveetha.com',
            ':phone_number' => null,
            ':campus' => 'Thandalam Campus',
            ':institution' => $st['institution'],
            ':hostel_name' => $st['hostel_name'],
            ':hostel_type' => $st['hostel_type'],
            ':room_type' => $st['room_type'],
            ':room_id' => $roomId,
            ':academic' => $st['course'],
            ':conduct' => 'Good',
            ':status' => '1',
            ':fcm_token' => null
        ]);
        
        $newUserId = $pdo->lastInsertId();

        // Insert Student Profile
        $stmtProfile->execute([
            ':user_id' => $newUserId,
            ':reg_no' => $st['reg_no'],
            ':full_name' => $st['full_name'],
            ':institution' => $st['institution'],
            ':hostel_name' => $st['hostel_name'],
            ':current_room_id' => $roomId,
            ':room_allocation' => $roomCode,
            ':valid_from' => $st['valid_from'],
            ':valid_to' => $st['valid_to'],
            ':check_in_date' => $st['valid_from'],
            ':renewal_date' => $st['valid_to']
        ]);
    }
    echo "Inserted " . count($studentsData) . " students into users and profiles.\n";

    // 9. Re-insert Parent Users and maps
    echo "Restoring parent records...\n";
    $stmtParentUser = $pdo->prepare("
        INSERT INTO parent_users (parent_id, password, contact, fcm_token)
        VALUES (:parent_id, :password, :contact, :fcm_token)
    ");
    foreach ($parentUsers as $pu) {
        $stmtParentUser->execute([
            ':parent_id' => $pu['parent_id'],
            ':password' => $pu['password'],
            ':contact' => $pu['contact'],
            ':fcm_token' => $pu['fcm_token']
        ]);
    }

    $stmtParentMap = $pdo->prepare("
        INSERT INTO parent_student_map (parent_id, student_id)
        VALUES (:parent_id, :student_id)
    ");
    foreach ($parentStudentMap as $pm) {
        $stmtParentMap->execute([
            ':parent_id' => $pm['parent_id'],
            ':student_id' => $pm['student_id']
        ]);
    }

    // 10. Update logical table relations (e.g. dynamic foreign keys)
    echo "Re-mapping historical relationships...\n";
    
    // User old-to-new ID mapping
    $newUsersList = $pdo->query("SELECT id, username FROM `users`")->fetchAll(PDO::FETCH_ASSOC);
    $newUserMap = array_column($newUsersList, 'id', 'username');
    
    $userIdMapping = [];
    foreach ($oldUserMap as $oldId => $username) {
        if (isset($newUserMap[$username])) {
            $userIdMapping[$oldId] = $newUserMap[$username];
        }
    }

    // Room old-to-new ID mapping
    $newRoomsList = $pdo->query("SELECT id, room_code FROM `hostel_rooms`")->fetchAll(PDO::FETCH_ASSOC);
    $newRoomIdMap = array_column($newRoomsList, 'id', 'room_code');

    $roomIdMapping = [];
    foreach ($oldRoomMap as $oldId => $roomCode) {
        if (isset($newRoomIdMap[$roomCode])) {
            $roomIdMapping[$oldId] = $newRoomIdMap[$roomCode];
        }
    }

    // Restore dynamic tables dynamically to prevent column mismatch failures
    $dynamicTables = [];
    if (tableExists($pdo, 'complaints')) $dynamicTables['complaints'] = $oldComplaints;
    if (tableExists($pdo, 'feedbacks')) $dynamicTables['feedbacks'] = $oldFeedbacks;
    if (tableExists($pdo, 'renewal_requests')) $dynamicTables['renewal_requests'] = $oldRenewals;
    if (tableExists($pdo, 'room_change_requests')) $dynamicTables['room_change_requests'] = $oldRoomChangeRequests;
    if (tableExists($pdo, 'room_allocations')) $dynamicTables['room_allocations'] = $oldRoomAllocations;
    if (tableExists($pdo, 'allocation_requests')) $dynamicTables['allocation_requests'] = $oldAllocationRequests;

    foreach ($dynamicTables as $tableName => $recordsList) {
        if (empty($recordsList)) {
            continue;
        }

        // Fetch columns of the table
        $columns = [];
        $stmtCols = $pdo->query("DESCRIBE `$tableName`");
        while ($colRow = $stmtCols->fetch(PDO::FETCH_ASSOC)) {
            $columns[] = $colRow['Field'];
        }

        // Clear the table
        $pdo->exec("DELETE FROM `$tableName`");

        // Build dynamically bound query
        $colsStr = implode('`, `', $columns);
        $placeholders = implode(', ', array_map(function($c) { return ":$c"; }, $columns));
        $insertSql = "INSERT INTO `$tableName` (`$colsStr`) VALUES ($placeholders)";
        $stmtRestore = $pdo->prepare($insertSql);

        foreach ($recordsList as $row) {
            // Remap references
            if (array_key_exists('student_id', $row)) {
                $row['student_id'] = $userIdMapping[$row['student_id']] ?? null;
                if ($row['student_id'] === null) continue; // Skip orphaned records
            }
            if (array_key_exists('processed_by', $row)) {
                $row['processed_by'] = $userIdMapping[$row['processed_by']] ?? null;
            }
            if (array_key_exists('approved_by', $row)) {
                $row['approved_by'] = $userIdMapping[$row['approved_by']] ?? null;
            }
            if (array_key_exists('allocated_room_id', $row)) {
                $row['allocated_room_id'] = $roomIdMapping[$row['allocated_room_id']] ?? null;
            }
            if (array_key_exists('room_id', $row)) {
                $row['room_id'] = $roomIdMapping[$row['room_id']] ?? null;
            }
            if (array_key_exists('current_room_id', $row)) {
                $row['current_room_id'] = $roomIdMapping[$row['current_room_id']] ?? null;
            }
            if (array_key_exists('selected_room_id', $row)) {
                $row['selected_room_id'] = $roomIdMapping[$row['selected_room_id']] ?? null;
            }

            // Bind values
            $params = [];
            foreach ($columns as $c) {
                $params[":$c"] = $row[$c] ?? null;
            }
            $stmtRestore->execute($params);
        }
        echo "Dynamically restored " . count($recordsList) . " records in table: $tableName.\n";
    }

    // Reset logical table auto_increments
    $autoincrementTables = ['users', 'profile', 'hostel_rooms', 'room_master', 'parent_users', 'parent_student_map', 'hostel_type'];
    $dynamicTablesToReset = ['complaints', 'feedbacks', 'renewal_requests', 'room_change_requests', 'room_allocations', 'allocation_requests'];
    foreach ($dynamicTablesToReset as $tbl) {
        if (tableExists($pdo, $tbl)) {
            $autoincrementTables[] = $tbl;
        }
    }
    foreach ($autoincrementTables as $tbl) {
        $pdo->exec("ALTER TABLE `$tbl` AUTO_INCREMENT = 1");
    }

    echo "=== RE-ENABLING FOREIGN KEY CHECKS ===\n";
    $pdo->exec("SET FOREIGN_KEY_CHECKS = 1");

    if ($pdo->inTransaction()) {
        $pdo->commit();
    }
    echo "=== DATABASE SYNCHRONIZATION AND IMPORT COMPLETED SUCCESSFULLY ===\n";

} catch (Exception $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    $pdo->exec("SET FOREIGN_KEY_CHECKS = 1");
    die("Database migration failed: " . $e->getMessage() . "\n");
}
?>
