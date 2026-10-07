@echo off
rem Saves database, uploaded files and settings into the backups folder.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bangla-crm.ps1" backup %*
echo.
pause