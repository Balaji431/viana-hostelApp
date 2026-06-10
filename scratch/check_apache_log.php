<?php
$accessLogPath = 'c:/xampp/apache/logs/access.log';
if (file_exists($accessLogPath)) {
    $log = file_get_contents($accessLogPath);
    $lines = explode("\n", $log);
    $lastLines = array_slice($lines, -50); // Get last 50 requests
    foreach ($lastLines as $line) {
        if (strpos($line, 'send_message.php') !== false || strpos($line, 'mark_read.php') !== false) {
            echo $line . "\n";
        }
    }
} else {
    echo "Access log not found at $accessLogPath\n";
}
?>
