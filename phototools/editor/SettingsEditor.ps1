#requires -Version 5.1
# ==============================================================================
# SettingsEditor.ps1 - settings.ini・関連設定/履歴ファイル編集GUI (UTF-8 BOM / CRLF)
# ==============================================================================
param(
    [string]$RootDir = ""
)

Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-PhotoToolsSettingsDialog {
    param(
        [string]$RootDir = "",
        [System.Windows.Forms.IWin32Window]$OwnerForm = $null
    )

    if ([string]::IsNullOrWhiteSpace($RootDir)) {
        $scriptFolder = $PSScriptRoot
        if ([string]::IsNullOrWhiteSpace($scriptFolder)) { $scriptFolder = "D:\PhotoTools\editor" }
        $RootDir = Split-Path -Parent $scriptFolder
        if (-not (Test-Path -LiteralPath (Join-Path $RootDir "settings.ini"))) {
            if (Test-Path -LiteralPath "D:\PhotoTools\settings.ini") { $RootDir = "D:\PhotoTools" }
        }
    }

    $commonDir = Join-Path $RootDir "common"
    $cfgHelper = Join-Path $commonDir "ConfigHelper.ps1"
    $logHelper = Join-Path $commonDir "LogHelper.ps1"
    if (Test-Path -LiteralPath $cfgHelper) { . $cfgHelper }
    if (Test-Path -LiteralPath $logHelper) { . $logHelper }

    $iniPath = Join-Path $RootDir "settings.ini"
    $cfg = Get-PhotoToolsConfig -IniPath $iniPath -RootDir $RootDir

    # 生のsettings.ini値も取得（空欄保持が必要な MegaCmdPath / MegaSyncRootPath 等のため）
    $rawIniMap = @{}
    if (Test-Path -LiteralPath $iniPath) {
        $curSec = ""
        foreach ($ln in [System.IO.File]::ReadAllLines($iniPath, [System.Text.Encoding]::UTF8)) {
            $t = $ln.Trim()
            if ($t -eq "" -or $t.StartsWith(";") -or $t.StartsWith("#")) { continue }
            if ($t -match '^\[(.+)\]$') { $curSec = $Matches[1].Trim(); continue }
            if ($t -match '^([^=]+)=(.*)$') {
                $rawIniMap[$Matches[1].Trim()] = $Matches[2].Trim()
            }
        }
    }

    $getInitialVal = {
        param([string]$Key, [string]$Fallback = "")
        if ($rawIniMap.ContainsKey($Key)) { return [string]$rawIniMap[$Key] }
        if ($cfg.ContainsKey($Key) -and $null -ne $cfg[$Key]) { return [string]$cfg[$Key] }
        return $Fallback
    }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "PhotoTools 設定編集 (settings.ini / 関連設定ファイル)"
    $dlg.Size = New-Object System.Drawing.Size(860, 670)
    $dlg.MinimumSize = New-Object System.Drawing.Size(780, 580)
    $dlg.StartPosition = if ($null -ne $OwnerForm) { "CenterParent" } else { "CenterScreen" }
    $dlg.Font = New-Object System.Drawing.Font("Meiryo UI", 9)
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

    $script:SettingsDirty = $false
    $script:SettingsSaved = $false
    $script:IsPopulatingUI = $true

    # ヘッダー
    $pnlTop = New-Object System.Windows.Forms.Panel
    $pnlTop.Dock = "Top"
    $pnlTop.Height = 56
    $pnlTop.BackColor = [System.Drawing.Color]::FromArgb(20, 45, 60)
    $dlg.Controls.Add($pnlTop)

    $lblHead = New-Object System.Windows.Forms.Label
    $lblHead.Text = "PhotoTools 環境設定エディタ"
    $lblHead.Font = New-Object System.Drawing.Font("Meiryo UI", 11.5, [System.Drawing.FontStyle]::Bold)
    $lblHead.ForeColor = [System.Drawing.Color]::White
    $lblHead.Location = New-Object System.Drawing.Point(16, 8)
    $lblHead.AutoSize = $true
    $pnlTop.Controls.Add($lblHead)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "対象ファイル: $iniPath  （保存時に自動で settings.ini.bak バックアップを作成します）"
    $lblSub.Font = New-Object System.Drawing.Font("Meiryo UI", 8.5)
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(185, 215, 230)
    $lblSub.Location = New-Object System.Drawing.Point(17, 33)
    $lblSub.AutoSize = $true
    $pnlTop.Controls.Add($lblSub)

    # 下部アクションバー
    $pnlBottom = New-Object System.Windows.Forms.Panel
    $pnlBottom.Dock = "Bottom"
    $pnlBottom.Height = 56
    $pnlBottom.BackColor = [System.Drawing.Color]::FromArgb(236, 240, 245)
    $dlg.Controls.Add($pnlBottom)

    $btnCheckPaths = New-Object System.Windows.Forms.Button
    $btnCheckPaths.Text = "パス存在チェック"
    $btnCheckPaths.Location = New-Object System.Drawing.Point(16, 12)
    $btnCheckPaths.Size = New-Object System.Drawing.Size(135, 32)
    $btnCheckPaths.BackColor = [System.Drawing.Color]::White
    $pnlBottom.Controls.Add($btnCheckPaths)

    $btnResetDefault = New-Object System.Windows.Forms.Button
    $btnResetDefault.Text = "標準値に戻す"
    $btnResetDefault.Location = New-Object System.Drawing.Point(160, 12)
    $btnResetDefault.Size = New-Object System.Drawing.Size(115, 32)
    $btnResetDefault.BackColor = [System.Drawing.Color]::White
    $pnlBottom.Controls.Add($btnResetDefault)

    $btnOpenIniFolder = New-Object System.Windows.Forms.Button
    $btnOpenIniFolder.Text = "設定フォルダを開く"
    $btnOpenIniFolder.Location = New-Object System.Drawing.Point(284, 12)
    $btnOpenIniFolder.Size = New-Object System.Drawing.Size(135, 32)
    $btnOpenIniFolder.BackColor = [System.Drawing.Color]::White
    $pnlBottom.Controls.Add($btnOpenIniFolder)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "settings.ini を保存して反映"
    $btnSave.Location = New-Object System.Drawing.Point(540, 11)
    $btnSave.Size = New-Object System.Drawing.Size(195, 34)
    $btnSave.Anchor = "Top, Right"
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(16, 124, 65)
    $btnSave.ForeColor = [System.Drawing.Color]::White
    $btnSave.FlatStyle = "Flat"
    $btnSave.Font = New-Object System.Drawing.Font("Meiryo UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $pnlBottom.Controls.Add($btnSave)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "閉じる"
    $btnClose.Location = New-Object System.Drawing.Point(744, 11)
    $btnClose.Size = New-Object System.Drawing.Size(88, 34)
    $btnClose.Anchor = "Top, Right"
    $btnClose.BackColor = [System.Drawing.Color]::White
    $pnlBottom.Controls.Add($btnClose)

    # メインタブ
    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = "Fill"
    $tabs.Padding = New-Object System.Drawing.Point(12, 6)
    $dlg.Controls.Add($tabs)
    $tabs.BringToFront()

    # --------------------------------------------------------------------------
    # タブ1: フォルダ・パス設定 ([Paths])
    # --------------------------------------------------------------------------
    $tpPaths = New-Object System.Windows.Forms.TabPage
    $tpPaths.Text = "フォルダ・パス設定"
    $tpPaths.BackColor = [System.Drawing.Color]::White
    $tabs.Controls.Add($tpPaths)

    $pnlPathScroll = New-Object System.Windows.Forms.Panel
    $pnlPathScroll.Dock = "Fill"
    $pnlPathScroll.AutoScroll = $true
    $pnlPathScroll.Padding = New-Object System.Windows.Forms.Padding(12)
    $tpPaths.Controls.Add($pnlPathScroll)

    $pathFieldDefs = @(
        @{ Key = "ImportRoot1";          Label = "取込元ルート 1 (ImportRoot1)";          Kind = "Dir";  Default = "G:\写真\eos" },
        @{ Key = "ImportRoot2";          Label = "取込元ルート 2 (ImportRoot2)";          Kind = "Dir";  Default = "H:\写真作業用\eos" },
        @{ Key = "RawSaveRoot";          Label = "作業用RAWルート 1 (RawSaveRoot)";       Kind = "Dir";  Default = "G:\写真raw" },
        @{ Key = "RawSaveRoot2";         Label = "作業用RAWルート 2 (RawSaveRoot2)";      Kind = "Dir";  Default = "H:\写真作業用\作業用RAW" },
        @{ Key = "DevelopedRoot";        Label = "現像後ルート (DevelopedRoot)";          Kind = "Dir";  Default = "G:\写真\現像後" },
        @{ Key = "RawArchiveRoot";       Label = "RAWアーカイブ先 (RawArchiveRoot)";      Kind = "Dir";  Default = "L:\" },
        @{ Key = "DevelopedArchiveRoot"; Label = "現像後アーカイブ先 (DevelopedArchive)"; Kind = "Dir";  Default = "J:\写真2\現像後" },
        @{ Key = "ImportArchiveRoot";    Label = "取込アーカイブ先 (ImportArchiveRoot)";  Kind = "Dir";  Default = "J:\写真2\eos" },
        @{ Key = "DataDir";              Label = "データ保存フォルダ (DataDir)";          Kind = "Dir";  Default = (Join-Path $RootDir "data") },
        @{ Key = "LedgerFileName";       Label = "Excel台帳ファイル名 (LedgerFileName)";  Kind = "Text"; Default = "写真管理一覧.xlsx" },
        @{ Key = "ExcelPath";            Label = "Excel管理台帳パス (ExcelPath)";         Kind = "File"; Filter = "Excel (*.xlsx)|*.xlsx|すべてのファイル (*.*)|*.*"; Default = "G:\写真\現像後\写真管理一覧.xlsx" },
        @{ Key = "XHistoryPath";         Label = "Xアカウント履歴JSON (XHistoryPath)";    Kind = "File"; Filter = "JSON (*.json)|*.json|すべてのファイル (*.*)|*.*"; Default = (Join-Path $RootDir "data\x_history.json") },
        @{ Key = "SceneHistoryPath";     Label = "シーン履歴JSON (SceneHistoryPath)";     Kind = "File"; Filter = "JSON (*.json)|*.json|すべてのファイル (*.*)|*.*"; Default = (Join-Path $RootDir "data\scene_history.json") },
        @{ Key = "GigaFileScriptPath";   Label = "ギガファイル便スクリプト";              Kind = "File"; Filter = "PowerShell (*.ps1)|*.ps1|すべてのファイル (*.*)|*.*"; Default = (Join-Path $RootDir "gigafile\send_to_gigafile.ps1") },
        @{ Key = "MegaSyncRootPath";     Label = "MEGA同期ルート (任意・空欄可)";         Kind = "Dir";  Default = "" }
    )

    $pathTextBoxes = @{}
    $y = 14
    foreach ($def in $pathFieldDefs) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $def.Label
        $lbl.Location = New-Object System.Drawing.Point(14, ($y + 4))
        $lbl.Size = New-Object System.Drawing.Size(255, 22)
        $pnlPathScroll.Controls.Add($lbl)

        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location = New-Object System.Drawing.Point(274, $y)
        $tb.Size = New-Object System.Drawing.Size(435, 24)
        $tb.Text = & $getInitialVal $def.Key $def.Default
        $tb.Add_TextChanged({ if (-not $script:IsPopulatingUI) { $script:SettingsDirty = $true } })
        $pnlPathScroll.Controls.Add($tb)
        $pathTextBoxes[$def.Key] = $tb

        if ($def.Kind -eq "Dir" -or $def.Kind -eq "File") {
            $btnBr = New-Object System.Windows.Forms.Button
            $btnBr.Text = "参照..."
            $btnBr.Location = New-Object System.Drawing.Point(716, ($y - 1))
            $btnBr.Size = New-Object System.Drawing.Size(74, 26)
            $btnBr.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
            $btnBr.Tag = @{ Box = $tb; Kind = $def.Kind; Filter = $(if ($def.ContainsKey("Filter")) { $def.Filter } else { "すべてのファイル (*.*)|*.*" }); Title = $def.Label }
            $btnBr.Add_Click({
                param($s, $e)
                $t = $s.Tag
                $box = $t.Box
                if ($t.Kind -eq "Dir") {
                    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
                    $fbd.Description = "$($t.Title) を選択してください"
                    if (-not [string]::IsNullOrWhiteSpace($box.Text) -and (Test-Path -LiteralPath $box.Text)) {
                        $fbd.SelectedPath = $box.Text
                    }
                    if ($fbd.ShowDialog($dlg) -eq [System.Windows.Forms.DialogResult]::OK) {
                        $box.Text = $fbd.SelectedPath
                    }
                    $fbd.Dispose()
                } else {
                    $ofd = New-Object System.Windows.Forms.OpenFileDialog
                    $ofd.Title = "$($t.Title) を選択してください"
                    $ofd.Filter = $t.Filter
                    $ofd.CheckFileExists = $false
                    if (-not [string]::IsNullOrWhiteSpace($box.Text)) {
                        $pDir = Split-Path -Parent $box.Text
                        if (-not [string]::IsNullOrWhiteSpace($pDir) -and (Test-Path -LiteralPath $pDir)) {
                            $ofd.InitialDirectory = $pDir
                        }
                        $ofd.FileName = Split-Path -Leaf $box.Text
                    }
                    if ($ofd.ShowDialog($dlg) -eq [System.Windows.Forms.DialogResult]::OK) {
                        $box.Text = $ofd.FileName
                    }
                    $ofd.Dispose()
                }
            })
            $pnlPathScroll.Controls.Add($btnBr)
        }
        $y += 33
    }

    # --------------------------------------------------------------------------
    # タブ2: 期分け・拡張子・MEGA設定
    # --------------------------------------------------------------------------
    $tpRules = New-Object System.Windows.Forms.TabPage
    $tpRules.Text = "期分け・拡張子・MEGA"
    $tpRules.BackColor = [System.Drawing.Color]::White
    $tabs.Controls.Add($tpRules)

    # [ArchivePeriod]
    $grpPeriod = New-Object System.Windows.Forms.GroupBox
    $grpPeriod.Text = "アーカイブ期分け月設定 ([ArchivePeriod])  ※カンマ区切りで 1〜12 の月を指定"
    $grpPeriod.Location = New-Object System.Drawing.Point(16, 16)
    $grpPeriod.Size = New-Object System.Drawing.Size(790, 125)
    $tpRules.Controls.Add($grpPeriod)

    $qBoxes = @{}
    $qDefs = @(
        @{ Key = "Q1_Months"; Label = "1期 (Q1_Months):"; X = 20;  Y = 34; Default = "1,2,3" },
        @{ Key = "Q2_Months"; Label = "2期 (Q2_Months):"; X = 405; Y = 34; Default = "4,5,6" },
        @{ Key = "Q3_Months"; Label = "3期 (Q3_Months):"; X = 20;  Y = 74; Default = "7,8,9" },
        @{ Key = "Q4_Months"; Label = "4期 (Q4_Months):"; X = 405; Y = 74; Default = "10,11,12" }
    )
    foreach ($qd in $qDefs) {
        $ql = New-Object System.Windows.Forms.Label
        $ql.Text = $qd.Label
        $ql.Location = New-Object System.Drawing.Point($qd.X, ($qd.Y + 4))
        $ql.Size = New-Object System.Drawing.Size(130, 22)
        $grpPeriod.Controls.Add($ql)

        $qtb = New-Object System.Windows.Forms.TextBox
        $qtb.Location = New-Object System.Drawing.Point(($qd.X + 135), $qd.Y)
        $qtb.Size = New-Object System.Drawing.Size(210, 24)
        $curArr = if ($cfg.ArchivePeriod.ContainsKey($qd.Key)) { @($cfg.ArchivePeriod[$qd.Key]) -join "," } else { $qd.Default }
        $qtb.Text = if ($rawIniMap.ContainsKey($qd.Key)) { $rawIniMap[$qd.Key] } else { $curArr }
        $qtb.Add_TextChanged({ if (-not $script:IsPopulatingUI) { $script:SettingsDirty = $true } })
        $grpPeriod.Controls.Add($qtb)
        $qBoxes[$qd.Key] = $qtb
    }

    # [Extensions]
    $grpExt = New-Object System.Windows.Forms.GroupBox
    $grpExt.Text = "対象ファイル拡張子 ([Extensions])  ※カンマ区切り（例: .ARW,.CR3）"
    $grpExt.Location = New-Object System.Drawing.Point(16, 156)
    $grpExt.Size = New-Object System.Drawing.Size(790, 112)
    $tpRules.Controls.Add($grpExt)

    $lblRawExt = New-Object System.Windows.Forms.Label
    $lblRawExt.Text = "RAW拡張子 (RawExtensions):"
    $lblRawExt.Location = New-Object System.Drawing.Point(20, 34)
    $lblRawExt.Size = New-Object System.Drawing.Size(215, 22)
    $grpExt.Controls.Add($lblRawExt)

    $txtRawExt = New-Object System.Windows.Forms.TextBox
    $txtRawExt.Location = New-Object System.Drawing.Point(240, 30)
    $txtRawExt.Size = New-Object System.Drawing.Size(525, 24)
    $txtRawExt.Text = if ($rawIniMap.ContainsKey("RawExtensions")) { $rawIniMap["RawExtensions"] } else { (@($cfg.Extensions.RawExtensions) -join ",") }
    $txtRawExt.Add_TextChanged({ if (-not $script:IsPopulatingUI) { $script:SettingsDirty = $true } })
    $grpExt.Controls.Add($txtRawExt)

    $lblImgExt = New-Object System.Windows.Forms.Label
    $lblImgExt.Text = "画像拡張子 (ImageExtensions):"
    $lblImgExt.Location = New-Object System.Drawing.Point(20, 72)
    $lblImgExt.Size = New-Object System.Drawing.Size(215, 22)
    $grpExt.Controls.Add($lblImgExt)

    $txtImgExt = New-Object System.Windows.Forms.TextBox
    $txtImgExt.Location = New-Object System.Drawing.Point(240, 68)
    $txtImgExt.Size = New-Object System.Drawing.Size(525, 24)
    $txtImgExt.Text = if ($rawIniMap.ContainsKey("ImageExtensions")) { $rawIniMap["ImageExtensions"] } else { (@($cfg.Extensions.ImageExtensions) -join ",") }
    $txtImgExt.Add_TextChanged({ if (-not $script:IsPopulatingUI) { $script:SettingsDirty = $true } })
    $grpExt.Controls.Add($txtImgExt)

    # [Mega]
    $grpMega = New-Object System.Windows.Forms.GroupBox
    $grpMega.Text = "MEGA 連携設定 ([Mega])"
    $grpMega.Location = New-Object System.Drawing.Point(16, 284)
    $grpMega.Size = New-Object System.Drawing.Size(790, 152)
    $tpRules.Controls.Add($grpMega)

    $lblMegaCmd = New-Object System.Windows.Forms.Label
    $lblMegaCmd.Text = "MEGAcmd パス (空欄で自動検出):"
    $lblMegaCmd.Location = New-Object System.Drawing.Point(20, 34)
    $lblMegaCmd.Size = New-Object System.Drawing.Size(215, 22)
    $grpMega.Controls.Add($lblMegaCmd)

    $txtMegaCmd = New-Object System.Windows.Forms.TextBox
    $txtMegaCmd.Location = New-Object System.Drawing.Point(240, 30)
    $txtMegaCmd.Size = New-Object System.Drawing.Size(442, 24)
    $txtMegaCmd.Text = if ($rawIniMap.ContainsKey("MegaCmdPath")) { $rawIniMap["MegaCmdPath"] } else { "" }
    $txtMegaCmd.Add_TextChanged({ if (-not $script:IsPopulatingUI) { $script:SettingsDirty = $true } })
    $grpMega.Controls.Add($txtMegaCmd)

    $btnBrMegaCmd = New-Object System.Windows.Forms.Button
    $btnBrMegaCmd.Text = "参照..."
    $btnBrMegaCmd.Location = New-Object System.Drawing.Point(690, 29)
    $btnBrMegaCmd.Size = New-Object System.Drawing.Size(75, 26)
    $btnBrMegaCmd.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Title = "mega-export.bat または MEGAcmd 実行ファイルを選択"
        $ofd.Filter = "バッチ/実行ファイル (*.bat;*.exe)|*.bat;*.exe|すべてのファイル (*.*)|*.*"
        if ($ofd.ShowDialog($dlg) -eq [System.Windows.Forms.DialogResult]::OK) { $txtMegaCmd.Text = $ofd.FileName }
        $ofd.Dispose()
    })
    $grpMega.Controls.Add($btnBrMegaCmd)

    $lblMegaRem = New-Object System.Windows.Forms.Label
    $lblMegaRem.Text = "MEGAリモートルート (MegaRemoteRoot):"
    $lblMegaRem.Location = New-Object System.Drawing.Point(20, 72)
    $lblMegaRem.Size = New-Object System.Drawing.Size(215, 22)
    $grpMega.Controls.Add($lblMegaRem)

    $txtMegaRem = New-Object System.Windows.Forms.TextBox
    $txtMegaRem.Location = New-Object System.Drawing.Point(240, 68)
    $txtMegaRem.Size = New-Object System.Drawing.Size(525, 24)
    $txtMegaRem.Text = & $getInitialVal "MegaRemoteRoot" "/写真1/現像後"
    $txtMegaRem.Add_TextChanged({ if (-not $script:IsPopulatingUI) { $script:SettingsDirty = $true } })
    $grpMega.Controls.Add($txtMegaRem)

    $lblMegaLog = New-Object System.Windows.Forms.Label
    $lblMegaLog.Text = "MEGAログ出力先 (MegaLogPath):"
    $lblMegaLog.Location = New-Object System.Drawing.Point(20, 110)
    $lblMegaLog.Size = New-Object System.Drawing.Size(215, 22)
    $grpMega.Controls.Add($lblMegaLog)

    $txtMegaLog = New-Object System.Windows.Forms.TextBox
    $txtMegaLog.Location = New-Object System.Drawing.Point(240, 106)
    $txtMegaLog.Size = New-Object System.Drawing.Size(442, 24)
    $txtMegaLog.Text = & $getInitialVal "MegaLogPath" (Join-Path $RootDir "data\logs\mega_debug.log")
    $txtMegaLog.Add_TextChanged({ if (-not $script:IsPopulatingUI) { $script:SettingsDirty = $true } })
    $grpMega.Controls.Add($txtMegaLog)

    $btnBrMegaLog = New-Object System.Windows.Forms.Button
    $btnBrMegaLog.Text = "参照..."
    $btnBrMegaLog.Location = New-Object System.Drawing.Point(690, 105)
    $btnBrMegaLog.Size = New-Object System.Drawing.Size(75, 26)
    $btnBrMegaLog.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Title = "MEGAデバッグログの保存先を指定"
        $sfd.Filter = "ログファイル (*.log;*.txt)|*.log;*.txt|すべてのファイル (*.*)|*.*"
        $sfd.FileName = "mega_debug.log"
        if ($sfd.ShowDialog($dlg) -eq [System.Windows.Forms.DialogResult]::OK) { $txtMegaLog.Text = $sfd.FileName }
        $sfd.Dispose()
    })
    $grpMega.Controls.Add($btnBrMegaLog)

    # --------------------------------------------------------------------------
    # タブ3: 関連設定・履歴JSONファイル編集 & OS連携登録
    # --------------------------------------------------------------------------
    $tpFiles = New-Object System.Windows.Forms.TabPage
    $tpFiles.Text = "関連ファイル編集・OS登録"
    $tpFiles.BackColor = [System.Drawing.Color]::White
    $tabs.Controls.Add($tpFiles)

    $lblFileTarget = New-Object System.Windows.Forms.Label
    $lblFileTarget.Text = "編集対象ファイル:"
    $lblFileTarget.Location = New-Object System.Drawing.Point(16, 18)
    $lblFileTarget.Size = New-Object System.Drawing.Size(115, 22)
    $tpFiles.Controls.Add($lblFileTarget)

    $cmbRawFile = New-Object System.Windows.Forms.ComboBox
    $cmbRawFile.Location = New-Object System.Drawing.Point(135, 14)
    $cmbRawFile.Size = New-Object System.Drawing.Size(345, 24)
    $cmbRawFile.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$cmbRawFile.Items.Add("settings.ini (全体設定テキスト)")
    [void]$cmbRawFile.Items.Add("scene_history.json (シーン・衣装履歴)")
    [void]$cmbRawFile.Items.Add("x_history.json (Xアカウント履歴)")
    $cmbRawFile.SelectedIndex = 0
    $tpFiles.Controls.Add($cmbRawFile)

    $btnRawReload = New-Object System.Windows.Forms.Button
    $btnRawReload.Text = "再読込"
    $btnRawReload.Location = New-Object System.Drawing.Point(490, 13)
    $btnRawReload.Size = New-Object System.Drawing.Size(80, 26)
    $tpFiles.Controls.Add($btnRawReload)

    $btnRawValidate = New-Object System.Windows.Forms.Button
    $btnRawValidate.Text = "形式チェック"
    $btnRawValidate.Location = New-Object System.Drawing.Point(578, 13)
    $btnRawValidate.Size = New-Object System.Drawing.Size(100, 26)
    $tpFiles.Controls.Add($btnRawValidate)

    $btnRawSave = New-Object System.Windows.Forms.Button
    $btnRawSave.Text = "このファイルを保存"
    $btnRawSave.Location = New-Object System.Drawing.Point(686, 13)
    $btnRawSave.Size = New-Object System.Drawing.Size(128, 26)
    $btnRawSave.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnRawSave.ForeColor = [System.Drawing.Color]::White
    $btnRawSave.FlatStyle = "Flat"
    $tpFiles.Controls.Add($btnRawSave)

    $lblRawFilePath = New-Object System.Windows.Forms.Label
    $lblRawFilePath.Location = New-Object System.Drawing.Point(16, 46)
    $lblRawFilePath.Size = New-Object System.Drawing.Size(798, 18)
    $lblRawFilePath.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $lblRawFilePath.Font = New-Object System.Drawing.Font("Consolas", 8.5)
    $tpFiles.Controls.Add($lblRawFilePath)

    $txtRawEditor = New-Object System.Windows.Forms.TextBox
    $txtRawEditor.Location = New-Object System.Drawing.Point(16, 68)
    $txtRawEditor.Size = New-Object System.Drawing.Size(798, 340)
    $txtRawEditor.Multiline = $true
    $txtRawEditor.ScrollBars = "Both"
    $txtRawEditor.WordWrap = $false
    $txtRawEditor.Font = New-Object System.Drawing.Font("Consolas", 9.5)
    $txtRawEditor.Anchor = "Top, Bottom, Left, Right"
    $tpFiles.Controls.Add($txtRawEditor)

    $grpOsTools = New-Object System.Windows.Forms.GroupBox
    $grpOsTools.Text = "Windows 連携登録・メンテナンス実行"
    $grpOsTools.Location = New-Object System.Drawing.Point(16, 418)
    $grpOsTools.Size = New-Object System.Drawing.Size(798, 66)
    $grpOsTools.Anchor = "Bottom, Left, Right"
    $tpFiles.Controls.Add($grpOsTools)

    $btnRegCtx = New-Object System.Windows.Forms.Button
    $btnRegCtx.Text = "右クリックメニュー登録"
    $btnRegCtx.Location = New-Object System.Drawing.Point(14, 24)
    $btnRegCtx.Size = New-Object System.Drawing.Size(180, 30)
    $grpOsTools.Controls.Add($btnRegCtx)

    $btnRegProto = New-Object System.Windows.Forms.Button
    $btnRegProto.Text = "URLプロトコル登録"
    $btnRegProto.Location = New-Object System.Drawing.Point(204, 24)
    $btnRegProto.Size = New-Object System.Drawing.Size(170, 30)
    $grpOsTools.Controls.Add($btnRegProto)

    $btnRegGiga = New-Object System.Windows.Forms.Button
    $btnRegGiga.Text = "ギガファイル便 SendTo登録"
    $btnRegGiga.Location = New-Object System.Drawing.Point(384, 24)
    $btnRegGiga.Size = New-Object System.Drawing.Size(195, 30)
    $grpOsTools.Controls.Add($btnRegGiga)

    $btnRunTests = New-Object System.Windows.Forms.Button
    $btnRunTests.Text = "モジュールテスト実行"
    $btnRunTests.Location = New-Object System.Drawing.Point(589, 24)
    $btnRunTests.Size = New-Object System.Drawing.Size(195, 30)
    $grpOsTools.Controls.Add($btnRunTests)

    # --------------------------------------------------------------------------
    # ヘルパーアクション
    # --------------------------------------------------------------------------
    $resolveSelectedRawFilePath = {
        switch ($cmbRawFile.SelectedIndex) {
            0 { return $iniPath }
            1 {
                $p = $pathTextBoxes["SceneHistoryPath"].Text.Trim()
                if ([string]::IsNullOrWhiteSpace($p)) { return (Join-Path $RootDir "data\scene_history.json") }
                return $p
            }
            2 {
                $p = $pathTextBoxes["XHistoryPath"].Text.Trim()
                if ([string]::IsNullOrWhiteSpace($p)) { return (Join-Path $RootDir "data\x_history.json") }
                return $p
            }
            default { return $iniPath }
        }
    }

    $loadSelectedRawFile = {
        $targetPath = & $resolveSelectedRawFilePath
        $lblRawFilePath.Text = "パス: $targetPath"
        if (Test-Path -LiteralPath $targetPath) {
            try {
                $txtRawEditor.Text = [System.IO.File]::ReadAllText($targetPath, [System.Text.Encoding]::UTF8)
            } catch {
                $txtRawEditor.Text = "# 読み込みエラー: $($_.Exception.Message)"
            }
        } else {
            if ($targetPath.ToLower().EndsWith(".json")) {
                $txtRawEditor.Text = "[]"
            } else {
                $txtRawEditor.Text = ""
            }
        }
    }

    $cmbRawFile.Add_SelectedIndexChanged($loadSelectedRawFile)
    $btnRawReload.Add_Click($loadSelectedRawFile)

    $btnRawValidate.Add_Click({
        $targetPath = & $resolveSelectedRawFilePath
        if ($targetPath.ToLower().EndsWith(".json")) {
            try {
                $null = $txtRawEditor.Text | ConvertFrom-Json
                [System.Windows.Forms.MessageBox]::Show($dlg, "JSON 形式は正常です。", "形式チェック", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            } catch {
                [System.Windows.Forms.MessageBox]::Show($dlg, "JSON 構文エラーがあります:`n$($_.Exception.Message)", "形式エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
        } else {
            $hasPaths = $txtRawEditor.Text -match '\[Paths\]'
            $msg = if ($hasPaths) { "INI 形式の基本セクション ([Paths]) が確認できました。" } else { "[Paths] セクションが見つかりません。内容を確認してください。" }
            $ic = if ($hasPaths) { [System.Windows.Forms.MessageBoxIcon]::Information } else { [System.Windows.Forms.MessageBoxIcon]::Warning }
            [System.Windows.Forms.MessageBox]::Show($dlg, $msg, "形式チェック", [System.Windows.Forms.MessageBoxButtons]::OK, $ic) | Out-Null
        }
    })

    $btnRawSave.Add_Click({
        $targetPath = & $resolveSelectedRawFilePath
        if ($targetPath.ToLower().EndsWith(".json")) {
            try {
                $null = $txtRawEditor.Text | ConvertFrom-Json
            } catch {
                [System.Windows.Forms.MessageBox]::Show($dlg, "JSON に構文エラーがあるため保存できません:`n$($_.Exception.Message)", "保存エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
                return
            }
        }
        try {
            $parentDir = Split-Path -Parent $targetPath
            if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
            if (Test-Path -LiteralPath $targetPath) {
                Copy-Item -LiteralPath $targetPath -Destination ($targetPath + ".bak") -Force -ErrorAction SilentlyContinue
            }
            $utf8Bom = New-Object System.Text.UTF8Encoding($true)
            $normText = $txtRawEditor.Text.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
            [System.IO.File]::WriteAllText($targetPath, $normText, $utf8Bom)
            if ($targetPath -ieq $iniPath) {
                $script:SettingsSaved = $true
            }
            [System.Windows.Forms.MessageBox]::Show($dlg, "保存しました:`n$targetPath`n（バックアップ: .bak）", "保存完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show($dlg, "保存に失敗しました:`n$($_.Exception.Message)", "保存エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $runBatchHelper = {
        param([string]$RelBat, [string]$Label)
        $batPath = Join-Path $RootDir $RelBat
        if (-not (Test-Path -LiteralPath $batPath)) {
            [System.Windows.Forms.MessageBox]::Show($dlg, "ファイルが見つかりません:`n$batPath", "確認", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$batPath`"" -WorkingDirectory (Split-Path -Parent $batPath)
    }
    $btnRegCtx.Add_Click({ & $runBatchHelper "RegisterContextMenu.bat" "右クリックメニュー登録" })
    $btnRegProto.Add_Click({ & $runBatchHelper "RegisterProtocol.bat" "URLプロトコル登録" })
    $btnRegGiga.Add_Click({ & $runBatchHelper "gigafile\install_gigafile_sendto.bat" "ギガファイル便SendTo登録" })
    $btnRunTests.Add_Click({ & $runBatchHelper "RunTestManager.bat" "モジュールテスト" })

    # パス存在チェック
    $btnCheckPaths.Add_Click({
        $okList = New-Object System.Collections.Generic.List[string]
        $ngList = New-Object System.Collections.Generic.List[string]
        foreach ($def in $pathFieldDefs) {
            if ($def.Kind -eq "Text") { continue }
            $val = $pathTextBoxes[$def.Key].Text.Trim()
            if ([string]::IsNullOrWhiteSpace($val)) { continue }
            if (Test-Path -LiteralPath $val) {
                [void]$okList.Add("[OK] $($def.Key): $val")
            } else {
                [void]$ngList.Add("[未検出] $($def.Key): $val")
            }
        }
        $msg = "存在確認結果: OK $($okList.Count) 件 / 未検出 $($ngList.Count) 件`n"
        if ($ngList.Count -gt 0) {
            $msg += "`n--- 未検出パス ---`n" + ($ngList -join "`n")
        } else {
            $msg += "`n入力されているすべてのパスが存在することを確認しました。"
        }
        $ic = if ($ngList.Count -eq 0) { [System.Windows.Forms.MessageBoxIcon]::Information } else { [System.Windows.Forms.MessageBoxIcon]::Warning }
        [System.Windows.Forms.MessageBox]::Show($dlg, $msg, "パス存在チェック", [System.Windows.Forms.MessageBoxButtons]::OK, $ic) | Out-Null
    })

    # 標準値に戻す
    $btnResetDefault.Add_Click({
        $ans = [System.Windows.Forms.MessageBox]::Show($dlg, "入力欄をすべて初期標準値へ戻しますか？（「保存して反映」を押すまでファイルは書き換わりません）", "確認", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        foreach ($def in $pathFieldDefs) {
            $pathTextBoxes[$def.Key].Text = $def.Default
        }
        $qBoxes["Q1_Months"].Text = "1,2,3"
        $qBoxes["Q2_Months"].Text = "4,5,6"
        $qBoxes["Q3_Months"].Text = "7,8,9"
        $qBoxes["Q4_Months"].Text = "10,11,12"
        $txtRawExt.Text = ".ARW,.CR2,.CR3,.NEF,.RAF,.ORF,.RW2,.DNG"
        $txtImgExt.Text = ".JPG,.JPEG,.PNG,.TIF,.TIFF"
        $txtMegaCmd.Text = ""
        $txtMegaRem.Text = "/写真1/現像後"
        $txtMegaLog.Text = (Join-Path $RootDir "data\logs\mega_debug.log")
        $script:SettingsDirty = $true
    })

    $btnOpenIniFolder.Add_Click({
        if (Test-Path -LiteralPath $RootDir) {
            Start-Process "explorer.exe" -ArgumentList "`"$RootDir`""
        }
    })

    # 保存して反映
    $btnSave.Add_Click({
        try {
            $pathsDict = @{}
            foreach ($def in $pathFieldDefs) {
                $pathsDict[$def.Key] = $pathTextBoxes[$def.Key].Text.Trim()
            }
            $settingsPayload = @{
                Paths = $pathsDict
                ArchivePeriod = @{
                    Q1_Months = $qBoxes["Q1_Months"].Text.Trim()
                    Q2_Months = $qBoxes["Q2_Months"].Text.Trim()
                    Q3_Months = $qBoxes["Q3_Months"].Text.Trim()
                    Q4_Months = $qBoxes["Q4_Months"].Text.Trim()
                }
                Extensions = @{
                    RawExtensions   = $txtRawExt.Text.Trim()
                    ImageExtensions = $txtImgExt.Text.Trim()
                }
                Mega = @{
                    MegaCmdPath    = $txtMegaCmd.Text.Trim()
                    MegaRemoteRoot = $txtMegaRem.Text.Trim()
                    MegaLogPath    = $txtMegaLog.Text.Trim()
                }
            }
            [void](Save-PhotoToolsSettingsIni -IniPath $iniPath -Settings $settingsPayload)
            $script:SettingsDirty = $false
            $script:SettingsSaved = $true
            if ($cmbRawFile.SelectedIndex -eq 0) { & $loadSelectedRawFile }
            [System.Windows.Forms.MessageBox]::Show($dlg, "settings.ini を保存しました。`nPhotoTools Master に新しい設定を即時反映します。", "保存完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dlg.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show($dlg, "settings.ini の保存中にエラーが発生しました:`n$($_.Exception.Message)", "保存エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $btnClose.Add_Click({
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dlg.Close()
    })

    $dlg.Add_FormClosing({
        param($s, $e)
        if ($script:SettingsDirty) {
            $ans = [System.Windows.Forms.MessageBox]::Show($dlg, "未保存の設定変更があります。保存せずに閉じますか？", "確認", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
                $e.Cancel = $true
            }
        }
    })

    & $loadSelectedRawFile
    $script:IsPopulatingUI = $false

    if ($null -ne $OwnerForm) {
        [void]$dlg.ShowDialog($OwnerForm)
    } else {
        [void]$dlg.ShowDialog()
    }
    $dlg.Dispose()
    return $script:SettingsSaved
}

if ($MyInvocation.InvocationName -ne '.') {
    [void](Show-PhotoToolsSettingsDialog -RootDir $RootDir)
}
