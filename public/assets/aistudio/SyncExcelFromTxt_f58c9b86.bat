@echo off
chcp 932 > nul
setlocal
set "TARGET_PATH=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "D:\PhotoTools\workflow\SyncExcelFromTxt.ps1" -TargetPath "%TARGET_PATH%"
if errorlevel 1 (
    echo [ERROR] SyncExcelFromTxt の起動に失敗しました。logs フォルダを確認してください。
    pause
)
