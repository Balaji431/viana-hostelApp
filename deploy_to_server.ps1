# ============================================================
#  VStay - Production Deploy Script
#  Pulls the latest images from Docker Hub and goes live.
#  Run this AFTER build_and_push.ps1 has finished successfully.
#
#  Usage:  .\deploy_to_server.ps1
# ============================================================

# Add optional parameter to force deploy if sentinel was consumed
param(
    [switch]$Force
)

$KEY        = if (Test-Path (Join-Path $PSScriptRoot "vstay-prod-key.pem")) { Join-Path $PSScriptRoot "vstay-prod-key.pem" } else { "$env:USERPROFILE\.ssh\vstay-prod-key.pem" }
$SERVER     = "ubuntu@15.206.172.50"
$APP_DIR    = "/home/ubuntu/hostel-app"
$START_TIME = Get-Date
$SENTINEL   = Join-Path $PSScriptRoot ".build_push_ok"

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  VStay Production Deploy"                    -ForegroundColor Cyan
Write-Host "  Server : 15.206.172.50"                     -ForegroundColor DarkGray
Write-Host "  Path   : $APP_DIR"                          -ForegroundColor DarkGray
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# -- Sentinel status check (non-blocking) -
Write-Host "=== Pre-flight: Checking build status ===" -ForegroundColor Cyan
if (Test-Path $SENTINEL) {
    $sentinelInfo = Get-Content $SENTINEL -Raw
    Write-Host "  Sentinel OK: $($sentinelInfo.Trim())" -ForegroundColor Green
} else {
    Write-Host "  No sentinel found - deploying latest images from Docker Hub directly." -ForegroundColor Yellow
}

# Step 1: Verify SSH connection
Write-Host "`n=== Step 1: Verifying server connection ===" -ForegroundColor Cyan
$ping = & ssh -i "$KEY" -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=15 $SERVER "echo OK" 2>&1
$pingText = ($ping | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $pingText -notmatch "OK") {
    Write-Error "Cannot reach server ($SERVER). Output: $pingText"
    exit 1
}
Write-Host "  Server reachable." -ForegroundColor Green

# Step 2: Pull latest images
Write-Host "`n=== Step 2: Pulling latest images from Docker Hub ===" -ForegroundColor Cyan
Write-Host "  Downloading image layers from Docker Hub (please wait 30-60s)..." -ForegroundColor Yellow
& ssh -i "$KEY" -o StrictHostKeyChecking=no -o BatchMode=yes $SERVER "cd $APP_DIR && docker compose pull frontend backend websocket"
if ($LASTEXITCODE -ne 0) {
    Write-Error "docker compose pull failed."
    exit 1
}
Write-Host "  Images pulled successfully." -ForegroundColor Green

# Step 3: Restart containers
Write-Host "`n=== Step 3: Restarting containers ===" -ForegroundColor Cyan
& ssh -i "$KEY" -o StrictHostKeyChecking=no -o BatchMode=yes $SERVER "cd $APP_DIR && docker compose up -d --no-build frontend backend websocket redis"
if ($LASTEXITCODE -ne 0) {
    Write-Error "docker compose up failed."
    exit 1
}
Write-Host "  Containers restarted." -ForegroundColor Green

# Step 4: Wait for nginx
Write-Host "`n=== Step 4: Waiting for nginx to be ready ===" -ForegroundColor Cyan
Start-Sleep -Seconds 4

# Step 5: Verify response headers
Write-Host "`n=== Step 5: Verifying response headers ===" -ForegroundColor Cyan
$headers = & ssh -i "$KEY" -o StrictHostKeyChecking=no -o BatchMode=yes $SERVER "curl -sI http://localhost:8080/ | grep -i 'HTTP/\|cache-control\|expires\|pragma\|content-encoding'"
Write-Host $headers -ForegroundColor DarkGray

$cacheLines = @($headers -split "`n" | Where-Object { $_ -imatch "cache-control" })
if ($cacheLines.Count -eq 1) {
    Write-Host "  Cache-Control: single header confirmed." -ForegroundColor Green
} elseif ($cacheLines.Count -gt 1) {
    Write-Warning "  Cache-Control is still duplicated ($($cacheLines.Count) entries)!"
} else {
    Write-Warning "  No Cache-Control header found."
}

# Step 6: Live container status
Write-Host "`n=== Step 6: Container status ===" -ForegroundColor Cyan
& ssh -i "$KEY" -o StrictHostKeyChecking=no -o BatchMode=yes $SERVER "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'"

# Consume the sentinel now that deployment is 100% complete
if (Test-Path $SENTINEL) {
    Remove-Item $SENTINEL -Force -ErrorAction SilentlyContinue
    Write-Host "  Sentinel consumed (single-use)." -ForegroundColor DarkGray
}

# Done
$elapsed = [math]::Round(((Get-Date) - $START_TIME).TotalSeconds, 1)
Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  DEPLOYED SUCCESSFULLY in ${elapsed}s"       -ForegroundColor Green
Write-Host "  Live at: https://vstay.saveetha.com"        -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
