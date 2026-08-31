# VStay Docker Build and Push Automation Script
# Make sure you are logged into Docker Hub: docker login
param(
    [string]$DockerUsername = "balaji182"
)

$DOCKER_USERNAME = if ($DockerUsername) { $DockerUsername.Trim() } else { "balaji182" }

if ([string]::IsNullOrEmpty($DOCKER_USERNAME)) {
    Write-Error "Docker Hub Username cannot be empty!"
    exit 1
}

Write-Host "`n=== Step 1: Cleaning Old Build Directory ===" -ForegroundColor Cyan
if (Test-Path "build") {
    try {
        Remove-Item -Path "build" -Recurse -Force -ErrorAction Stop
        Write-Host "  Successfully deleted old build directory." -ForegroundColor Gray
    } catch {
        Write-Host "  Build folder locked by background process. Bypassing lock..." -ForegroundColor Yellow
        # Stop background dart processes holding locks
        Get-Process -Name dart, flutter_tools -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300

        # Rename locked folder out of the way so flutter build gets a fresh path
        $tempBuild = "build_old_" + (Get-Date -Format "HHmmss")
        try {
            Rename-Item -Path "build" -NewName $tempBuild -ErrorAction SilentlyContinue
            Remove-Item -Path $tempBuild -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  Bypassed locked build folder via path rotation." -ForegroundColor Green
        } catch {
            Write-Host "  Path rotation applied." -ForegroundColor Gray
        }
    }
}

# Remove any stale build-success sentinel from a previous run
$SENTINEL = Join-Path $PSScriptRoot ".build_push_ok"
if (Test-Path $SENTINEL) { Remove-Item $SENTINEL -Force }

Write-Host "`n=== Step 2: Getting Flutter Dependencies ===" -ForegroundColor Cyan
flutter pub get

if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter pub get failed!"
    exit $LASTEXITCODE
}

Write-Host "`n=== Step 3: Building Flutter Web Application ===" -ForegroundColor Cyan
flutter build web --release --optimization-level=4 --no-source-maps --no-wasm-dry-run

if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter web build failed!"
    exit $LASTEXITCODE
}

# -- Step 3a: Enforce web/index.html as the single source of truth --------------
# flutter build web regenerates build/web/index.html from its own template.
# We immediately overwrite it with our hand-maintained web/index.html so that
# lazy-loading, security settings, and other customisations are always deployed.
Write-Host "`n=== Step 3a: Overwriting build/web/index.html from web/index.html ===" -ForegroundColor Cyan
$srcIndex = Join-Path $PSScriptRoot "web\index.html"
$dstIndex = Join-Path $PSScriptRoot "build\web\index.html"
if (Test-Path $srcIndex) {
    Copy-Item -Path $srcIndex -Destination $dstIndex -Force
    Write-Host "  build/web/index.html replaced from source." -ForegroundColor Green
} else {
    Write-Error "  web/index.html not found - aborting to prevent deploying flutter-generated default."
    exit 1
}

# -- Rewrite flutter_service_worker.js to a no-op (prevents stale-cache issues) -
$flutterServiceWorkerPath = Join-Path $PSScriptRoot "build\web\flutter_service_worker.js"
if (Test-Path $flutterServiceWorkerPath) {
    @'
'use strict';

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});
'@ | Set-Content -Path $flutterServiceWorkerPath -Encoding UTF8
}

# -- Step 3b: Cache-bust all icon/favicon references in index.html and manifest --
# Browsers cache PNG icons with max-age=1year (immutable). Adding ?v=BUILD_VER
# forces browsers to fetch the new file on the next visit after a redeploy.
Write-Host "`n=== Step 3b: Injecting cache-buster version into icon references ===" -ForegroundColor Cyan
$BUILD_VER = Get-Date -Format "yyyyMMddHHmmss"
Write-Host "  Build version: $BUILD_VER" -ForegroundColor DarkGray

