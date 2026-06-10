# VStay Docker Build and Push Automation Script
# Make sure you are logged into Docker Hub: docker login

$DOCKER_USERNAME = Read-Host -Prompt "Enter your Docker Hub Username"

if ([string]::IsNullOrEmpty($DOCKER_USERNAME)) {
    Write-Error "Docker Hub Username cannot be empty!"
    exit 1
}

Write-Host "`n=== Step 1: Cleaning Flutter Project ===" -ForegroundColor Cyan
flutter clean

if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter clean failed!"
    exit $LASTEXITCODE
}

Write-Host "`n=== Step 2: Getting Flutter Dependencies ===" -ForegroundColor Cyan
flutter pub get

if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter pub get failed!"
    exit $LASTEXITCODE
}

Write-Host "`n=== Step 3: Building Flutter Web Application ===" -ForegroundColor Cyan
flutter build web --release --no-wasm-dry-run

if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter web build failed!"
    exit $LASTEXITCODE
}

Write-Host "`n=== Step 4: Starting Docker Compose Build ===" -ForegroundColor Cyan
docker compose up -d --build backend frontend

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

Write-Host "`n=== Step 7: Pushing Backend Image to Docker Hub ===" -ForegroundColor Cyan
docker push "${DOCKER_USERNAME}/vstay-backend:latest"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to push Backend image! Are you logged in? (Run 'docker login')"
    exit $LASTEXITCODE
}

Write-Host "`n=== Step 8: Pushing Frontend Image to Docker Hub ===" -ForegroundColor Cyan
docker push "${DOCKER_USERNAME}/vstay-frontend:latest"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to push Frontend image! Are you logged in? (Run 'docker login')"
    exit $LASTEXITCODE
}

Write-Host "`n=== Step 9: Warming Up Backend Cache ===" -ForegroundColor Cyan
Write-Host "Waiting 5 seconds for containers to start..." -ForegroundColor Gray
Start-Sleep -Seconds 5

# Pre-seed the locations cache so the first real user never waits 19 seconds
$warmupUrl = "http://localhost:8081/rooms/fetch_locations.php"
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

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " SUCCESS: Images pushed to Docker Hub!" -ForegroundColor Green
Write-Host " Backend:  ${DOCKER_USERNAME}/vstay-backend:latest" -ForegroundColor Green
Write-Host " Frontend: ${DOCKER_USERNAME}/vstay-frontend:latest" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host " NOTE: Both files are now set to PRODUCTION." -ForegroundColor Yellow
Write-Host " To go back to LOCAL, change these 2 files:" -ForegroundColor Yellow
Write-Host "   api_service.dart  -> baseUrl = 'http://localhost:8081/'" -ForegroundColor Yellow
Write-Host "   web/config.json   -> api_url  = 'http://localhost:8081/'" -ForegroundColor Yellow
Write-Host ""

