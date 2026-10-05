<?php
/**
 * sync_biometric_attendance.php
 *
 * NOTE: This script no longer inserts into the `attendance` table.
 * The `attendance` table stores WARDEN MANUAL MARKS only.
 * Biometric data is fetched live from the external API for IT dashboard display.
 * DO NOT re-enable automatic biometric inserts into attendance.
 */
set_time_limit(600);
ini_set('display_errors', 1);
error_reporting(E_ALL);

require_once __DIR__ . '/../config/database.php';

$database = new Database();
$db = $database->getConnection();

if (!$db) {
    die("Database connection failed.\n");
}

echo "Database connection successful!\n";
echo "[INFO] Biometric attendance sync to DB is DISABLED.\n";
echo "[INFO] The attendance table is WARDEN MANUAL MARKS only.\n";
echo "[INFO] Biometric logs are fetched live from the external API for IT dashboard display.\n";
echo "\nNo changes made. Done.\n";
?>
