@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%send_to_gigafile.ps1"

if not exist "%PS_SCRIPT%" (
    echo [ERROR] send_to_gigafile.ps1 not found: "%PS_SCRIPT%"
    pause
    exit /b 1
)

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_SCRIPT%" %*
endlocal
