@echo off
rem Starts Bangla CRM and opens it in the browser.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bangla-crm.ps1" start %*
echo.
pause