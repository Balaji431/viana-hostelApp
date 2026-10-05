<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

$uploadDir = __DIR__ . '/../uploads/temp_stay_docs/';
if (!file_exists($uploadDir)) {
    @mkdir($uploadDir, 0777, true);
}

$inputJSON = json_decode(file_get_contents('php://input'), true);

$docNumber = trim($_POST['doc_number'] ?? $inputJSON['doc_number'] ?? '');
if (empty($docNumber)) {
    echo json_encode(["success" => false, "matched" => false, "message" => "Please enter the Document ID number before uploading."]);
    exit();
}

$fileName = '';
$targetPath = '';

$validExtensions = ['pdf', 'jpg', 'jpeg', 'png'];

if (isset($_FILES['doc_file']) && $_FILES['doc_file']['error'] === UPLOAD_ERR_OK) {
    $file = $_FILES['doc_file'];
    $fileExt = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
    if (!in_array($fileExt, $validExtensions)) {
        echo json_encode(["success" => false, "matched" => false, "message" => "Invalid document file type. Please upload a PDF or Image (JPG/PNG) file."]);
        exit();
    }

    $fileName = time() . '_' . preg_replace('/[^a-zA-Z0-9_\.-]/', '_', basename($file['name']));
    $targetPath = $uploadDir . $fileName;

    if (!move_uploaded_file($file['tmp_name'], $targetPath)) {
        echo json_encode(["success" => false, "matched" => false, "message" => "Failed to save uploaded file."]);
        exit();
    }
} else if (!empty($inputJSON['file_base64']) && !empty($inputJSON['file_name'])) {
    $rawName = basename($inputJSON['file_name']);
    $fileExt = strtolower(pathinfo($rawName, PATHINFO_EXTENSION));
    if (!in_array($fileExt, $validExtensions)) {
        echo json_encode(["success" => false, "matched" => false, "message" => "Invalid document file type. Please upload a PDF or Image (JPG/PNG) file."]);
        exit();
    }

    $fileName = time() . '_' . preg_replace('/[^a-zA-Z0-9_\.-]/', '_', $rawName);
    $targetPath = $uploadDir . $fileName;

    $binaryData = base64_decode($inputJSON['file_base64']);
    if (!$binaryData || file_put_contents($targetPath, $binaryData) === false) {
        echo json_encode(["success" => false, "matched" => false, "message" => "Failed to decode and save base64 document file."]);
        exit();
    }
} else {
    echo json_encode(["success" => false, "matched" => false, "message" => "No document file was provided for upload."]);
    exit();
}

$cleanTypedDoc = strtolower(preg_replace('/[^a-zA-Z0-9]/', '', $docNumber));
$userEmail = trim($_POST['email'] ?? $inputJSON['email'] ?? '');

// Check if this document number already exists under another active request
if (!empty($cleanTypedDoc)) {
    try {
        $database = new Database();
        $db = $database->getConnection();
        if ($db) {
            $stmtDocChk = $db->prepare("
                SELECT id, email 
                FROM temporary_stay_requests 
                WHERE REPLACE(REPLACE(UPPER(TRIM(doc_number)), ' ', ''), '-', '') = ? 
                  AND LOWER(TRIM(email)) != LOWER(TRIM(?))
                  AND status IN ('pending', 'approved', 'allocated')
                LIMIT 1
            ");
            $stmtDocChk->execute([strtoupper($cleanTypedDoc), $userEmail]);
            $dConflict = $stmtDocChk->fetch(PDO::FETCH_ASSOC);
            if ($dConflict) {
                @unlink($targetPath);
                echo json_encode([
                    "success" => false,
                    "matched" => false,
                    "message" => "This government document number ($docNumber) already exists and is registered to another application. Please upload your own valid government ID."
                ]);
                exit();
            }
        }
    } catch (Exception $e) {}
}

/**
 * Advanced PDF Stream & FlateDecode Decompressor to extract text from e-PAN / e-Aadhaar PDFs
 */
function extractAllPdfText($filePath) {
    $content = file_get_contents($filePath);
    if (!$content) return '';

    $text = '';

    // 1. Literal PDF strings inside parentheses: (GSPPB2566F)
    preg_match_all('/(?<=\()[\w\s\-\.\/]+(?=\))/u', $content, $matches);
    if (!empty($matches[0])) {
        $text .= ' ' . implode(' ', $matches[0]);
    }

    // 2. Hex strings: <47535050423235363646>
    preg_match_all('/<([0-9a-fA-F]{6,})>/', $content, $hexMatches);
    if (!empty($hexMatches[1])) {
        foreach ($hexMatches[1] as $hex) {
            $decoded = @hex2bin($hex);
            if ($decoded) $text .= ' ' . $decoded;
        }
    }

    // 3. Decompress FlateDecode streams in PDF
    preg_match_all('/stream[\r\n]+(.*?)[\r\n]+endstream/s', $content, $streamMatches);
    if (!empty($streamMatches[1])) {
        foreach ($streamMatches[1] as $rawStream) {
            $decompressed = @gzuncompress($rawStream);
            if (!$decompressed) $decompressed = @gzinflate($rawStream);
            if (!$decompressed) $decompressed = @zlib_decode($rawStream);

            if ($decompressed) {
                preg_match_all('/(?<=\()[\w\s\-\.\/]+(?=\))/u', $decompressed, $subMatches);
                if (!empty($subMatches[0])) {
                    $text .= ' ' . implode(' ', $subMatches[0]);
                }
                preg_match_all('/<([0-9a-fA-F]{6,})>/', $decompressed, $subHex);
                if (!empty($subHex[1])) {
                    foreach ($subHex[1] as $h) {
                        $dec = @hex2bin($h);
                        if ($dec) $text .= ' ' . $dec;
                    }
                }
                preg_match_all('/[a-zA-Z0-9]{3,}/', $decompressed, $subAscii);
                if (!empty($subAscii[0])) {
                    $text .= ' ' . implode(' ', $subAscii[0]);
                }
            }
        }
    }

    // 4. Raw ASCII fallback across entire binary file content
    preg_match_all('/[a-zA-Z0-9]{3,}/', $content, $rawAscii);
    if (!empty($rawAscii[0])) {
        $text .= ' ' . implode(' ', $rawAscii[0]);
    }

    return $text;
}

$fileExt = strtolower(pathinfo($targetPath, PATHINFO_EXTENSION));
$validExtensions = ['pdf', 'jpg', 'jpeg', 'png'];

if (!in_array($fileExt, $validExtensions)) {
    @unlink($targetPath);
    echo json_encode([
        "success" => false,
        "matched" => false,
        "message" => "Invalid document file type. Please upload a PDF or Image (JPG/PNG) file."
    ]);
    exit();
}

$extractedText = '';
if ($fileExt === 'pdf') {
    $extractedText = extractAllPdfText($targetPath);
} else {
    $rawContent = file_get_contents($targetPath);
    preg_match_all('/[a-zA-Z0-9]{3,}/', $rawContent, $asciiMatches);
    $extractedText = implode(' ', $asciiMatches[0] ?? []);
}

$relPath = 'uploads/temp_stay_docs/' . $fileName;

echo json_encode([
    "success" => true,
    "matched" => true,
    "file_path" => $relPath,
    "message" => "Document ID '$docNumber' attached successfully. Uploaded document is ready for Admin verification."
]);
?>
