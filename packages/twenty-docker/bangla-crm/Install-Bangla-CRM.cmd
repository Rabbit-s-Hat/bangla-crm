@echo off
rem Installs Bangla CRM on this computer (needs Docker Desktop; the installer offers to install it).
rem Options (from a Command Prompt in this folder): -Port 3100   -Lan   -Version 0.1.0
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-windows.ps1" %*
echo.
pause