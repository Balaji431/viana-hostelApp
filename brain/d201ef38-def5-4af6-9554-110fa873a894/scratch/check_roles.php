<?php
$output = shell_exec('c:\xampp\php\php.exe c:\xampp\htdocs\hostelapp\hostel_backend\staff\get_external_staff.php');
$data = json_decode($output, true);
if (isset($data['data'])) {
    $roles = [];
    foreach ($data['data'] as $emp) {
        $r = $emp['role'];
        if (!isset($roles[$r])) $roles[$r] = 0;
        $roles[$r]++;
    }
    print_r($roles);
} else {
    echo "No data found";
}
?>
