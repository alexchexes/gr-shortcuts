@echo off
setlocal

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\check-update.ps1"

echo.
pause
