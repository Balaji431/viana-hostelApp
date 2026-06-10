<?php
$conn = new mysqli('127.0.0.1', 'user', 'vstay2026', 'stay_simats', 3307);
if ($conn->connect_error) die("Connect Error: " . $conn->connect_error);

$new_password = 'password123';
$hash = password_hash($new_password, PASSWORD_DEFAULT);

$users = ['warden1', 'rajesh1', 'anitha1', 'suresh1'];

foreach ($users as $username) {
    $stmt = $conn->prepare("UPDATE users SET password = ? WHERE username = ?");
    $stmt->bind_param("ss", $hash, $username);
    if ($stmt->execute()) {
        echo "Successfully updated password for $username to '$new_password'\n";
    } else {
        echo "Failed to update password for $username: " . $stmt->error . "\n";
    }
    $stmt->close();
}

$conn->close();
?>
