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
define('VSTUDY_RENEWAL_API_URL', getenv('VSTUDY_RENEWAL_API_URL') ?: ($secrets['VSTUDY_RENEWAL_API_URL'] ?? 'https://vstudy.saveetha.com/api/hostel-applications/external/renew'));
define('VSTUDY_TRANSFER_API_URL', getenv('VSTUDY_TRANSFER_API_URL') ?: ($secrets['VSTUDY_TRANSFER_API_URL'] ?? 'https://vstudy.saveetha.com/api/hostel-applications/external/transfer'));
define('VSTUDY_SHORT_STAY_API_URL', getenv('VSTUDY_SHORT_STAY_API_URL') ?: ($secrets['VSTUDY_SHORT_STAY_API_URL'] ?? 'https://vstudy.saveetha.com/api/hostel-applications/external/short-stay'));
define('VSTUDY_PRICING_API_URL', getenv('VSTUDY_PRICING_API_URL') ?: ($secrets['VSTUDY_PRICING_API_URL'] ?? 'https://vstudy.saveetha.com/api/hostel-applications/external/pricing'));
define('VSTUDY_ROOM_TYPES_API_URL', getenv('VSTUDY_ROOM_TYPES_API_URL') ?: ($secrets['VSTUDY_ROOM_TYPES_API_URL'] ?? 'https://vstudy.saveetha.com/api/hostel-settings/room-types/external'));
define('VSTUDY_RELEASE_API_URL', getenv('VSTUDY_RELEASE_API_URL') ?: ($secrets['VSTUDY_RELEASE_API_URL'] ?? 'https://vstudy.saveetha.com/api/hostel-applications/external/release'));
define('VSTUDY_EB_SYNC_API_URL', getenv('VSTUDY_EB_SYNC_API_URL') ?: ($secrets['VSTUDY_EB_SYNC_API_URL'] ?? 'https://vstudy.saveetha.com/api/hostel-applications/external/eb-meter-readings'));
define('EXTERNAL_EMP_API_URL', getenv('EXTERNAL_EMP_API_URL') ?: ($secrets['EXTERNAL_EMP_API_URL'] ?? 'https://360.saveetha.com/api/external/get-emp-lists.php'));
define('EXTERNAL_EMP_API_KEY', getenv('EXTERNAL_EMP_API_KEY') ?: ($secrets['EXTERNAL_EMP_API_KEY'] ?? ''));
