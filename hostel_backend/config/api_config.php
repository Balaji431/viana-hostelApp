<?php
/**
 * Centralized API configuration file
 * Stored on server side to hide keys from the frontend client.
 */
$secrets_file = __DIR__ . '/secrets.php';
$secrets = [];
if (file_exists($secrets_file)) {
    $secrets = include($secrets_file);
}

define('VSTAAY_API_KEY', $secrets['VSTAAY_API_KEY'] ?? 'BGNVLg7dC0/svRNIl08Q7fnQtvKIe9Zl11VJmz6ciGQ=');
define('VSTUDY_CLIENT_ID', $secrets['VSTUDY_CLIENT_ID'] ?? 'client_51e2de18e4a27a525e2fd17a');
define('VSTUDY_CLIENT_SECRET', $secrets['VSTUDY_CLIENT_SECRET'] ?? 'secret_7f8fdb2dc219dd64be8d496201590db3bd18c8fe6b1e9faf');
?>

