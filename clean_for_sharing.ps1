# VStay Project Cleanup Script for sharing (Windows PowerShell)
Write-Host "=== Starting Project Cleanup for Sharing ===" -ForegroundColor Cyan

# 1. Run Flutter Clean
Write-Host "`n[1/3] Cleaning Flutter build caches..." -ForegroundColor Yellow
if (Get-Command "flutter" -ErrorAction SilentlyContinue) {
    flutter clean
} else {
    Write-Warning "Flutter SDK not found in PATH! Skipping flutter clean."
}

# 2. Define files and directories to clean
$itemsToDelete = @(
    # Ephemeral logs & SQL backups
    "*.log",
    "stay_simats*.sql",
    "response.json",
    "schema.sql",
    
    # Empty database directories or test artifacts
    "database",
    
    # Scratch or obsolete PHP scripts at root level
    "cleanup_payments.php",
    "fix_warden_passwords.php",
    "get_wardens_creds.php",
    "list_mapping_staff.php",
    "update_mapping_table.php",
    "update_venkatesh.php",
    
    # Obsolete Docker builder configurations
    "Dockerfile.android_build"
)

# 3. Perform cleanup
Write-Host "`n[2/3] Deleting root-level temporary & duplicate files..." -ForegroundColor Yellow
foreach ($pattern in $itemsToDelete) {
    if (Test-Path $pattern) {
        Remove-Item $pattern -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Deleted: $pattern" -ForegroundColor Gray
    }
}

# 4. Success message
Write-Host "`n[3/3] Project directory is now fully clean!" -ForegroundColor Green
Write-Host "You can now zip and share the folder to run on iOS/Mac." -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
