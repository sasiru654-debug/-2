#requires -Version 5.1
# ==============================================================================
# PhotoToolsMaster.ps1 - PhotoTools Master 総合管理・整合性チェック・台帳同期
# ==============================================================================
Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = "D:\PhotoTools" }

$configHelperPath = Join-path $scriptDir "common\ConfigHelper.ps1"
$excelHelperPath = Join-Path $scriptDir "common\ExcelHelper.ps1"
$photoInfoHelperPath = Join-Path $scriptDir "common\PhotoInfoHelper.ps1"
$logHelperPath = Join-Path $scriptDir "common\LogHelper.ps1"

if (Test-Path $configHelperPath) { . $configHelperPath }
if (Test-Path $excelHelperPath) { . $excelHelperPath }
if (Test-Path $photoInfoHelperPath) { . $photoInfoHelperPath }
if (Test-Path $logHelperPath) { . $logHelperPath }

function Reload-MasterConfig {
    if (Get-Command Get-PhotoToolsConfig -ErrorAction SilentlyContinue) {
        $script:config = Get-PhotoToolsConfig -RootDir $scriptDir
    } else {
        $script:config = @{
            ImportRoot1 = "G:\写真\eos"
            DevelopedRoot = "G:\写真\現像後"
            DevelopedArchiveRoot = "J:\写真2\現像後"
            ImportArchiveRoot = "J:\写真2\eos"
            ExcelPath = "G:\写真\現像後\写真管理一覧.xlsx"
        }
    }
}
Reload-MasterConfig

$form = New-Object System.Windows.Forms.Form
$form.Text = "PhotoTools Master - 総合管理・整合性チェック・台帳同期"
$form.Size = New-Object System.Drawing.Size(960, 680)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(800, 550)

$fontMain = New-Object System.Drawing.Font("Meiryo UI", 9)
$form.Font = $fontMain

