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

define('VSTAAY_API_KEY', getenv('VSTAAY_API_KEY') ?: ($secrets['VSTAAY_API_KEY'] ?? ''));
define('VSTUDY_CLIENT_ID', getenv('VSTUDY_CLIENT_ID') ?: ($secrets['VSTUDY_CLIENT_ID'] ?? ''));
define('VSTUDY_CLIENT_SECRET', getenv('VSTUDY_CLIENT_SECRET') ?: ($secrets['VSTUDY_CLIENT_SECRET'] ?? ''));
define('VSTUDY_PAYMENT_API_URL', 'https://vstudy.saveetha.com/api/hostel-applications/paid');
define('EXTERNAL_EMP_API_URL', getenv('EXTERNAL_EMP_API_URL') ?: ($secrets['EXTERNAL_EMP_API_URL'] ?? 'https://360.saveetha.com/api/external/get-emp-lists.php'));
define('EXTERNAL_EMP_API_KEY', getenv('EXTERNAL_EMP_API_KEY') ?: ($secrets['EXTERNAL_EMP_API_KEY'] ?? ''));
