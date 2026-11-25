@echo off
chcp 932 > nul
setlocal
set "SCRIPT_DIR=%~dp0"
set "TARGET_BAT=%SCRIPT_DIR%launch_gigafile.bat"
set "TARGET_PS1=%SCRIPT_DIR%send_to_gigafile.ps1"

if not exist "%TARGET_PS1%" (
    echo [ERROR] send_to_gigafile.ps1 が見つかりません: "%SCRIPT_DIR%"
    pause
    exit /b 1
)

if not exist "%TARGET_BAT%" (
    echo [ERROR] launch_gigafile.bat が見つかりません: "%SCRIPT_DIR%"
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$dir = '%SCRIPT_DIR%'.TrimEnd('\');" ^
  "Get-ChildItem -LiteralPath $dir -File | Unblock-File -ErrorAction SilentlyContinue;" ^
  "$sendTo = [Environment]::GetFolderPath('SendTo');" ^
  "$lnkName = [char]0x30AE + [char]0x30AC + [char]0x30D5 + [char]0x30A1 + [char]0x30A4 + [char]0x30EB + [char]0x4FBF + [char]0x306B + [char]0x9001 + [char]0x308B + '.lnk';" ^
  "$lnkPath = Join-Path $sendTo $lnkName;" ^
  "$ws = New-Object -ComObject WScript.Shell;" ^
  "$sc = $ws.CreateShortcut($lnkPath);" ^
  "$sc.TargetPath = Join-Path $dir 'launch_gigafile.bat';" ^
  "$sc.WorkingDirectory = $dir;" ^
  "$sc.IconLocation = 'shell32.dll,14';" ^
  "$sc.Save();" ^
  "Write-Host ('[OK] 「送る」ショートカットを登録しました: ' + $lnkPath) -ForegroundColor Green;"

if errorlevel 1 (
    echo [ERROR] 登録に失敗しました。
    pause
    exit /b 1
)

echo.
echo セットアップが完了しました！
pause
endlocal
