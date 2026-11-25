@echo off
chcp 932 >nul
cd /d "%~dp0"
powershell -STA -ExecutionPolicy Bypass -File "%~dp0common\RegisterProtocol.ps1"
pause
