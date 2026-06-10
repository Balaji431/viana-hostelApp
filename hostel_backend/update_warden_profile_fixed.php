<?php
$host = "localhost";
$db_name = "stay_simats";
$username = "root";
$password = "vstay2026";
$port = 3307;

try {
    $conn = new mysqli($host, $username, $password, $db_name, $port);
    if ($conn->connect_error) {
        die("Connection failed: " . $conn->connect_error);
    }

    $id = 2; // Warden ID
    $newName = "Venkatesh";
    $newInstitution = "Main Warden"; 

    // Using full_name instead of name
    $sql = "UPDATE users SET full_name = ?, Institution = ? WHERE id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("ssi", $newName, $newInstitution, $id);

    if ($stmt->execute()) {
        echo "Success: Warden profile updated in database.\n";
    } else {
        echo "Error: " . $conn->error . "\n";
    }
} catch (Exception $e) {
    echo "Fatal Error: " . $e->getMessage() . "\n";
}
?>
