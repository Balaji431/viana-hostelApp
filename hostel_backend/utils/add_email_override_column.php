<?php
/**
 * Migration: Add email_override column to users table.
 * 
 * When email_override = 1, the 15-minute sync jobs will NOT overwrite
 * the email or phone_number for that student with data from the external API.
 * This allows manual test accounts to persist for Apple/Play Store review.
 * 
 * Run once. Safe to run multiple times (uses IF NOT EXISTS logic).
 */

require_once __DIR__ . '/../config/database.php';

try {
    $db = (new Database())->getConnection();

    // Add email_override column if it doesn't exist
    $db->exec("
        ALTER TABLE users 
        ADD COLUMN IF NOT EXISTS email_override TINYINT(1) NOT NULL DEFAULT 0 
        COMMENT '1 = manually set, do NOT overwrite email/phone from API sync'
    ");

    echo json_encode([
        'success' => true,
        'message' => 'email_override column added (or already exists) on users table.'
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => $e->getMessage()]);
}
?>
