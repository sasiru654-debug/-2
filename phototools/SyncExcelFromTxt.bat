@echo off
chcp 932 >nul
cd /d "%~dp0"
powershell -STA -ExecutionPolicy Bypass -File "%~dp0workflow\SyncExcelFromTxt.ps1"
pause
