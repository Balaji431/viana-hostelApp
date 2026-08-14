<?php
$r = file_get_contents('https://vstay.saveetha.com/api/staff/get_external_staff.php');
$d = json_decode($r, true);
echo 'Top-level type: ' . gettype($d) . PHP_EOL;
if (is_array($d)) {
    if (array_keys($d) !== range(0, count($d)-1)) {
        // associative array (object)
        echo 'Structure: OBJECT' . PHP_EOL;
        echo 'Keys: ' . implode(', ', array_keys($d)) . PHP_EOL;
        if (isset($d['data'])) {
            echo 'data count: ' . count($d['data']) . PHP_EOL;
            if (count($d['data']) > 0) {
                echo 'First data item keys: ' . implode(', ', array_keys($d['data'][0])) . PHP_EOL;
                echo 'First data item sample: ' . json_encode(array_slice($d['data'][0], 0, 5)) . PHP_EOL;
            }
        }
    } else {
        echo 'Structure: ARRAY (list)' . PHP_EOL;
        echo 'Count: ' . count($d) . PHP_EOL;
        if (count($d) > 0) {
            echo 'First item keys: ' . implode(', ', array_keys($d[0])) . PHP_EOL;
        }
    }
}
echo PHP_EOL . 'success field: ' . json_encode($d['success'] ?? 'NOT PRESENT') . PHP_EOL;
echo 'source field: ' . json_encode($d['source'] ?? 'NOT PRESENT') . PHP_EOL;
?>
