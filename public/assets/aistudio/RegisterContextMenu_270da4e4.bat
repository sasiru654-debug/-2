@echo off
chcp 932 >nul
setlocal

echo ==================================================
echo PhotoTools Context Menu Registration
echo ==================================================
echo.

set "TOOL_DIR=%~dp0"
if "%TOOL_DIR:~-1%"=="\" set "TOOL_DIR=%TOOL_DIR:~0,-1%"
set "TARGET_BAT=%TOOL_DIR%\MakePhotoInfo.bat"

if not exist "%TARGET_BAT%" (
    echo [ERROR] MakePhotoInfo.bat not found: "%TARGET_BAT%"
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$label = [char]0x88AB + [char]0x5199 + [char]0x4F53 + [char]0x30D7 + [char]0x30ED + [char]0x30D1 + [char]0x30C6 + [char]0x30A3; $bat = '%TARGET_BAT%'; $keys = @('HKCU:\Software\Classes\Directory\Background\shell\PhotoToolsMakeInfo', 'HKCU:\Software\Classes\Directory\shell\PhotoToolsMakeInfo'); foreach ($k in $keys) { if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }; Set-ItemProperty -Path $k -Name '(Default)' -Value $label; Set-ItemProperty -Path $k -Name 'Icon' -Value 'shell32.dll,70'; $cmdKey = $k + '\command'; if (-not (Test-Path $cmdKey)) { New-Item -Path $cmdKey -Force | Out-Null }; $arg = if ($k -like '*Background*') { '"' + $bat + '" "%%V"' } else { '"' + $bat + '" "%%1"' }; Set-ItemProperty -Path $cmdKey -Name '(Default)' -Value $arg }; Write-Host '[OK] Context menu updated.' -ForegroundColor Green"

echo.
pause
endlocal
