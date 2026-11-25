@echo off
chcp 932 >nul
cd /d "%~dp0"
powershell -STA -ExecutionPolicy Bypass -File "%~dp0common\RegisterContextMenu.ps1"
pause
