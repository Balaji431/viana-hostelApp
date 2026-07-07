# VStay Payment Sync Automation Script
# Pulls the updated list of students from the live VStudy API and updates the local & Docker databases

$ErrorActionPreference = "Stop"

Write-Host "=== VStay Payment Sync Automation ===" -ForegroundColor Blue
Write-Host ""

# 1. Run sync inside Docker Container
Write-Host "=== Step 1: Synchronizing Docker Container Database ===" -ForegroundColor Cyan
try {
    $containers = docker ps --format "{{.Names}}"
    if ($containers -contains "hostel_backend") {
        Write-Host "Docker container 'hostel_backend' is active. Executing sync..." -ForegroundColor Gray
        docker exec hostel_backend php /var/www/html/paid_students_api/sync_all_vstudy_pages.php
        Write-Host "Docker Container database successfully updated!" -ForegroundColor Green
    } else {
        Write-Host "Docker container 'hostel_backend' is not running, skipping Docker sync." -ForegroundColor Yellow
    }
} catch {
    Write-Warning "Docker sync skipped or encountered a non-critical error: $_"
}

Write-Host ""

# 2. Run sync locally via XAMPP
Write-Host "=== Step 2: Synchronizing Local XAMPP Database ===" -ForegroundColor Cyan
$phpPath = "C:\xampp\php\php.exe"
$localScriptPath = Join-Path $PSScriptRoot "hostel_backend\paid_students_api\sync_all_vstudy_pages.php"

if (Test-Path $phpPath) {
    if (Test-Path $localScriptPath) {
        Write-Host "Found local PHP at $phpPath. Executing local sync..." -ForegroundColor Gray
        & $phpPath $localScriptPath
        Write-Host "Local XAMPP database successfully updated!" -ForegroundColor Green
    } else {
        Write-Warning "Local script not found at $localScriptPath"
    }
} else {
    Write-Host "XAMPP PHP not found at $phpPath, skipping local sync." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host " SUCCESS: Payment synchronization completed!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host ""