$indexPath    = Join-Path $PSScriptRoot "build\web\index.html"
$manifestPath = Join-Path $PSScriptRoot "build\web\manifest.json"

if (Test-Path $indexPath) {
    $html = Get-Content $indexPath -Raw
    # Regex uses double-quoted strings so PowerShell variable expansion works.
    # Character class [^"'] uses backslash-escaped double-quote inside double-quoted string.
    $html = $html -replace 'favicon\.png(\?v=[^\s"]+)?', "favicon.png?v=$BUILD_VER"
    $html = $html -replace '(icons/Icon-[^\s"]+\.png)(\?v=[^\s"]+)?', ('$1' + "?v=$BUILD_VER")
    Set-Content -Path $indexPath -Value $html -Encoding UTF8 -NoNewline
    Write-Host "  index.html updated." -ForegroundColor Green
}

if (Test-Path $manifestPath) {
    $mf = Get-Content $manifestPath -Raw
    $mf = $mf -replace '(icons/Icon-[^\s"]+\.png)(\?v=[^\s"]+)?', ('$1' + "?v=$BUILD_VER")
    Set-Content -Path $manifestPath -Value $mf -Encoding UTF8 -NoNewline
    Write-Host "  manifest.json updated." -ForegroundColor Green
}

# -- Step 3c: Inject canvasKitVariant:chromium into flutter_bootstrap.js ---------
# Chromium browsers (Chrome, Edge, Brave) download the lighter ~1.0 MB canvaskit.wasm
# instead of the full ~1.6 MB. Safari and Firefox automatically receive the full build.
Write-Host "`n=== Step 3c: Injecting canvasKitVariant:chromium into flutter_bootstrap.js ===" -ForegroundColor Cyan
$bootstrapPath = Join-Path $PSScriptRoot "build\web\flutter_bootstrap.js"
if (Test-Path $bootstrapPath) {
    $bootstrap = Get-Content $bootstrapPath -Raw
    # Use -replace with a double-quoted pattern. \s is valid regex inside double-quoted strings.
    # Replacement uses single-quoted string so $1 is treated as a regex back-reference, not a variable.
    $pattern     = '"renderer"\s*:\s*"canvaskit"'
    $replacement = '"renderer":"canvaskit","canvasKitVariant":"chromium"'
    $patched     = $bootstrap -replace $pattern, $replacement
    if ($patched -ne $bootstrap) {
        Set-Content -Path $bootstrapPath -Value $patched -Encoding UTF8 -NoNewline
        Write-Host "  flutter_bootstrap.js patched: canvasKitVariant=chromium injected." -ForegroundColor Green
    } else {
        Write-Host "  flutter_bootstrap.js: pattern not matched or already patched (skipped)." -ForegroundColor Yellow
    }
} else {
    Write-Warning "  flutter_bootstrap.js not found - skipping canvasKitVariant injection."
}

Write-Host "`n=== Step 4: Starting Docker Compose Build ===" -ForegroundColor Cyan
docker compose up -d --build backend frontend websocket redis

if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker Compose build failed!"
    exit $LASTEXITCODE
}

Write-Host "`n=== Step 5: Building Backend Docker Image ===" -ForegroundColor Cyan
docker build -t "${DOCKER_USERNAME}/vstay-backend:latest" -f Dockerfile.backend .

if ($LASTEXITCODE -ne 0) {
    Write-Error "Backend Docker build failed!"
    exit $LASTEXITCODE
}

Write-Host "`n=== Step 6: Building Frontend Docker Image ===" -ForegroundColor Cyan
docker build -t "${DOCKER_USERNAME}/vstay-frontend:latest" -f Dockerfile.frontend .

if ($LASTEXITCODE -ne 0) {
    Write-Error "Frontend Docker build failed!"
    exit $LASTEXITCODE
}

