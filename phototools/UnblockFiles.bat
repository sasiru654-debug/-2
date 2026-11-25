@echo off
chcp 932 >nul
cd /d "%~dp0"
powershell -STA -ExecutionPolicy Bypass -Command "Get-ChildItem -Recurse '%~dp0' | Unblock-File -ErrorAction SilentlyContinue"
echo Zone.Identifier unblocked successfully.
pause
