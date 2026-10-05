<?php
// hostel_backend/utils/auth_helper.php

if (!defined('JWT_SECRET')) {
    $secrets_file = __DIR__ . '/../config/secrets.php';
    $secrets = file_exists($secrets_file) ? include($secrets_file) : [];
    $jwtSec = getenv('JWT_SECRET') ?: ($secrets['JWT_SECRET'] ?? '');
    if (empty($jwtSec)) {
        $jwtSec = 'vstay_jwt_sec_8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d';
    }
    define('JWT_SECRET', $jwtSec);
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

if (!function_exists('getBearerToken')) {
    function getBearerToken() {
        $headers = null;
        if (function_exists('getallheaders')) {
            $headers = getallheaders();
        } elseif (function_exists('apache_request_headers')) {
            $headers = apache_request_headers();
        }
        $authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';
        if (preg_match('/Bearer\s+(\S+)/i', $authHeader, $matches)) {
            return trim($matches[1]);
        }
        return null;
    }
}

if (!function_exists('requireAuth')) {
    function requireAuth($allowedRoles = []) {
        $token = getBearerToken();
        if (!$token) {
            http_response_code(401);
            echo json_encode(['success' => false, 'status' => 'error', 'message' => 'Unauthorized: Missing or invalid token']);
            exit();
        }
        $user = validateJWT($token);
        if (!$user) {
            http_response_code(401);
            echo json_encode(['success' => false, 'status' => 'error', 'message' => 'Unauthorized: Invalid or expired session']);
            exit();
        }
        if (!empty($allowedRoles)) {
            $role = strtolower($user['role'] ?? '');
            $allowed = array_map('strtolower', (array)$allowedRoles);
            // Allow admin and super_admin everywhere privileged access is checked
            if (!in_array($role, $allowed) && !in_array('admin', $allowed) && $role !== 'admin' && $role !== 'super_admin') {
                http_response_code(403);
                echo json_encode(['success' => false, 'status' => 'error', 'message' => 'Forbidden: Insufficient privileges']);
                exit();
            }
        }
        return $user;
    }
}
?>
