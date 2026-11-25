@echo off
chcp 932 > nul
setlocal
set "TARGET_PATH=%~1"
if "%TARGET_PATH%"=="" set "TARGET_PATH=%cd%"
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "D:\PhotoTools\editor\PhotoInfoEditor.ps1" -TargetPath "%TARGET_PATH%"
if errorlevel 1 (
    echo [ERROR] PhotoInfoEditor の起動に失敗しました。logs フォルダを確認してください。
    pause
)
