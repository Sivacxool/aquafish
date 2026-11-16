@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Install-FirstBoot.ps1" -Kind ett32ue
set "INSTALL_EXIT=%errorlevel%"
pause
exit /b %INSTALL_EXIT%
