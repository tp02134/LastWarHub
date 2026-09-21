@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\CheckRequirements.ps1" -Quiet
if errorlevel 1 (
  echo.
  echo Requirements are missing. Run Check-Requirements.cmd first.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\LaunchLastwarHub.ps1"
if errorlevel 1 (
  echo.
  echo LastwarHub could not start. Check data\local-server-error.log.
  pause
)
