@echo off
rem Downloads, backs up, then switches to the newest release. Options: -Version 0.2.0  -AllowDowngrade
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bangla-crm.ps1" update %*
echo.
pause