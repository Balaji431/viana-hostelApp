# ==============================================================================
# Script: reset_student_renewal.ps1
# Description: Resets student & guest renewal / temporary stay details, payments, 
#              wallets, and calculates real remaining days dynamically.
# Usage:
#   1. Default Reset for student 192511250:
#      .\reset_student_renewal.ps1
#
#   2. Reset Any Other Student:
#      .\reset_student_renewal.ps1 -RegNo "192511250"
#
#   3. Custom Dates for Student:
#      .\reset_student_renewal.ps1 -RegNo "192511250" -RenewalDate "2027-08-07" -CheckInDate "2026-08-09"
#
#   4. Reset Renewal Details + Reset Wallet Balance to ₹0:
#      .\reset_student_renewal.ps1 -ResetWallet
#
#   5. Reset Guest / Temporary Stay Request:
#      .\reset_student_renewal.ps1 -RegNo "TEMP-D9F27B37"
#      .\reset_student_renewal.ps1 -RegNo "TEMP-1B0B1728"
# ==============================================================================

param(
    [string]$RegNo = "192511250",
    [string]$RenewalDate = "2027-08-07",
    [string]$CheckInDate = "2026-08-09",
    [switch]$ResetWallet = $false
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Resetting Records for: $RegNo" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$isGuest = ($RegNo -like "TEMP*" -or $RegNo -like "*@*")

if ($isGuest) {
    Write-Host "Detected Guest / Temporary Stay ID. Performing Guest & Temporary Stay Cleanup..." -ForegroundColor Magenta

    $sql = @"
-- 1. Remove from temporary_stay_requests
DELETE FROM temporary_stay_requests 
WHERE request_id = '$RegNo' 
   OR email = '$RegNo' 
   OR email IN (SELECT email FROM users WHERE username = '$RegNo');

-- 2. Remove guest user from users & profile tables
DELETE FROM profile WHERE reg_no = '$RegNo';
DELETE FROM users WHERE username = '$RegNo' OR (role = 'guest' AND email = '$RegNo');

-- 3. Clear guest payment records from payment table (so Warden Payments & UI reset)
DELETE FROM payment WHERE registerNumber = '$RegNo' OR email = '$RegNo';

-- 4. Clear guest wallet & transactions
DELETE FROM wallet_transactions WHERE LOWER(email) LIKE LOWER('%$RegNo%');
DELETE FROM user_wallets WHERE LOWER(email) LIKE LOWER('%$RegNo%');

-- 5. Verification output for Temporary Stay
SELECT id, request_id, full_name, email, phone, status 
FROM temporary_stay_requests 
WHERE request_id = '$RegNo' OR email = '$RegNo';
"@

} else {
    Write-Host "Detected Student Registration Number. Performing Student Renewal Reset..." -ForegroundColor Cyan

    $sql = @"
-- 1. Reset profile renewal date, check-in date, and re-calculate real remaining days
UPDATE profile 
SET 
    renewal_date = '$RenewalDate',
    check_in_date = '$CheckInDate',
    remaining_days = GREATEST(0, DATEDIFF('$RenewalDate', CURDATE()))
WHERE reg_no = '$RegNo';

-- 2. Clear any test renewal requests for this student (so Warden Management Renewals tab resets)
DELETE FROM renewal_requests WHERE student_reg_no = '$RegNo' OR student_id IN (SELECT id FROM users WHERE username = '$RegNo');

-- 3. Clear renewal payment history records (so Student Settings & Warden Payments tab reset)
DELETE FROM payment WHERE registerNumber = '$RegNo' AND (payment_type LIKE '%Renewal%' OR payment_type LIKE '%renew%');

-- 4. Clear renewal wallet transactions (so Student Wallet card resets)
DELETE FROM wallet_transactions WHERE LOWER(email) LIKE LOWER('%$RegNo%') AND (LOWER(description) LIKE '%renewal%' OR LOWER(description) LIKE '%renew%');

-- 5. Clear any test temporary stay requests for this student's email/reg_no
DELETE FROM temporary_stay_requests WHERE email IN (SELECT email FROM users WHERE username = '$RegNo');
"@

    if ($ResetWallet) {
        $sql += @"

-- 6. Reset wallet balance and all transactions to 0 if requested
UPDATE user_wallets SET balance = 0.00 WHERE LOWER(email) LIKE LOWER('%$RegNo%');
DELETE FROM wallet_transactions WHERE LOWER(email) LIKE LOWER('%$RegNo%');
"@
    } else {
        $sql += @"

-- 6. Refund renewal debit back to wallet balance if was debited
UPDATE user_wallets SET balance = balance + 120000.00 WHERE LOWER(email) LIKE LOWER('%$RegNo%') AND balance = 381000.00;
"@
    }

    $sql += @"

-- Verification output
SELECT 
    reg_no, 
    full_name, 
    check_in_date, 
    renewal_date, 
    remaining_days, 
    room_allocation
FROM profile
WHERE reg_no = '$RegNo'
LIMIT 1;

SELECT 
    id, 
    email, 
    balance 
FROM user_wallets 
WHERE LOWER(email) LIKE '%$RegNo%' 
LIMIT 1;

SELECT 
    id, 
    registerNumber, 
    name, 
    payment_type, 
    amount, 
    status 
FROM payment 
WHERE registerNumber = '$RegNo'
LIMIT 5;
"@
}

# Execute against Docker MySQL container
try {
    Write-Host "Executing SQL reset inside hostel_db..." -ForegroundColor Gray
    docker exec hostel_db mysql -u root -pvstay2026 stay_simats -e "$sql"
    
    Write-Host ""
    if ($isGuest) {
        Write-Host " [SUCCESS] Guest / Temporary Stay ($RegNo) has been completely reset & removed!" -ForegroundColor Green
        Write-Host " - Temporary Request : Removed (room/beds freed up)" -ForegroundColor White
        Write-Host " - Guest Profile     : Removed" -ForegroundColor White
        Write-Host " - Payment Records   : Cleared" -ForegroundColor White
    } else {
        Write-Host " [SUCCESS] Student $RegNo renewal details have been reset successfully!" -ForegroundColor Green
        Write-Host " - Check-in Date     : $CheckInDate" -ForegroundColor White
        Write-Host " - Renewal Date      : $RenewalDate" -ForegroundColor White
        Write-Host " - Remaining Days    : (Recalculated dynamically from today)" -ForegroundColor White
        Write-Host " - Renewal Requests  : Cleared (Warden Renewals Tab Reset)" -ForegroundColor White
        Write-Host " - Renewal Payments  : Cleared (Warden Payments Tab Reset)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "Please refresh (Ctrl + F5) your app to see the updated countdown/status." -ForegroundColor Cyan
} catch {
    Write-Host " [ERROR] Failed to execute reset script: $_" -ForegroundColor Red
}