Write-Host "`n=== Step 6a: Building WebSocket Docker Image ===" -ForegroundColor Cyan
docker build -t "${DOCKER_USERNAME}/vstay-websocket:latest" -f Dockerfile.websocket_php .

if ($LASTEXITCODE -ne 0) {
    Write-Error "WebSocket Docker build failed!"
    exit $LASTEXITCODE
}

# Helper function to push Docker images with automatic retry on transient network/registry timeouts
function Push-DockerImageWithRetry([string]$ImageName, [int]$MaxAttempts = 3) {
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-Host "  Pushing $ImageName (Attempt $attempt of $MaxAttempts)..." -ForegroundColor Gray
        docker push $ImageName
        if ($LASTEXITCODE -eq 0) {
            return $true
        }
        Write-Warning "  Push failed on attempt $attempt. Retrying in 5 seconds..."
        Start-Sleep -Seconds 5
    }
    return $false
}

Write-Host "`n=== Step 7: Pushing Backend Image to Docker Hub ===" -ForegroundColor Cyan
if (-not (Push-DockerImageWithRetry "${DOCKER_USERNAME}/vstay-backend:latest")) {
    Write-Error "Failed to push Backend image! Are you logged in? (Run 'docker login')"
    exit 1
}

Write-Host "`n=== Step 8: Pushing Frontend Image to Docker Hub ===" -ForegroundColor Cyan
if (-not (Push-DockerImageWithRetry "${DOCKER_USERNAME}/vstay-frontend:latest")) {
    Write-Error "Failed to push Frontend image! Are you logged in? (Run 'docker login')"
    exit 1
}

Write-Host "`n=== Step 8a: Pushing WebSocket Image to Docker Hub ===" -ForegroundColor Cyan
if (-not (Push-DockerImageWithRetry "${DOCKER_USERNAME}/vstay-websocket:latest")) {
    Write-Error "Failed to push WebSocket image! Are you logged in? (Run 'docker login')"
    exit 1
}


Write-Host "`n=== Step 9: Warming Up Backend Cache ===" -ForegroundColor Cyan
Write-Host "Waiting 5 seconds for containers to start..." -ForegroundColor Gray
Start-Sleep -Seconds 5

# Pre-warm room master (page 1) so first real user never waits
$warmupUrl = "http://localhost:8081/rooms/fetch_room_master.php?page=1&limit=100"
Write-Host "Warming up: $warmupUrl" -ForegroundColor Gray
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebRequest -Uri $warmupUrl -UseBasicParsing -TimeoutSec 60
    $sw.Stop()
    $secs = [math]::Round($sw.ElapsedMilliseconds / 1000, 1)
    Write-Host "  Cache warm-up done in ${secs}s - Status: $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Warning "Cache warm-up failed (non-critical): $_"
}

# -- Write sentinel file so deploy_to_server.ps1 knows this run succeeded --------
"$DOCKER_USERNAME $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')" | Set-Content -Path $SENTINEL -Encoding UTF8
Write-Host "  Build sentinel written." -ForegroundColor DarkGray

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " SUCCESS: Images pushed to Docker Hub!"  -ForegroundColor Green
Write-Host " Backend:   ${DOCKER_USERNAME}/vstay-backend:latest"   -ForegroundColor Green
Write-Host " Frontend:  ${DOCKER_USERNAME}/vstay-frontend:latest"  -ForegroundColor Green
Write-Host " WebSocket: ${DOCKER_USERNAME}/vstay-websocket:latest" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host " NOTE: Both files are now set to PRODUCTION." -ForegroundColor Yellow
Write-Host " To go back to LOCAL, change these 2 files:"  -ForegroundColor Yellow
Write-Host "   api_service.dart  -> baseUrl = 'http://localhost:8081/'" -ForegroundColor Yellow
Write-Host "   web/config.json   -> api_url  = 'http://localhost:8081/'" -ForegroundColor Yellow
Write-Host ""
