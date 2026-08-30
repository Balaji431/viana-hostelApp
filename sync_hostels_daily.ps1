# ==============================================================================
# Hostels Daily Synchronization Script (PowerShell)
# Synchronizes room availability, capacities, and holds from VStudy Live API.
#
# USAGE EXAMPLES:
#   1. Run sync manually right now:
#      powershell -ExecutionPolicy Bypass -File .\sync_hostels_daily.ps1
#
#   2. Install automatic daily midnight (12:00 AM) Scheduled Task:
#      powershell -ExecutionPolicy Bypass -File .\sync_hostels_daily.ps1 -InstallTask
#
#   3. Check scheduled task status:
#      powershell -ExecutionPolicy Bypass -File .\sync_hostels_daily.ps1 -Status
#
#   4. Remove scheduled task:
#      powershell -ExecutionPolicy Bypass -File .\sync_hostels_daily.ps1 -RemoveTask
# ==============================================================================

[CmdletBinding()]
param (
    [switch]$InstallTask,
    [switch]$RemoveTask,
    [switch]$Status,
    [switch]$Manual
)

$TaskName = "VStay_Hostels_Daily_Midnight_Sync"
$AppDir   = "c:\xampp\htdocs\hostelapp"
$PhpScript = "$AppDir\hostel_backend\rooms\sync_hostel_rooms_daily.php"
$LogDir    = "$AppDir\hostel_backend\logs"
$LogFile   = "$LogDir\daily_sync.log"

# Locate PHP Binary
$PhpExe = "C:\xampp\php\php.exe"
if (-not (Test-Path $PhpExe)) {
    $phpCmd = Get-Command php -ErrorAction SilentlyContinue
    if ($phpCmd) {
        $PhpExe = $phpCmd.Source
    }
}
if (-not $PhpExe -or -not (Test-Path $PhpExe)) {
    Write-Host "[ERROR] Could not find php.exe. Please ensure XAMPP PHP is installed at C:\xampp\php\php.exe" -ForegroundColor Red
    exit 1
}

# Ensure Logs Directory Exists
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# ------------------------------------------------------------------------------
# 1. REMOVE SCHEDULED TASK
# ------------------------------------------------------------------------------
if ($RemoveTask) {
    Write-Host "`n=== Removing Scheduled Task: $TaskName ===" -ForegroundColor Yellow
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Write-Host "[SUCCESS] Scheduled Task '$TaskName' has been removed." -ForegroundColor Green
    } catch {
        Write-Host "[INFO] Scheduled Task '$TaskName' was not found or already removed." -ForegroundColor Gray
    }
    exit 0
}

# ------------------------------------------------------------------------------
# 2. CHECK TASK STATUS
# ------------------------------------------------------------------------------
if ($Status) {
    Write-Host "`n=== Checking Status of '$TaskName' ===" -ForegroundColor Cyan
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        $info = Get-ScheduledTaskInfo -TaskName $TaskName
        Write-Host "Task State      : " -NoNewline; Write-Host $task.State -ForegroundColor Green
        Write-Host "Last Run Time   : " -NoNewline; Write-Host $info.LastRunTime -ForegroundColor Yellow
        Write-Host "Last Result     : " -NoNewline; Write-Host $info.LastTaskResult -ForegroundColor White
        Write-Host "Next Run Time   : " -NoNewline; Write-Host $info.NextRunTime -ForegroundColor Cyan
    } catch {
        Write-Host "[NOTICE] Scheduled Task is not currently registered." -ForegroundColor Yellow
        Write-Host "To register it, run: .\sync_hostels_daily.ps1 -InstallTask" -ForegroundColor Gray
    }

    if (Test-Path $LogFile) {
        Write-Host "`n--- Recent Log Output (Last 15 lines) ---" -ForegroundColor Gray
        Get-Content $LogFile -Tail 15
    }
    exit 0
}

# ------------------------------------------------------------------------------
# 3. INSTALL SCHEDULED TASK (Runs Daily at 12:00 AM / Midnight)
# ------------------------------------------------------------------------------
if ($InstallTask) {
    Write-Host "`n=======================================================" -ForegroundColor Cyan
    Write-Host "  Installing Windows Scheduled Task: $TaskName" -ForegroundColor Cyan
    Write-Host "  Schedule: Daily at 12:00:00 AM (Midnight / 00:00)" -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Cyan

    $taskCommand = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -Command `& '$PhpExe' -f '$PhpScript' *>> '$LogFile'"

    # Try schtasks.exe (standard across all Windows editions)
    $schResult = & schtasks.exe /Create /TN $TaskName /TR "$taskCommand" /SC DAILY /ST 00:00 /F 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n[SUCCESS] Scheduled Task '$TaskName' installed successfully!" -ForegroundColor Green
        Write-Host "It will trigger automatically every day at 12:00 AM (Midnight)." -ForegroundColor White
        Write-Host "Log file destination: $LogFile" -ForegroundColor Gray
    } else {
        Write-Host "`n[ERROR] Could not register scheduled task: $schResult" -ForegroundColor Red
        Write-Host "Please run PowerShell as Administrator and retry." -ForegroundColor Yellow
        exit 1
    }
    exit 0
}

# ------------------------------------------------------------------------------
# 4. MANUAL SYNCHRONIZATION EXECUTION (Default)
# ------------------------------------------------------------------------------
Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "       HOSTELS LIVE SYNCHRONIZATION (MANUAL RUN)        " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "PHP Script : $PhpScript" -ForegroundColor Gray
Write-Host "Log Target : $LogFile" -ForegroundColor Gray
Write-Host "Timestamp  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" -ForegroundColor Gray

$StartTime = Get-Date

# Execute PHP script and mirror output to both console and logfile
$LogHeader = "`n`n=======================================================`nRUN AT: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n======================================================="
Add-Content -Path $LogFile -Value $LogHeader

& $PhpExe -f $PhpScript 2>&1 | ForEach-Object {
    Write-Host $_
    Add-Content -Path $LogFile -Value $_
}

$ExitCode = $LASTEXITCODE
$Duration = [math]::Round(((Get-Date) - $StartTime).TotalSeconds, 2)

if ($ExitCode -eq 0) {
    Write-Host "`n[SUCCESS] Synchronization completed successfully in $Duration seconds!" -ForegroundColor Green
} else {
    Write-Host "`n[ERROR] Synchronization finished with exit code: $ExitCode" -ForegroundColor Red
}

Write-Host "`n💡 TIP: To schedule this to run automatically every night at 12:00 AM, run:" -ForegroundColor Yellow
Write-Host "   powershell -ExecutionPolicy Bypass -File .\sync_hostels_daily.ps1 -InstallTask`n" -ForegroundColor White
