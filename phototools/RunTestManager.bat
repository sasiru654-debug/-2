@echo off
chcp 932 >nul
cd /d "%~dp0"
powershell -STA -ExecutionPolicy Bypass -File "%~dp0tests\TestManager.ps1"
pause
