<?php
// hostel_backend/utils/auth_helper.php

if (!defined('JWT_SECRET')) {
    define('JWT_SECRET', 'vstay_super_secret_key_2026_safe');
}

if (!function_exists('base64url_encode')) {
    function base64url_encode($data) {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }
}

if (!function_exists('base64url_decode')) {
    function base64url_decode($data) {
        return base64_decode(str_pad(strtr($data, '-_', '+/'), strlen($data) % 4, '=', STR_PAD_RIGHT));
    }
}

if (!function_exists('generateJWT')) {
    function generateJWT($userId, $username, $role) {
        $header = json_encode(['alg' => 'HS256', 'typ' => 'JWT']);
        $payload = json_encode([
            'id' => $userId,
            'username' => $username,
            'role' => $role,
            'exp' => time() + (3600 * 24 * 30) // 30 days expiry
        ]);
        
        $base64UrlHeader = base64url_encode($header);
        $base64UrlPayload = base64url_encode($payload);
        
        $signature = hash_hmac('sha256', $base64UrlHeader . "." . $base64UrlPayload, JWT_SECRET, true);
        $base64UrlSignature = base64url_encode($signature);
        
        return $base64UrlHeader . "." . $base64UrlPayload . "." . $base64UrlSignature;
    }
}

if (!function_exists('validateJWT')) {
    function validateJWT($token) {
        if (empty($token)) return null;
        
        $parts = explode('.', $token);
        if (count($parts) !== 3) return null;
        
        list($header64, $payload64, $signature64) = $parts;
        
        $signature = base64url_decode($signature64);
        $expectedSignature = hash_hmac('sha256', $header64 . "." . $payload64, JWT_SECRET, true);
        
        if (!hash_equals($signature, $expectedSignature)) {
            return null;
        }
        
        $payload = json_decode(base64url_decode($payload64), true);
        if (!$payload) return null;
        
        if (isset($payload['exp']) && $payload['exp'] < time()) {
            return null; // Expired
        }
        
        return $payload;
    }
}
?>
