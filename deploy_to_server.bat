@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy_to_server.ps1" %*
