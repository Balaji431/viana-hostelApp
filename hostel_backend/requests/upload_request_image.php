<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

$uploadDir = __DIR__ . '/../uploads/maintenance_photos/';
if (!file_exists($uploadDir)) {
    @mkdir($uploadDir, 0777, true);
}

// 1. Handle Multipart file upload
if (isset($_FILES['image']) && $_FILES['image']['error'] === UPLOAD_ERR_OK) {
    $fileTmpPath = $_FILES['image']['tmp_name'];
    $fileName = $_FILES['image']['name'];
    $fileExtension = strtolower(pathinfo($fileName, PATHINFO_EXTENSION));
    
    $allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
    if (!in_array($fileExtension, $allowedExtensions)) {
        $fileExtension = 'jpg';
    }

    $newFileName = 'maint_' . time() . '_' . rand(1000, 9999) . '.' . $fileExtension;
    $destPath = $uploadDir . $newFileName;

    if (move_uploaded_file($fileTmpPath, $destPath)) {
        $imageUrl = 'uploads/maintenance_photos/' . $newFileName;
        echo json_encode([
            "success" => true,
            "message" => "Image uploaded successfully",
            "image_url" => $imageUrl
        ]);
        exit();
    }
}

// 2. Handle Base64 JSON upload fallback
$raw = file_get_contents("php://input");
$data = json_decode($raw, true);

if ($data && !empty($data['base64'])) {
    $base64Data = $data['base64'];
    if (preg_match('/^data:image\/(\w+);base64,/', $base64Data, $type)) {
        $base64Data = substr($base64Data, strpos($base64Data, ',') + 1);
        $ext = strtolower($type[1]);
    } else {
        $ext = 'jpg';
    }

    $base64Data = base64_decode($base64Data);
    if ($base64Data !== false) {
        $newFileName = 'maint_' . time() . '_' . rand(1000, 9999) . '.' . $ext;
        $destPath = $uploadDir . $newFileName;
        if (file_put_contents($destPath, $base64Data)) {
            $imageUrl = 'uploads/maintenance_photos/' . $newFileName;
            echo json_encode([
                "success" => true,
                "message" => "Image uploaded successfully",
                "image_url" => $imageUrl
            ]);
            exit();
        }
    }
}

echo json_encode([
    "success" => false,
    "message" => "No image file or valid base64 data provided"
]);
