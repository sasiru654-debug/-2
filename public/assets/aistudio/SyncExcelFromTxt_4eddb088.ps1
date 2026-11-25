#Requires -Version 5.1
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
. (Join-Path $CommonDir "PhotoInfoHelper.ps1")
. (Join-Path $CommonDir "SceneHelper.ps1")
. (Join-Path $CommonDir "XHelper.ps1")
. (Join-Path $CommonDir "ExcelHelper.ps1")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

try {
    Write-PhotoLog -Level "INFO" -Module "SyncExcelFromTxt" -Message "一括台帳同期ツールを起動します。"
    $config = Get-PhotoConfig -RootDir $RootDir

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "台帳へ一括同期するルートフォルダ（作業フォルダまたはアーカイブフォルダ）を選択してください"
        $fbd.SelectedPath = $config.DevelopedRoot
        if ($fbd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-PhotoLog -Level "INFO" -Module "SyncExcelFromTxt" -Message "フォルダ選択がキャンセルされました。"
            exit 0
        }
        $TargetPath = $fbd.SelectedPath
    }

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        throw "指定されたパスが存在しません: $TargetPath"
    }

    Write-PhotoLog -Level "INFO" -Module "SyncExcelFromTxt" -Message "スキャン対象: $TargetPath"

    $allDirs = @(Get-ChildItem -LiteralPath $TargetPath -Directory -Recurse -ErrorAction SilentlyContinue)
    $leafDirs = @()
    foreach ($d in $allDirs) {
        if ($d.Name -match '^(System Volume Information|\$RECYCLE\.BIN|logs|data|tests|common|editor|workflow)$') { continue }
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
        $info = Read-PhotoInfoFile -FolderPath $dir.FullName -Config $config
        $records += $info
        if ($info.IsRegistered) {
            Update-SceneHistoryFromInfo -RootDir $RootDir -Info $info
            Update-XHistoryFromInfo -RootDir $RootDir -Info $info
            $learnedCount++
        }
    }

    if ($records.Count -gt 0) {
        Sync-RecordsToExcelLedger -Config $config -Records $records
    }

    $msg = "一括同期が完了しました。`n対象フォルダ数: $($records.Count) 件（うち情報登録済: $learnedCount 件 / 未登録: $($records.Count - $learnedCount) 件）"
    Write-PhotoLog -Level "INFO" -Module "SyncExcelFromTxt" -Message $msg
    [System.Windows.Forms.MessageBox]::Show($msg, "一括台帳同期 完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}
catch {
    Write-PhotoError -Module "SyncExcelFromTxt" -ErrorRecord $_
    [System.Windows.Forms.MessageBox]::Show("エラーが発生しました。logsフォルダを確認してください。`n$($_.Exception.Message)", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}
