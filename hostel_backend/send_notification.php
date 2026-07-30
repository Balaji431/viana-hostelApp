<?php
/**
 * Unified FCM Notification Service
 *
 * IMPORTANT: We send DATA-ONLY FCM messages (no 'notification' block).
 * This forces Android to route the message through our Flutter background
 * handler (_backgroundHandler), which then shows a LOCAL notification with
 * the 3 WhatsApp-style action buttons (Reply, Mark as Read, Mute).
 *
 * If we included a 'notification' block, Android would auto-render the
 * notification at the system level WITHOUT our action buttons.
 */

require_once __DIR__ . '/vendor/autoload.php';

use Google\Auth\Credentials\ServiceAccountCredentials;
use Google\Auth\HttpHandler\HttpHandlerFactory;

function sendFCM($token, $title, $body, $requestId = '', $senderId = '', $senderName = '', $messageText = '', $type = 'chat', $department = '') {
    $serviceAccountPath = __DIR__ . '/config/service-account.json';
    
    if (!file_exists($serviceAccountPath)) {
        $serviceAccountPath = __DIR__ . '/service-account.json';
    }

    $logMsg = date('Y-m-d H:i:s') . " - Attempting to send FCM to $token\n";
    file_put_contents(__DIR__ . '/fcm_debug.txt', $logMsg, FILE_APPEND);

    if (!file_exists($serviceAccountPath)) {
        file_put_contents(__DIR__ . '/fcm_debug.txt', "ERROR: Service account file not found at $serviceAccountPath\n", FILE_APPEND);
        return json_encode(["error" => "Service account missing"]);
    }

    // Auto-detect Project ID from Service Account
    $saData = json_decode(file_get_contents($serviceAccountPath), true);
    $projectId = $saData['project_id'] ?? 'hostel-app-3afa1';

    try {
        $accessToken = null;
        $cacheFile = __DIR__ . '/config/fcm_token_cache.json';
        
        if (file_exists($cacheFile)) {
            $cacheData = json_decode(file_get_contents($cacheFile), true);
            if ($cacheData && isset($cacheData['access_token']) && $cacheData['expires_at'] > (time() + 300)) {
                $accessToken = $cacheData['access_token'];
            }
        }

        if (!$accessToken) {
            $scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
            $credentials = new ServiceAccountCredentials($scopes, $serviceAccountPath);
            $tokenArray = $credentials->fetchAuthToken(HttpHandlerFactory::build());
            $accessToken = $tokenArray['access_token'];

            file_put_contents($cacheFile, json_encode([
                'access_token' => $accessToken,
                'expires_at'   => time() + 3300
            ]));
        }

        $url = "https://fcm.googleapis.com/v1/projects/$projectId/messages:send";

        // ─────────────────────────────────────────────────────────────────
        // UNIFIED native + data payload.
        // Android: 'priority=high' and native notification wakes the device
        //          even in Doze mode or deep background, showing it instantly.
        // iOS: 'content-available=1' + native alert wakes iOS background fetch.
        // ─────────────────────────────────────────────────────────────────
        $message = [
            'message' => [
                'token' => $token,
                'data' => [
                    'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                    'request_id'   => (string)$requestId,
                    'sender_id'    => (string)$senderId,
                    'sender_name'  => (string)$senderName,
                    'message'      => (string)$messageText,
                    'title'        => (string)$title,
                    'body'         => (string)$body,
                    'type'         => (string)$type,
                    'department'   => (string)$department,
                ],
                'android' => [
                    'priority' => 'high',   // Wakes device even in Doze mode
                    'notification' => [
                        'sound' => 'default',
                        'click_action' => 'FLUTTER_NOTIFICATION_CLICK'
                    ]
                ],
                'apns' => [
                    'headers' => [
                        'apns-priority'  => '10',
                        'apns-push-type' => 'alert',
                    ],
                    'payload' => [
                        'aps' => [
                            'alert' => [
                                'title' => (string)$title,
                                'body'  => (string)$body,
                            ],
                            'content-available' => 1,
                            'mutable-content'   => 1,
                            'sound'             => 'default',
                            'badge'             => 1,
                        ],
                    ],
                ],
            ]
        ];

        $headers = [
            'Authorization: Bearer ' . $accessToken,
            'Content-Type: application/json'
        ];

        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($message));

        $result = curl_exec($ch);
        curl_close($ch);

        file_put_contents(__DIR__ . '/fcm_response.txt', date('Y-m-d H:i:s') . " - RESPONSE: $result\n", FILE_APPEND);
        return $result;

    } catch (Exception $e) {
        file_put_contents(__DIR__ . '/fcm_debug.txt', "EXCEPTION: " . $e->getMessage() . "\n", FILE_APPEND);
        return json_encode(["error" => $e->getMessage()]);
    }
}
?>