$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = "Top"
$pnlHeader.Height = 65
$pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(20, 45, 60)
$form.Controls.Add($pnlHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "PhotoTools Master 総合管理コンソール"
$lblTitle.Font = New-Object System.Drawing.Font("Meiryo UI", 12, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.Location = New-Object System.Drawing.Point(15, 10)
$lblTitle.AutoSize = $true
$pnlHeader.Controls.Add($lblTitle)

$lblSubTitle = New-Object System.Windows.Forms.Label
$lblSubTitle.Text = "日付フォルダスコープ、不整合診断、およびExcel台帳の自動補完・復元を一元管理"
$lblSubTitle.Font = New-Object System.Drawing.Font("Meiryo UI", 8.5)
$lblSubTitle.ForeColor = [System.Drawing.Color]::FromArgb(180, 210, 225)
$lblSubTitle.Location = New-Object System.Drawing.Point(16, 38)
$lblSubTitle.AutoSize = $true
$pnlHeader.Controls.Add($lblSubTitle)

$btnOpenSettings = New-Object System.Windows.Forms.Button
$btnOpenSettings.Text = "設定編集 (settings.ini 等)"
$btnOpenSettings.Location = New-Object System.Drawing.Point(730, 15)
$btnOpenSettings.Size = New-Object System.Drawing.Size(200, 35)
$btnOpenSettings.Anchor = "Top, Right"
$btnOpenSettings.BackColor = [System.Drawing.Color]::FromArgb(15, 118, 110)
$btnOpenSettings.ForeColor = [System.Drawing.Color]::White
$btnOpenSettings.FlatStyle = "Flat"
$btnOpenSettings.Font = New-Object System.Drawing.Font("Meiryo UI", 9.5, [System.Drawing.FontStyle]::Bold)
$pnlHeader.Controls.Add($btnOpenSettings)

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = "Fill"
$tabControl.Padding = New-Object System.Drawing.Point(12, 6)
$form.Controls.Add($tabControl)

# Tab 1
$tpFolders = New-Object System.Windows.Forms.TabPage
$tpFolders.Text = "フォルダ構造 & ワークフロー呼出"
$tpFolders.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$tabControl.Controls.Add($tpFolders)

$grpViewSelect = New-Object System.Windows.Forms.GroupBox
$grpViewSelect.Text = "表示対象ビューの切替（オンデマンドスキャン）"
$grpViewSelect.Location = New-Object System.Drawing.Point(15, 12)
$grpViewSelect.Size = New-Object System.Drawing.Size(915, 60)
$tpFolders.Controls.Add($grpViewSelect)

$rbtnWork = New-Object System.Windows.Forms.RadioButton
$rbtnWork.Text = "作業用ルート (Developed / Raw)"
$rbtnWork.Location = New-Object System.Drawing.Point(20, 24)
$rbtnWork.AutoSize = $true
$rbtnWork.Checked = $true
$grpViewSelect.Controls.Add($rbtnWork)

$rbtnCompleted = New-Object System.Windows.Forms.RadioButton
$rbtnCompleted.Text = "作業完了後ルート"
$rbtnCompleted.Location = New-Object System.Drawing.Point(240, 24)
$rbtnCompleted.AutoSize = $true
$grpViewSelect.Controls.Add($rbtnCompleted)

$rbtnArchive = New-Object System.Windows.Forms.RadioButton
$rbtnArchive.Text = "長期アーカイブ"
$rbtnArchive.Location = New-Object System.Drawing.Point(400, 24)
$rbtnArchive.AutoSize = $true
$grpViewSelect.Controls.Add($rbtnArchive)

$btnRefreshView = New-Object System.Windows.Forms.Button
$btnRefreshView.Text = "フォルダをチェック・表示"
$btnRefreshView.Location = New-Object System.Drawing.Point(620, 20)
$btnRefreshView.Size = New-Object System.Drawing.Size(160, 28)
$btnRefreshView.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnRefreshView.ForeColor = [System.Drawing.Color]::White
$grpViewSelect.Controls.Add($btnRefreshView)

$lblDateListInfo = New-Object System.Windows.Forms.Label
$lblDateListInfo.Text = "日付フォルダ一覧（リストは日付階層まで。日付を選択してボタンを押すと DailyWorkflow を起動できます）"
$lblDateListInfo.Location = New-Object System.Drawing.Point(15, 85)
$lblDateListInfo.Size = New-Object System.Drawing.Size(915, 20)
$tpFolders.Controls.Add($lblDateListInfo)

$listViewDates = New-Object System.Windows.Forms.ListView
$listViewDates.Location = New-Object System.Drawing.Point(15, 110)
$listViewDates.Size = New-Object System.Drawing.Size(915, 430)
$listViewDates.View = [System.Windows.Forms.View]::Details
$listViewDates.FullRowSelect = $true
$listViewDates.GridLines = $true
$listViewDates.Columns.Add("撮影日付 (YYYY-MM-DD)", 160) | Out-Null
$listViewDates.Columns.Add("状態 / ステータス", 150) | Out-Null
$listViewDates.Columns.Add("フォルダフルパス", 450) | Out-Null
$listViewDates.Columns.Add("写真情報.txt", 120) | Out-Null
$tpFolders.Controls.Add($listViewDates)

$btnLaunchDaily = New-Object System.Windows.Forms.Button
$btnLaunchDaily.Text = "選択した日付で DailyWorkflow を起動"
$btnLaunchDaily.Location = New-Object System.Drawing.Point(600, 550)
$btnLaunchDaily.Size = New-Object System.Drawing.Size(330, 36)
$btnLaunchDaily.BackColor = [System.Drawing.Color]::FromArgb(16, 124, 65)
$btnLaunchDaily.ForeColor = [System.Drawing.Color]::White
$btnLaunchDaily.Font = New-Object System.Drawing.Font("Meiryo UI", 9.5, [System.Drawing.FontStyle]::Bold)
$tpFolders.Controls.Add($btnLaunchDaily)

# Tab 2
$tpCheck = New-Object System.Windows.Forms.TabPage
$tpCheck.Text = "不整合チェック・診断"
$tpCheck.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$tabControl.Controls.Add($tpCheck)

$lblCheckDesc = New-Object System.Windows.Forms.Label
$lblCheckDesc.Text = "日付フォルダが「作業用」「作業完了後」「アーカイブ」に跨って重複存在していないか、または台帳と不整合がないかを診断します。"
$lblCheckDesc.Location = New-Object System.Drawing.Point(20, 20)
$lblCheckDesc.Size = New-Object System.Drawing.Size(900, 25)
$tpCheck.Controls.Add($lblCheckDesc)

$btnRunCheck = New-Object System.Windows.Forms.Button
$btnRunCheck.Text = "不整合チェックを実行"
$btnRunCheck.Location = New-Object System.Drawing.Point(20, 55)
$btnRunCheck.Size = New-Object System.Drawing.Size(180, 32)
$btnRunCheck.BackColor = [System.Drawing.Color]::FromArgb(200, 80, 0)
$btnRunCheck.ForeColor = [System.Drawing.Color]::White
$tpCheck.Controls.Add($btnRunCheck)

$txtCheckLog = New-Object System.Windows.Forms.TextBox
$txtCheckLog.Location = New-Object System.Drawing.Point(20, 100)
$txtCheckLog.Size = New-Object System.Drawing.Size(910, 480)
$txtCheckLog.Multiline = $true
$txtCheckLog.ScrollBars = "Vertical"
$txtCheckLog.ReadOnly = $true
$txtCheckLog.Font = New-Object System.Drawing.Font("Consolas", 9.5)
$txtCheckLog.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$txtCheckLog.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
$tpCheck.Controls.Add($txtCheckLog)

# Tab 3
$tpLedger = New-Object System.Windows.Forms.TabPage
$tpLedger.Text = "台帳自動補完・セルフヒーリング"
$tpLedger.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$tabControl.Controls.Add($tpLedger)

$lblLedgerDesc = New-Object System.Windows.Forms.Label
$lblLedgerDesc.Text = "全ての日付フォルダをスキャンし、Excel台帳に存在しないものは自動追加します。写真情報.txtやscene.txtがない場合は仮登録行を作成し、詳細情報登録時にExcelHelperが自動で仮登録行を削除して正式レコードへ正規化・追記します。"
$lblLedgerDesc.Location = New-Object System.Drawing.Point(20, 20)
$lblLedgerDesc.Size = New-Object System.Drawing.Size(900, 40)
$tpLedger.Controls.Add($lblLedgerDesc)

$btnSyncLedger = New-Object System.Windows.Forms.Button
$btnSyncLedger.Text = "台帳の自動補完・同期を実行"
$btnSyncLedger.Location = New-Object System.Drawing.Point(20, 70)
$btnSyncLedger.Size = New-Object System.Drawing.Size(220, 36)
$btnSyncLedger.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnSyncLedger.ForeColor = [System.Drawing.Color]::White
$btnSyncLedger.Font = New-Object System.Drawing.Font("Meiryo UI", 10, [System.Drawing.FontStyle]::Bold)
$tpLedger.Controls.Add($btnSyncLedger)

$txtLedgerLog = New-Object System.Windows.Forms.TextBox
$txtLedgerLog.Location = New-Object System.Drawing.Point(20, 120)
$txtLedgerLog.Size = New-Object System.Drawing.Size(910, 460)
$txtLedgerLog.Multiline = $true
$txtLedgerLog.ScrollBars = "Vertical"
$txtLedgerLog.ReadOnly = $true
$txtLedgerLog.Font = New-Object System.Drawing.Font("Consolas", 9.5)
$txtLedgerLog.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$txtLedgerLog.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
$tpLedger.Controls.Add($txtLedgerLog)

function Load-DateFoldersForView {
    $listViewDates.Items.Clear()
    $targetRoot = if ($rbtnWork.Checked) {
        $script:config.DevelopedRoot
    } elseif ($rbtnCompleted.Checked) {
        $script:config.DevelopedArchiveRoot
    } else {
        if ($script:config.ContainsKey("ImportArchiveRoot") -and -not [string]::IsNullOrWhiteSpace([string]$script:config.ImportArchiveRoot) -and (Test-Path -LiteralPath ([string]$script:config.ImportArchiveRoot))) {
            [string]$script:config.ImportArchiveRoot
        } else {
            "J:\写真2\archive"
        }
    }

    if (-not (Test-Path $targetRoot)) {
        return
    }

    $subDirs = Get-ChildItem -Path $targetRoot -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $subDirs) {
        if ($dir.Name -match '^\d{4}[_-]\d{2}[_-]\d{2}$') {
            $dateStr = $dir.Name -replace '_','-'
            $status = "正常"
            $hasDirectTxt = Test-Path -LiteralPath (Join-Path $dir.FullName "写真情報.txt")
            $childTxts = @(Get-ChildItem -LiteralPath $dir.FullName -Filter "写真情報.txt" -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -ine $dir.FullName })
            $infoStatus = if ($hasDirectTxt -and $childTxts.Count -gt 0) { "日付直下+子($($childTxts.Count)件)" }
                          elseif ($hasDirectTxt) { "日付直下登録済" }
                          elseif ($childTxts.Count -gt 0) { "子フォルダ($($childTxts.Count)件)" }
                          else { "詳細未登録(仮)" }

            $item = New-Object System.Windows.Forms.ListViewItem($dateStr)
            $item.SubItems.Add($status) | Out-Null
            $item.SubItems.Add($dir.FullName) | Out-Null
            $item.SubItems.Add($infoStatus) | Out-Null
            $item.Tag = $dir.FullName
            $listViewDates.Items.Add($item) | Out-Null
        }
    }
}

