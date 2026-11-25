#requires -Version 5.1
# ==============================================================================
# SyncExcelFromTxt.ps1 - 写真情報.txt 一括スキャン＆Excel台帳・履歴学習同期 (UTF-8 BOM / CRLF)
# ==============================================================================
param(
    [string]$TargetPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$CommonDir = Join-Path $RootDir "common"

. (Join-Path $CommonDir "LogHelper.ps1")
. (Join-Path $CommonDir "ConfigHelper.ps1")
. (Join-Path $CommonDir "SceneHelper.ps1")
. (Join-Path $CommonDir "XHelper.ps1")
. (Join-Path $CommonDir "PhotoInfoHelper.ps1")
. (Join-Path $CommonDir "ExcelHelper.ps1")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Initialize-PhotoLogger -RootDir $RootDir | Out-Null

try {
    Write-PhotoLog -Level "INFO" -Module "SyncExcelFromTxt" -Message "一括台帳同期ツールを起動します。" | Out-Null
    $config = Get-PhotoToolsConfig -RootDir $RootDir

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "台帳へ一括同期するルートフォルダ（作業フォルダまたはアーカイブフォルダ）を選択してください"
        if (Test-Path -LiteralPath $config.DevelopedRoot) {
            $fbd.SelectedPath = $config.DevelopedRoot
        }
        if ($fbd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-PhotoLog -Level "INFO" -Module "SyncExcelFromTxt" -Message "フォルダ選択がキャンセルされました。" | Out-Null
            exit 0
        }
        $TargetPath = $fbd.SelectedPath
    }

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        throw "指定されたパスが存在しません: $TargetPath"
    }

    Write-PhotoLog -Level "INFO" -Module "SyncExcelFromTxt" -Message "スキャン対象: $TargetPath" | Out-Null

    $rootItem = Get-Item -LiteralPath $TargetPath -ErrorAction SilentlyContinue
    $allDirs = @()
    if ($null -ne $rootItem -and $rootItem.PSIsContainer) {
        $allDirs += $rootItem
    }
    $allDirs += @(Get-ChildItem -LiteralPath $TargetPath -Directory -Recurse -ErrorAction SilentlyContinue)
    $leafDirs = @()
    foreach ($d in $allDirs) {
        if ($d.Name -match '^(System Volume Information|\$RECYCLE\.BIN|logs|data|tests|common|editor|workflow|gigafile)$') { continue }
        $subDirs = @(Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue)
        $hasTxt = Test-Path -LiteralPath (Join-Path $d.FullName "写真情報.txt")
        $hasFiles = @(Get-ChildItem -LiteralPath $d.FullName -File -ErrorAction SilentlyContinue).Count -gt 0
        if ($hasTxt -or ($subDirs.Count -eq 0 -and $hasFiles)) {
            $leafDirs += $d
        }
    }

    $records = @()
    $learnedCount = 0
    foreach ($dir in $leafDirs) {
        $info = Read-PhotoInfoTxt -FolderPath $dir.FullName -Config $config
        $records += $info
        if ($info.IsRegistered) {
            Update-SceneHistoryFromInfo -RootDir $RootDir -Info $info -Config $config
            Update-XHistoryFromInfo -RootDir $RootDir -Info $info -Config $config
            $learnedCount++
        }
    }

    if ($records.Count -gt 0) {
        Sync-RecordsToExcelLedger -Config $config -Records $records
    }

    $msg = "一括同期が完了しました。`n対象フォルダ数: $($records.Count) 件（うち情報登録済: $learnedCount 件 / 未登録: $($records.Count - $learnedCount) 件）"
    Write-PhotoLog -Level "INFO" -Module "SyncExcelFromTxt" -Message $msg | Out-Null
    Show-MsgBox -Text $msg -Title "一括台帳同期 完了" -Buttons "OK" -Icon "Information" | Out-Null
}
catch {
    Write-PhotoError -Module "SyncExcelFromTxt" -ErrorRecord $_ | Out-Null
    Show-MsgBox -Text "エラーが発生しました。data\logs フォルダを確認してください。`n$($_.Exception.Message)" -Title "エラー" -Buttons "OK" -Icon "Error" | Out-Null
    exit 1
}
