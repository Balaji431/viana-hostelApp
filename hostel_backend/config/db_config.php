<?php
/**
 * OLD DATABASE CONFIG FILE (Legacy Support)
 * Now uses the centralized Database class
 */

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Origin, Accept');
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once 'database.php';

// Support for both types of connections if needed
$database_mysqli = new DatabaseMysqli();
$conn = $database_mysqli->getConnection();

$database_pdo = new Database();
$db = $database_pdo->getConnection();

// Error check
if (!$conn) {
    die(json_encode(["success" => false, "message" => "MySQLi Connection failed"]));
}
?>
