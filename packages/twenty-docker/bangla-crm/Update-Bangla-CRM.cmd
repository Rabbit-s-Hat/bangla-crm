@echo off
rem Backs up, then installs the newest release. Option: -Version 0.2.0
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bangla-crm.ps1" update %*
echo.
pause