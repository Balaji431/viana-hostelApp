@echo off
:: Ensure working directory is the batch file directory
cd /d "%~dp0"

title Android Launcher Icon Generator - SIMATS STAY
echo ========================================================
echo Running Android Launcher Icon Generator...
echo ========================================================
echo.

echo [1/2] Installing/verifying Dart dependencies...
call flutter pub get
echo.

echo [2/2] Running Dart Icon Generator...
call dart run bin/generate_icons.dart

echo.
echo ========================================================
echo Execution complete.
echo ========================================================
echo.
pause
