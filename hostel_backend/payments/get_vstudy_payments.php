<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/../config/database.php';

try {
    $database = new Database();
    $db = $database->getConnection();

    if (!$db) {
        throw new Exception("Database connection failed");
    }

    $page = isset($_GET['page']) ? (int)$_GET['page'] : 1;
    $limit = isset($_GET['limit']) ? (int)$_GET['limit'] : 10;
    if ($page < 1) $page = 1;
    if ($limit < 1) $limit = 10;
    
    $offset = ($page - 1) * $limit;

    $search = isset($_GET['search']) ? trim($_GET['search']) : '';
    $where = "";
    $params = [];

    if ($search !== '') {
        $where = " WHERE roll_number LIKE :search OR student_name LIKE :search ";
        $params[':search'] = "%$search%";
    }

    // 1. Get total count
    $count_query = "SELECT COUNT(*) as total FROM vstudy_payments $where";
    $stmt_count = $db->prepare($count_query);
    foreach ($params as $key => $val) {
        $stmt_count->bindValue($key, $val);
    }
    $stmt_count->execute();
    $count_row = $stmt_count->fetch(PDO::FETCH_ASSOC);
    $total = (int)$count_row['total'];

    // 2. Fetch paginated records
    $data_query = "SELECT * FROM vstudy_payments $where ORDER BY id DESC LIMIT :limit OFFSET :offset";
    $stmt_data = $db->prepare($data_query);
    foreach ($params as $key => $val) {
        $stmt_data->bindValue($key, $val);
    }
    $stmt_data->bindValue(':limit', $limit, PDO::PARAM_INT);
    $stmt_data->bindValue(':offset', $offset, PDO::PARAM_INT);
    $stmt_data->execute();
    $records = $stmt_data->fetchAll(PDO::FETCH_ASSOC);

    $totalPages = ceil($total / $limit);

    echo json_encode([
        "success" => true,
        "status" => "success",
        "data" => $records,
        "pagination" => [
            "total" => $total,
            "page" => $page,
            "limit" => $limit,
            "totalPages" => $totalPages,
            "hasNext" => $page < $totalPages,
            "hasPrev" => $page > 1
        ]
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "success" => false,
        "status" => "error",
        "message" => $e->getMessage()
    ]);
}
?>
