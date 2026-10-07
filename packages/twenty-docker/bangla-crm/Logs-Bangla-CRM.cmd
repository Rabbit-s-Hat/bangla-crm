@echo off
rem Shows the logs (Ctrl+C to quit).
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bangla-crm.ps1" logs %*
echo.
pause