#!/usr/bin/env pwsh
# ============================================================
#  VStay Production Server — Quick Access Script
#  Usage:  .\server.ps1              → Opens SSH shell
#          .\server.ps1 logs         → Live frontend logs
#          .\server.ps1 logs-api     → Live backend logs
#          .\server.ps1 ps           → docker ps
#          .\server.ps1 restart      → Restart all containers
#          .\server.ps1 restart-web  → Restart frontend only
#          .\server.ps1 df           → Disk usage
#          .\server.ps1 pull         → Pull latest images & restart
# ============================================================

param(
    [string]$Command = ""
)

$KEY  = "$env:USERPROFILE\.ssh\vstay-prod-key.pem"
$HOST = "ubuntu@15.206.172.50"

function Run-Remote($cmd) {
    ssh -i $KEY -o StrictHostKeyChecking=no $HOST $cmd
}

switch ($Command) {
    "logs"        { ssh -i $KEY -o StrictHostKeyChecking=no $HOST "docker logs -f hostel_frontend --tail 100" }
    "logs-api"    { ssh -i $KEY -o StrictHostKeyChecking=no $HOST "docker logs -f hostel_backend --tail 100" }
    "ps"          { Run-Remote "docker ps --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}'" }
    "restart"     { Run-Remote "cd /home/ubuntu/hostel-app && docker compose restart" }
    "restart-web" { Run-Remote "docker restart hostel_frontend" }
    "df"          { Run-Remote "df -h && echo '' && docker system df" }
    "pull"        {
        Write-Host "Pulling latest images and restarting..." -ForegroundColor Cyan
        Run-Remote "cd /home/ubuntu/hostel-app && docker compose pull && docker compose up -d"
    }
    default       {
        Write-Host ""
        Write-Host "  Connecting to VStay Production Server..." -ForegroundColor Cyan
        Write-Host "  IP: 15.206.172.50  |  User: ubuntu" -ForegroundColor DarkGray
        Write-Host ""
        ssh -i $KEY -o StrictHostKeyChecking=no $HOST
    }
}
