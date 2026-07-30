<?php
// Suppress warnings that could corrupt JSON output
ini_set('display_errors', 0);
error_reporting(E_ALL);
date_default_timezone_set('Asia/Kolkata');

/**
 * Single Database Connection Class
 * All PHP files should use this instead of duplicate connection code
 */

class Database {
    private $host;
    private $db_name;
    private $username;
    private $password;
    private $port;
    public $conn;

    public function __construct() {
        $secrets_file = __DIR__ . '/secrets.php';
        $secrets = [];
        if (file_exists($secrets_file)) {
            $secrets = include($secrets_file);
        }

        $this->host = getenv('DB_HOST') ?: ($secrets['DB_HOST'] ?? "db");
        $this->db_name = getenv('DB_NAME') ?: ($secrets['DB_NAME'] ?? "stay_simtas");
        if ($this->db_name === 'stay_simats') {
            $this->db_name = 'stay_simtas';
        }
        $this->username = getenv('DB_USER') ?: ($secrets['DB_USER'] ?? "root");
        $this->password = getenv('DB_PASS') ?: ($secrets['DB_PASS'] ?? "");
        $this->port = (int)(getenv('DB_PORT') ?: ($secrets['DB_PORT'] ?? 3306));

        if (strtoupper(substr(PHP_OS, 0, 3)) === 'WIN' || gethostbyname('db') === 'db') {
            $this->host = getenv('DB_HOST_LOCAL') ?: ($secrets['DB_HOST_LOCAL'] ?? "127.0.0.1");
            $this->port = (int)(getenv('DB_PORT_LOCAL') ?: ($secrets['DB_PORT_LOCAL'] ?? 3307));
        }
    }

    public function getConnection() {
        // Force PHP to use IST
        date_default_timezone_set('Asia/Kolkata');

        $candidates = [
            ['host' => $this->host, 'port' => $this->port],
            ['host' => '127.0.0.1', 'port' => 3306],
            ['host' => 'localhost', 'port' => 3306],
            ['host' => '127.0.0.1', 'port' => 3307],
            ['host' => 'db', 'port' => 3306],
        ];

        $tried = [];
        foreach ($candidates as $cand) {
            $key = $cand['host'] . ':' . $cand['port'];
            if (isset($tried[$key])) continue;
            $tried[$key] = true;

            try {
                $dsn = "mysql:host=" . $cand['host'] . ";port=" . $cand['port'] . ";dbname=" . $this->db_name;
                $conn = new PDO($dsn, $this->username, $this->password, [
                    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                    PDO::ATTR_TIMEOUT => 3
                ]);
                $conn->exec("set names utf8mb4");
                $conn->exec("SET time_zone = '+05:30'");
                $this->conn = $conn;
                return $this->conn;
            } catch (PDOException $e) {
                // Try next candidate in loop
            }
        }

        return null;
    }
}

// Alternative MySQLi connection for files that need it
class DatabaseMysqli {
    private $host;
    private $db_name;
    private $username;
    private $password;
    private $port;
    public $conn;

    public function __construct() {
        $secrets_file = __DIR__ . '/secrets.php';
        $secrets = [];
        if (file_exists($secrets_file)) {
            $secrets = include($secrets_file);
        }

        $this->host = $secrets['DB_HOST'] ?? getenv('DB_HOST') ?? "db";
        $this->db_name = $secrets['DB_NAME'] ?? getenv('DB_NAME') ?? "stay_simats";
        $this->username = $secrets['DB_USER'] ?? getenv('DB_USER') ?? "root";
        $this->password = $secrets['DB_PASS'] ?? getenv('DB_PASS') ?? "vstay2026";
        $this->port = (int)($secrets['DB_PORT'] ?? getenv('DB_PORT') ?? 3306);

        if (strtoupper(substr(PHP_OS, 0, 3)) === 'WIN' || gethostbyname('db') === 'db') {
            $this->host = $secrets['DB_HOST_LOCAL'] ?? "127.0.0.1";
            $this->port = (int)($secrets['DB_PORT_LOCAL'] ?? 3307);
        }
    }

    public function getConnection() {
        // Force PHP to use IST
        date_default_timezone_set('Asia/Kolkata');

        try {
            $this->conn = new mysqli($this->host, $this->username, $this->password, $this->db_name, $this->port);
            
            if ($this->conn->connect_error) {
                return null;
            }
            
            // Set charset
            $this->conn->set_charset("utf8mb4");
            
            // 🔥 Force MySQL session to align with IST (+5:30)
            $this->conn->query("SET time_zone = '+05:30'");
            
        } catch (Exception $exception) {
            return null; // Return null instead of exiting to allow caller to handle
        }
        return $this->conn;
    }
}

// Global connection instance for backward compatibility
$databaseMysqli = new DatabaseMysqli();
$conn = $databaseMysqli->getConnection();

$databasePdo = new Database();
$pdo = $databasePdo->getConnection();
?>