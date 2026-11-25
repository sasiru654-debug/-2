@echo off
chcp 932 > nul
setlocal
echo ====================================================================
echo  photoinfo:// プロトコル登録（Excelリンクからの直接起動用）
echo ====================================================================
reg add "HKCU\Software\Classes\photoinfo" /ve /d "URL:PhotoInfo Protocol" /f
reg add "HKCU\Software\Classes\photoinfo" /v "URL Protocol" /d "" /f
reg add "HKCU\Software\Classes\photoinfo\shell\open\command" /ve /d "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File \"D:\PhotoTools\common\OpenFromProtocol.ps1\" -Uri \"%%1\"" /f
echo.
echo [OK] レジストリへの登録が完了しました。
pause
