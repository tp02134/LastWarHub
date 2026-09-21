@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\StopLastwarHub.ps1"
timeout /t 2 /nobreak >nul