$btnRefreshView.Add_Click({ Load-DateFoldersForView })
$rbtnWork.Add_CheckedChanged({ if ($rbtnWork.Checked) { Load-DateFoldersForView } })
$rbtnCompleted.Add_CheckedChanged({ if ($rbtnCompleted.Checked) { Load-DateFoldersForView } })
$rbtnArchive.Add_CheckedChanged({ if ($rbtnArchive.Checked) { Load-DateFoldersForView } })

$btnLaunchDaily.Add_Click({
    if ($listViewDates.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("一覧から日付フォルダを選択してください。", "警告", 'OK', 'Warning')
        return
    }
    $selectedPath = $listViewDates.SelectedItems[0].Tag
    $dailyWorkflowScript = Join-Path $scriptDir "workflow\DailyWorkflow.ps1"
    if (Test-Path $dailyWorkflowScript) {
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$dailyWorkflowScript`" -TargetPath `"$selectedPath`""
    }
})

$btnOpenSettings.Add_Click({
    $settingsEditorScript = Join-Path $scriptDir "editor\SettingsEditor.ps1"
    if (-not (Test-Path -LiteralPath $settingsEditorScript)) {
        [System.Windows.Forms.MessageBox]::Show($form, "設定編集スクリプトが見つかりません:`n$settingsEditorScript", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }
    try {
        . $settingsEditorScript
        $saved = Show-PhotoToolsSettingsDialog -RootDir $scriptDir -OwnerForm $form
        if ($saved -eq $true) {
            Reload-MasterConfig
            Load-DateFoldersForView
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, "設定編集画面の起動に失敗しました:`n$($_.Exception.Message)", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$btnRunCheck.Add_Click({
    $txtCheckLog.Clear()
    $txtCheckLog.AppendText("[診断開始] フォルダ間の重複・不整合チェックを実行中...`r`n")
    $rootsToScan = @(
        @{ Label = "作業用(現像後)"; Path = [string]$script:config.DevelopedRoot },
        @{ Label = "作業用(取込元)"; Path = [string]$script:config.ImportRoot1 },
        @{ Label = "完了後アーカイブ"; Path = [string]$script:config.DevelopedArchiveRoot },
        @{ Label = "取込アーカイブ"; Path = [string]$script:config.ImportArchiveRoot }
    )
    $seenByDate = @{}
    foreach ($rt in $rootsToScan) {
        if ([string]::IsNullOrWhiteSpace($rt.Path) -or -not (Test-Path -LiteralPath $rt.Path)) { continue }
        $dirs = @(Get-ChildItem -LiteralPath $rt.Path -Directory -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{4}[_-]\d{2}[_-]\d{2}$' })
        $txtCheckLog.AppendText("  スキャン: $($rt.Label) ($($rt.Path)) -> $($dirs.Count) 件の日付フォルダ`r`n")
        foreach ($d in $dirs) {
            $dKey = ($d.Name -replace '_','-')
            if (-not $seenByDate.ContainsKey($dKey)) {
                $seenByDate[$dKey] = New-Object System.Collections.Generic.List[string]
            }
            [void]$seenByDate[$dKey].Add("$($rt.Label): $($d.FullName)")
        }
    }
    $dupCount = 0
    foreach ($kv in $seenByDate.GetEnumerator()) {
        $locs = @($kv.Value)
        $hasWork = @($locs | Where-Object { $_ -like "作業用*" }).Count -gt 0
        $hasArch = @($locs | Where-Object { $_ -like "*アーカイブ*" }).Count -gt 0
        if ($hasWork -and $hasArch) {
            $dupCount++
            $txtCheckLog.AppendText("[警告: 重複残存] $($kv.Key) が作業用とアーカイブの両方に存在します:`r`n")
            foreach ($lc in $locs) { $txtCheckLog.AppendText("    - $lc`r`n") }
        }
    }
    if ($dupCount -eq 0) {
        $txtCheckLog.AppendText("[診断完了] 作業用とアーカイブ間の重複不整合は検出されませんでした。`r`n")
    } else {
        $txtCheckLog.AppendText("[診断完了] $dupCount 件の重複日付フォルダを検出しました。`r`n")
    }
})

$btnSyncLedger.Add_Click({
    $txtLedgerLog.Clear()
    $txtLedgerLog.AppendText("[台帳同期開始] 全日付フォルダのスキャンとExcel台帳の自動補完・仮登録行正規化を実行中...`r`n")
    try {
        $scanRoots = @([string]$script:config.DevelopedRoot, [string]$script:config.DevelopedArchiveRoot) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) }
        $records = @()
        foreach ($sr in $scanRoots) {
            $txtLedgerLog.AppendText("  スキャン中: $sr`r`n")
            $allDirs = @(Get-ChildItem -LiteralPath $sr -Directory -Recurse -ErrorAction SilentlyContinue)
            foreach ($d in $allDirs) {
                if ($d.Name -match '^(System Volume Information|\$RECYCLE\.BIN|logs|data|tests|common|editor|workflow|gigafile)$') { continue }
                $subDirs = @(Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue)
                $hasTxt = Test-Path -LiteralPath (Join-Path $d.FullName "写真情報.txt")
                $hasFiles = @(Get-ChildItem -LiteralPath $d.FullName -File -ErrorAction SilentlyContinue).Count -gt 0
                if ($hasTxt -or ($subDirs.Count -eq 0 -and $hasFiles)) {
                    $info = Read-PhotoInfoTxt -FolderPath $d.FullName -Config $script:config
                    $records += $info
                }
            }
        }
        if ($records.Count -gt 0) {
            Sync-RecordsToExcelLedger -Config $script:config -Records $records
            $txtLedgerLog.AppendText("[台帳同期完了] $($records.Count) 件のフォルダ情報をExcel台帳 ($($script:config.ExcelPath)) へ同期・補完しました。`r`n")
        } else {
            $txtLedgerLog.AppendText("[台帳同期完了] 同期対象のフォルダが見つかりませんでした。`r`n")
        }
    } catch {
        $txtLedgerLog.AppendText("[エラー] $($_.Exception.Message)`r`n")
    }
})

Load-DateFoldersForView
[void]$form.ShowDialog()
