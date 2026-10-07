@echo off
rem Replaces ALL data with a backup. Drag a backup folder onto this file, or it asks which one.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bangla-crm.ps1" restore %*
echo.
pause