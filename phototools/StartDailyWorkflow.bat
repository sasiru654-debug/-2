@echo off
chcp 932 >nul
cd /d "%~dp0"
wscript.exe "%~dp0common\LaunchHidden.vbs" "%~dp0workflow\DailyWorkflow.ps1"
