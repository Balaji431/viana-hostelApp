<?php
header('Content-Type: text/plain; charset=utf-8');
require_once __DIR__ . '/config/database.php';

$db = new Database();
$pdo = $db->getConnection();

if (!$pdo) {
    die("Database connection failed!\n");
}

echo "=== IMPORTING STUDENTS FROM EXCEL SHEETS ===\n\n";

function parseXlsx($filePath) {
    $zip = new ZipArchive();
    if ($zip->open($filePath) !== TRUE) {
        throw new Exception("Cannot open ZIP file: " . $filePath);
    }
    
    // Read sharedStrings.xml
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
    
    // Read sheet1.xml
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

// Room mapping function
function mapToDbRoomType($type, $hostelName) {
    $type = strtoupper(trim($type));
    
    if (stripos($hostelName, 'noyyal') !== false) {
        if (stripos($type, '3 IN 1') !== false) {
            return 'Super Deluxe 3 IN 1 Bath Attached AC';
        }
        if (stripos($type, '4 IN 1') !== false) {
            return 'Super Deluxe 4 IN 1 Bath Attached AC';
        }
        return $type;
    }
    
    if (stripos($hostelName, 'ponni') !== false) {
        if (stripos($type, '3 IN') !== false) {
            return '3 IN 1 Non AC';
        }
        return $type;
    }
    
    if (stripos($hostelName, 'palar') !== false) {
        if (preg_match('/(\d+)\s*SHARING/i', $type, $m)) {
            $ac = (stripos($type, 'AC') !== false && stripos($type, 'NON') === false) ? 'AC' : 'Non AC';
            return $m[1] . " IN 1 " . $ac;
        }
    }
    
    return $type;
}

$files = [
    'Noyyal' => [
        'path' => 'C:/xampp/htdocs/hostelapp/HOSTEL FINAL - NOYYAL.xlsx',
        'hostel_name' => 'Noyyal Hostel',
        'hostel_type' => 'Boys',
        'reg_col' => 'C',
        'name_col' => 'D',
        'room_col' => 'H',
        'room_type_col' => 'G',
        'inst_col' => 'E',
        'course_col' => 'F',
        'start_row' => 2
    ],
    'Ponni' => [
        'path' => 'C:/xampp/htdocs/hostelapp/HOSTEL FINAL- PONNI.xlsx',
        'hostel_name' => 'SCON Ponni Hostel',
        'hostel_type' => 'Girls',
        'reg_col' => 'D',
        'name_col' => 'C',
        'room_col' => 'H',
        'room_type_col' => 'G',
        'inst_col' => 'E',
        'course_col' => 'F',
        'start_row' => 2
    ],
    'Palar' => [
        'path' => 'C:/xampp/htdocs/hostelapp/HOSTEL FINAL - PALAR.xlsx',
        'hostel_name' => 'Palar Hostel',
        'hostel_type' => 'Boys',
        'reg_col' => 'D',
        'name_col' => 'C',
        'room_col' => 'G',
        'room_type_col' => 'F',
        'inst_col' => 'E',
        'course_col' => 'E',
        'start_row' => 2 // Data row starts with S.No = 1 at Row 3 (we start scanning rows >= 2)
    ]
];

$pdo->beginTransaction();

try {
    $insertUserStmt = $pdo->prepare("
        INSERT INTO users (
            username, full_name, role, Campus, Institution, HostelName, HostelType, RoomType, RoomId, Academic, password, conduct, Status
        ) VALUES (
            :username, :full_name, 'student', 'Thandalam Campus', :institution, :hostel_name, :hostel_type, :room_type, :room_id, :academic, :password, 'Good', '1'
        ) ON DUPLICATE KEY UPDATE
            full_name = VALUES(full_name),
            Institution = VALUES(Institution),
            HostelName = VALUES(HostelName),
            HostelType = VALUES(HostelType),
            RoomType = VALUES(RoomType),
            RoomId = VALUES(RoomId),
            Academic = VALUES(Academic),
            Status = '1'
    ");
    
    $checkProfileStmt = $pdo->prepare("SELECT id FROM profile WHERE reg_no = ?");
    $insertProfileStmt = $pdo->prepare("
        INSERT INTO profile (reg_no, full_name, institution, hostel_name, room_allocation, valid_from, valid_to)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ");
    $updateProfileStmt = $pdo->prepare("
        UPDATE profile 
        SET full_name = ?, institution = ?, hostel_name = ?, room_allocation = ?
        WHERE reg_no = ?
    ");
    
    $defaultPasswordHash = '$2y$10$hk6ENKqC1vXmLF1dRtxFIu/ej8r7z1S5U2nhvHnkTI2CD4mRk9AXG'; // hash for welcome123
    
    $hostelStats = [];
    
    foreach ($files as $key => $f) {
        echo "Processing sheet: {$key}...\n";
        $rows = parseXlsx($f['path']);
        
        $totalRows = count($rows);
        $imported = 0;
        $updated = 0;
        $skipped = 0;
        
        foreach ($rows as $row) {
            $rowNum = $row['_rowNum'];
            if ($rowNum < $f['start_row']) {
                continue; // Skip header row
            }
            
            $regNo = $row[$f['reg_col']] ?? '';
            $fullName = $row[$f['name_col']] ?? '';
            $roomId = $row[$f['room_col']] ?? '';
            $rawRoomType = $row[$f['room_type_col']] ?? '';
            $institution = $row[$f['inst_col']] ?? '';
            $course = $row[$f['course_col']] ?? '';
            
            // Clean values
            $regNo = trim($regNo);
            $fullName = trim($fullName);
            $roomId = trim($roomId);
            $rawRoomType = trim($rawRoomType);
            $institution = trim($institution);
            $course = trim($course);
            
            // Skip invalid rows
            if (empty($regNo) || empty($fullName)) {
                $skipped++;
                continue;
            }
            
            // Skip header repetitions or placeholders
            if (stripos($regNo, 'reg') !== false || stripos($fullName, 'student name') !== false) {
                $skipped++;
                continue;
            }
            
            if (stripos($fullName, 'vacant') !== false || strtolower($fullName) === 'vacant') {
                $skipped++;
                continue;
            }
            
            // Map room type
            $dbRoomType = mapToDbRoomType($rawRoomType, $f['hostel_name']);
            
            // Academic year default to '1st Year' or extract from program if possible
            $academic = '1st Year';
            if (stripos($course, 'ii yr') !== false || stripos($course, '2nd') !== false || stripos($course, 'iiyr') !== false) {
                $academic = '2nd Year';
            } elseif (stripos($course, 'iii yr') !== false || stripos($course, '3rd') !== false || stripos($course, 'iiiyr') !== false) {
                $academic = '3rd Year';
            } elseif (stripos($course, 'iv yr') !== false || stripos($course, '4th') !== false || stripos($course, 'ivyr') !== false) {
                $academic = '4th Year';
            } elseif (stripos($course, 'intern') !== false) {
                $academic = 'Intern';
            }
            
            // Check if username already exists to update stats
            $stmtCheck = $pdo->prepare("SELECT id FROM users WHERE username = ?");
            $stmtCheck->execute([$regNo]);
            $userExists = $stmtCheck->fetch();
            
            // Insert or Update users table
            $insertUserStmt->execute([
                ':username' => $regNo,
                ':full_name' => $fullName,
                ':institution' => $institution ?: 'SIMATS',
                ':hostel_name' => $f['hostel_name'],
                ':hostel_type' => $f['hostel_type'],
                ':room_type' => $dbRoomType,
                ':room_id' => $roomId,
                ':academic' => $academic,
                ':password' => $defaultPasswordHash
            ]);
            
            if ($userExists) {
                $updated++;
            } else {
                $imported++;
            }
            
            // Upsert profile table
            $checkProfileStmt->execute([$regNo]);
            $profileExists = $checkProfileStmt->fetch();
            
            if ($profileExists) {
                $updateProfileStmt->execute([
                    $fullName,
                    $institution ?: 'SIMATS',
                    $f['hostel_name'],
                    $roomId,
                    $regNo
                ]);
            } else {
                $insertProfileStmt->execute([
                    $regNo,
                    $fullName,
                    $institution ?: 'SIMATS',
                    $f['hostel_name'],
                    $roomId,
                    null,
                    null
                ]);
            }
        }
        
        $hostelStats[$key] = [
            'Total Sheet Rows' => $totalRows,
            'Imported (New Users)' => $imported,
            'Updated (Existing Users)' => $updated,
            'Skipped (Vacant/Empty)' => $skipped,
            'Total Active Students' => ($imported + $updated)
        ];
        
        echo "Finished {$key}: Total active students imported/updated = " . ($imported + $updated) . "\n\n";
    }
    
    $pdo->commit();
    echo "=== DATABASE TRANSACTION COMMITTED SUCCESSFULLY ===\n\n";
    
    // Print stats table
    echo "Summary of Counts:\n";
    echo str_pad("Hostel Name", 15) . " | " .
         str_pad("New Students", 15) . " | " .
         str_pad("Updated Students", 18) . " | " .
         str_pad("Skipped Rows", 15) . " | " .
         str_pad("Total Active Students", 22) . "\n";
    echo str_repeat("-", 95) . "\n";
    foreach ($hostelStats as $hName => $stats) {
        echo str_pad($hName, 15) . " | " .
             str_pad($stats['Imported (New Users)'], 15) . " | " .
             str_pad($stats['Updated (Existing Users)'], 18) . " | " .
             str_pad($stats['Skipped (Vacant/Empty)'], 15) . " | " .
             str_pad($stats['Total Active Students'], 22) . "\n";
    }
    
} catch (Exception $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    die("Transaction failed: " . $e->getMessage() . "\n");
}
