# VStay Project Cleanup Script for sharing & transport (Windows PowerShell)
Write-Host "=== Starting Project Cleanup for Sharing & Transport ===" -ForegroundColor Cyan

# 1. Clean Flutter build directory with path rotation if locked
Write-Host "`n[1/4] Cleaning Flutter build directory..." -ForegroundColor Yellow
if (Test-Path "build") {
    try {
        Remove-Item -Path "build" -Recurse -Force -ErrorAction Stop
        Write-Host "  Successfully deleted old build directory." -ForegroundColor Gray
    } catch {
        Write-Host "  Build folder locked. Bypassing lock via path rotation..." -ForegroundColor Yellow
        Get-Process -Name dart, flutter_tools -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
        $tempBuild = "build_old_" + (Get-Date -Format "HHmmss")
        try {
            Rename-Item -Path "build" -NewName $tempBuild -ErrorAction SilentlyContinue
            Remove-Item -Path $tempBuild -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

# Clean ephemeral and dependency caches
Remove-Item -Path ".dart_tool", ".flutter-plugins-dependencies" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "ios/Flutter/Generated.xcconfig", "ios/Flutter/flutter_export_environment.sh" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "ios/Pods", "ios/Podfile.lock", "ios/.symlinks" -Recurse -Force -ErrorAction SilentlyContinue

# 2. Define test & temporary checkup files/patterns to clean
$itemsToDelete = @(
    # Ephemeral logs, temporary docs & SQL backups
    "*.log",
    "stay_simats*.sql",
    "hostel_backup_*.sql",
    "response.json",
    "schema.sql",
    "data.json",
    "~$*.docx",
    "hostel.jpeg",
    "scratch",
    
    # Checkup & test PHP scripts in backend
    "cleanup_payments.php",
    "fix_warden_passwords.php",
    "get_wardens_creds.php",
    "list_mapping_staff.php",
    "update_mapping_table.php",
    "update_venkatesh.php",
    "hostel_backend/check_hostels.php",
    "hostel_backend/check_staff_id_2.php",
    "hostel_backend/check_staff_id_2_only.php",
    "hostel_backend/check_warden1.php",
    "hostel_backend/check_warden1_data.php",
    "hostel_backend/env_test.php",
    "hostel_backend/fcm_debug.txt",
    "hostel_backend/fcm_response.txt",
    "hostel_backend/find_warden1.php",
    "hostel_backend/list_all_users.php",
    "hostel_backend/token_debug.log",
    "hostel_backend/test_api_dump.php",
    "hostel_backend/test_api_count.php",
    "hostel_backend/test_api.php",
    "hostel_backend/staff/test_external_api.php",
    "hostel_backend/attendance/fcm_debug.txt",
    "hostel_backend/temp_ponni",
    
    # Temporary iOS downloaded plist files
    "ios/Flutter/GoogleService-Info (2).plist",
    "ios/Flutter/client_*.plist",
    
    # Obsolete Docker builder configurations
    "Dockerfile.android_build"
)

# 3. Perform cleanup
Write-Host "`n[2/4] Deleting temporary, test, checkup, dump & duplicate files..." -ForegroundColor Yellow
foreach ($pattern in $itemsToDelete) {
    if (Test-Path $pattern) {
        Remove-Item $pattern -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Deleted: $pattern" -ForegroundColor Gray
    }
}

# 4. Remove .DS_Store and build artifact residues
Write-Host "`n[3/4] Cleaning OS metadata files..." -ForegroundColor Yellow
Get-ChildItem -Path . -Include .DS_Store, Thumbs.db -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

# 5. Success message
Write-Host "`n[4/4] Project directory is now fully cleaned and streamlined!" -ForegroundColor Green
Write-Host "You can now zip and transport the folder to run anywhere (Mac/iOS/Windows/Linux)." -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
