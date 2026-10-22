@echo off
rem Starts BanglaCRM and opens it in the browser.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bangla-crm.ps1" start %*
echo.
pause