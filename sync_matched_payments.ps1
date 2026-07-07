Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  SYNCING VSTUDY API & MATCHED PAYMENTS TABLE   " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

$isDockerRunning = $false
try {
    $dockerCheck = docker ps --filter "name=hostel_backend" --format "{{.Names}}"
    if ($dockerCheck -eq "hostel_backend") {
        $isDockerRunning = $true
    }
} catch {
    # Docker not running or not installed
}

if ($isDockerRunning) {
    Write-Host "[Docker] Running sync inside 'hostel_backend' container..." -ForegroundColor Green
    Write-Host "1. Syncing VStudy API payments to local DB..." -ForegroundColor Yellow
    docker exec hostel_backend php /var/www/html/paid_students_api/sync_all_vstudy_pages.php
    
    Write-Host "2. Syncing matched students..." -ForegroundColor Yellow
    docker exec hostel_backend php /var/www/html/paid_students_api/sync_matched_students.php
} else {
    Write-Host "[Local] Container not running. Using local XAMPP PHP to sync..." -ForegroundColor Yellow
    
    $phpPath = "php"
    if (Test-Path "C:\xampp\php\php.exe") {
        $phpPath = "C:\xampp\php\php.exe"
    }

    Write-Host "1. Syncing VStudy API payments to local DB..." -ForegroundColor Yellow
    & $phpPath hostel_backend\paid_students_api\sync_all_vstudy_pages.php
    
    Write-Host "`n2. Syncing matched students..." -ForegroundColor Yellow
    & $phpPath hostel_backend\paid_students_api\sync_matched_students.php
}

Write-Host "`n=== SYNCHRONIZATION COMPLETE! ===" -ForegroundColor Green
