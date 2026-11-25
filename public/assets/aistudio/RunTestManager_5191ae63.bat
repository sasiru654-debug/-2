@echo off
chcp 932 > nul
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "D:\PhotoTools\tests\TestManager.ps1"
if errorlevel 1 (
    echo [ERROR] TestManager の起動に失敗しました。logs フォルダを確認してください。
    pause
)
