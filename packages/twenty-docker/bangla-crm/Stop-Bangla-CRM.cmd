@echo off
rem Stops BanglaCRM. Your data is kept.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bangla-crm.ps1" stop %*
echo.
pause