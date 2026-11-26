#requires -Version 5.1
# ==============================================================================
# SettingsEditor.ps1 - settings.ini・関連設定/履歴ファイル編集GUI (UTF-8 BOM / CRLF)
# ==============================================================================
param(
    [string]$RootDir = "",
    [int]$InitialTabIndex = 0
)

Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-PhotoToolsSettingsDialog {
    param(
        [string]$RootDir = "",
        [System.Windows.Forms.IWin32Window]$OwnerForm = $null,
        [int]$InitialTabIndex = 0
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
    $msgHelper = Join-Path $commonDir "MessageTemplateHelper.ps1"
    $aiHelper  = Join-Path $commonDir "GeminiCharacterHelper.ps1"
    if (Test-Path -LiteralPath $cfgHelper) { . $cfgHelper }
    if (Test-Path -LiteralPath $logHelper) { . $logHelper }
    if (Test-Path -LiteralPath $msgHelper) { . $msgHelper }
    if (Test-Path -LiteralPath $aiHelper)  { . $aiHelper }

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
    [void]$cmbRawFile.Items.Add("message_templates.json (メッセージ定型文・MEGAコメント)")
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
    # タブ4: メッセージ定型文・MEGAコメント設定 (data\message_templates.json)
    # --------------------------------------------------------------------------
    $tpMsgTpl = New-Object System.Windows.Forms.TabPage
    $tpMsgTpl.Text = "メッセージ定型文"
    $tpMsgTpl.BackColor = [System.Drawing.Color]::White
    $tabs.Controls.Add($tpMsgTpl)

    $msgTplPath = if (Get-Command Get-MessageTemplateFilePath -ErrorAction SilentlyContinue) {
        Get-MessageTemplateFilePath -RootDir $RootDir -Config $cfg
    } else {
        Join-Path $RootDir "data\message_templates.json"
    }
    $script:MsgTplStore = if (Get-Command Get-MessageTemplateStore -ErrorAction SilentlyContinue) {
        Get-MessageTemplateStore -FilePath $msgTplPath -RootDir $RootDir -Config $cfg
    } else {
        [ordered]@{ Version = 1; Templates = @(); MegaCommentPresets = @(); DefaultMegaCommentId = "" }
    }
    $script:TplWorkingList = New-Object System.Collections.ArrayList
    foreach ($t in @($script:MsgTplStore.Templates)) { [void]$script:TplWorkingList.Add($t) }
    $script:MegaPresetWorkingList = New-Object System.Collections.ArrayList
    foreach ($mp in @($script:MsgTplStore.MegaCommentPresets)) { [void]$script:MegaPresetWorkingList.Add($mp) }
    $script:DefaultMegaPresetId = [string]$script:MsgTplStore.DefaultMegaCommentId
    $script:IsPopulatingMsgTplUI = $false

    # 上段: 定型文テンプレート管理
    $grpTplMgr = New-Object System.Windows.Forms.GroupBox
    $grpTplMgr.Text = "送付メッセージ定型文（イベント・個撮・併せ・その他と連動）  保存先: $msgTplPath"
    $grpTplMgr.Location = New-Object System.Drawing.Point(12, 10)
    $grpTplMgr.Size = New-Object System.Drawing.Size(808, 304)
    $grpTplMgr.Anchor = "Top, Left, Right"
    $tpMsgTpl.Controls.Add($grpTplMgr)

    $lstTemplates = New-Object System.Windows.Forms.ListBox
    $lstTemplates.Location = New-Object System.Drawing.Point(12, 24)
    $lstTemplates.Size = New-Object System.Drawing.Size(218, 228)
    $lstTemplates.IntegralHeight = $false
    $grpTplMgr.Controls.Add($lstTemplates)

    $btnTplAdd = New-Object System.Windows.Forms.Button
    $btnTplAdd.Text = "＋ 新規"
    $btnTplAdd.Location = New-Object System.Drawing.Point(12, 260)
    $btnTplAdd.Size = New-Object System.Drawing.Size(68, 28)
    $btnTplAdd.BackColor = [System.Drawing.Color]::AliceBlue
    $grpTplMgr.Controls.Add($btnTplAdd)

    $btnTplDup = New-Object System.Windows.Forms.Button
    $btnTplDup.Text = "複製"
    $btnTplDup.Location = New-Object System.Drawing.Point(86, 260)
    $btnTplDup.Size = New-Object System.Drawing.Size(68, 28)
    $grpTplMgr.Controls.Add($btnTplDup)

    $btnTplDel = New-Object System.Windows.Forms.Button
    $btnTplDel.Text = "削除"
    $btnTplDel.Location = New-Object System.Drawing.Point(160, 260)
    $btnTplDel.Size = New-Object System.Drawing.Size(70, 28)
    $grpTplMgr.Controls.Add($btnTplDel)

    $lblTplName = New-Object System.Windows.Forms.Label
    $lblTplName.Text = "テンプレート名:"
    $lblTplName.Location = New-Object System.Drawing.Point(242, 27)
    $lblTplName.Size = New-Object System.Drawing.Size(96, 20)
    $grpTplMgr.Controls.Add($lblTplName)

    $txtTplName = New-Object System.Windows.Forms.TextBox
    $txtTplName.Location = New-Object System.Drawing.Point(340, 24)
    $txtTplName.Size = New-Object System.Drawing.Size(215, 24)
    $grpTplMgr.Controls.Add($txtTplName)

    $lblTplCat = New-Object System.Windows.Forms.Label
    $lblTplCat.Text = "連動区分:"
    $lblTplCat.Location = New-Object System.Drawing.Point(564, 27)
    $lblTplCat.Size = New-Object System.Drawing.Size(62, 20)
    $grpTplMgr.Controls.Add($lblTplCat)

    $cmbTplCat = New-Object System.Windows.Forms.ComboBox
    $cmbTplCat.Location = New-Object System.Drawing.Point(628, 24)
    $cmbTplCat.Size = New-Object System.Drawing.Size(166, 24)
    $cmbTplCat.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$cmbTplCat.Items.AddRange(@("イベント", "個撮", "併せ", "その他", "共通"))
    $cmbTplCat.SelectedIndex = 0
    $grpTplMgr.Controls.Add($cmbTplCat)

    $chkTplDefault = New-Object System.Windows.Forms.CheckBox
    $chkTplDefault.Text = "この撮影区分の既定テンプレートにする"
    $chkTplDefault.Location = New-Object System.Drawing.Point(242, 54)
    $chkTplDefault.AutoSize = $true
    $grpTplMgr.Controls.Add($chkTplDefault)

    $btnSaveMsgTemplates = New-Object System.Windows.Forms.Button
    $btnSaveMsgTemplates.Text = "定型文・MEGA設定を保存"
    $btnSaveMsgTemplates.Location = New-Object System.Drawing.Point(614, 51)
    $btnSaveMsgTemplates.Size = New-Object System.Drawing.Size(180, 26)
    $btnSaveMsgTemplates.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnSaveMsgTemplates.ForeColor = [System.Drawing.Color]::White
    $btnSaveMsgTemplates.FlatStyle = "Flat"
    $btnSaveMsgTemplates.Font = New-Object System.Drawing.Font("Meiryo UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $grpTplMgr.Controls.Add($btnSaveMsgTemplates)

    # 差し込み変数 入力支援パネル
    $lblVarHelper = New-Object System.Windows.Forms.Label
    $lblVarHelper.Text = "差し込み変数（クリックでカーソル位置へ挿入）:"
    $lblVarHelper.Location = New-Object System.Drawing.Point(242, 82)
    $lblVarHelper.Size = New-Object System.Drawing.Size(340, 18)
    $lblVarHelper.ForeColor = [System.Drawing.Color]::FromArgb(3, 105, 161)
    $lblVarHelper.Font = New-Object System.Drawing.Font("Meiryo UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $grpTplMgr.Controls.Add($lblVarHelper)

    $flpVars = New-Object System.Windows.Forms.FlowLayoutPanel
    $flpVars.Location = New-Object System.Drawing.Point(240, 102)
    $flpVars.Size = New-Object System.Drawing.Size(556, 54)
    $flpVars.WrapContents = $true
    $flpVars.AutoScroll = $false
    $grpTplMgr.Controls.Add($flpVars)

    $txtTplBody = New-Object System.Windows.Forms.TextBox
    $txtTplBody.Location = New-Object System.Drawing.Point(242, 160)
    $txtTplBody.Size = New-Object System.Drawing.Size(552, 130)
    $txtTplBody.Multiline = $true
    $txtTplBody.ScrollBars = "Vertical"
    $txtTplBody.AcceptsReturn = $true
    $txtTplBody.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5)
    $grpTplMgr.Controls.Add($txtTplBody)

    $varToolTip = New-Object System.Windows.Forms.ToolTip
    $varDefs = if (Get-Command Get-MessagePlaceholderDefinitions -ErrorAction SilentlyContinue) {
        Get-MessagePlaceholderDefinitions
    } else { @() }
    foreach ($vd in @($varDefs)) {
        $btnVar = New-Object System.Windows.Forms.Button
        $btnVar.Text = [string]$vd.Token
        $btnVar.AutoSize = $true
        $btnVar.Height = 23
        $btnVar.Margin = New-Object System.Windows.Forms.Padding(2, 2, 3, 2)
        $btnVar.Padding = New-Object System.Windows.Forms.Padding(3, 0, 3, 0)
        $btnVar.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
        $btnVar.FlatStyle = "Flat"
        $btnVar.Font = New-Object System.Drawing.Font("Meiryo UI", 8)
        $btnVar.Tag = [string]$vd.Token
        $varToolTip.SetToolTip($btnVar, [string]$vd.Description)
        $btnVar.Add_Click({
            param($s, $e)
            if (-not $txtTplBody.Enabled) { return }
            $tok = [string]$s.Tag
            $selStart = $txtTplBody.SelectionStart
            $selLen = $txtTplBody.SelectionLength
            $curTxt = $txtTplBody.Text
            $txtTplBody.Text = $curTxt.Substring(0, $selStart) + $tok + $curTxt.Substring($selStart + $selLen)
            $txtTplBody.SelectionStart = $selStart + $tok.Length
            $txtTplBody.SelectionLength = 0
            $txtTplBody.Focus()
        })
        $flpVars.Controls.Add($btnVar)
    }

    # 下段: MEGA選択時コメント設定（全テンプレート共通・複数パターン切替）
    $grpMegaPreset = New-Object System.Windows.Forms.GroupBox
    $grpMegaPreset.Text = "MEGA選択時のコメント設定（全テンプレート共通・作成画面で切替可能）"
    $grpMegaPreset.Location = New-Object System.Drawing.Point(12, 320)
    $grpMegaPreset.Size = New-Object System.Drawing.Size(808, 174)
    $grpMegaPreset.Anchor = "Top, Bottom, Left, Right"
    $tpMsgTpl.Controls.Add($grpMegaPreset)

    $lblMegaPresetSel = New-Object System.Windows.Forms.Label
    $lblMegaPresetSel.Text = "パターン選択:"
    $lblMegaPresetSel.Location = New-Object System.Drawing.Point(14, 27)
    $lblMegaPresetSel.Size = New-Object System.Drawing.Size(86, 20)
    $grpMegaPreset.Controls.Add($lblMegaPresetSel)

    $cmbMegaPreset = New-Object System.Windows.Forms.ComboBox
    $cmbMegaPreset.Location = New-Object System.Drawing.Point(104, 23)
    $cmbMegaPreset.Size = New-Object System.Drawing.Size(215, 24)
    $cmbMegaPreset.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $grpMegaPreset.Controls.Add($cmbMegaPreset)

    $btnMegaPresetAdd = New-Object System.Windows.Forms.Button
    $btnMegaPresetAdd.Text = "＋ 追加"
    $btnMegaPresetAdd.Location = New-Object System.Drawing.Point(326, 22)
    $btnMegaPresetAdd.Size = New-Object System.Drawing.Size(66, 26)
    $grpMegaPreset.Controls.Add($btnMegaPresetAdd)

    $btnMegaPresetDel = New-Object System.Windows.Forms.Button
    $btnMegaPresetDel.Text = "削除"
    $btnMegaPresetDel.Location = New-Object System.Drawing.Point(398, 22)
    $btnMegaPresetDel.Size = New-Object System.Drawing.Size(58, 26)
    $grpMegaPreset.Controls.Add($btnMegaPresetDel)

    $chkMegaPresetDefault = New-Object System.Windows.Forms.CheckBox
    $chkMegaPresetDefault.Text = "このパターンを初期選択（既定）にする"
    $chkMegaPresetDefault.Location = New-Object System.Drawing.Point(470, 26)
    $chkMegaPresetDefault.AutoSize = $true
    $grpMegaPreset.Controls.Add($chkMegaPresetDefault)

    $lblMegaPresetName = New-Object System.Windows.Forms.Label
    $lblMegaPresetName.Text = "パターン名:"
    $lblMegaPresetName.Location = New-Object System.Drawing.Point(14, 57)
    $lblMegaPresetName.Size = New-Object System.Drawing.Size(86, 20)
    $grpMegaPreset.Controls.Add($lblMegaPresetName)

    $txtMegaPresetName = New-Object System.Windows.Forms.TextBox
    $txtMegaPresetName.Location = New-Object System.Drawing.Point(104, 53)
    $txtMegaPresetName.Size = New-Object System.Drawing.Size(270, 24)
    $grpMegaPreset.Controls.Add($txtMegaPresetName)

    $lblMegaPresetHint = New-Object System.Windows.Forms.Label
    $lblMegaPresetHint.Text = "※本文に {MEGAコメント} が無い場合は {データリンク} の直下へ自動付与されます。"
    $lblMegaPresetHint.Location = New-Object System.Drawing.Point(384, 57)
    $lblMegaPresetHint.Size = New-Object System.Drawing.Size(412, 18)
    $lblMegaPresetHint.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
    $lblMegaPresetHint.Font = New-Object System.Drawing.Font("Meiryo UI", 8)
    $grpMegaPreset.Controls.Add($lblMegaPresetHint)

    $txtMegaPresetBody = New-Object System.Windows.Forms.TextBox
    $txtMegaPresetBody.Location = New-Object System.Drawing.Point(14, 83)
    $txtMegaPresetBody.Size = New-Object System.Drawing.Size(780, 78)
    $txtMegaPresetBody.Anchor = "Top, Bottom, Left, Right"
    $txtMegaPresetBody.Multiline = $true
    $txtMegaPresetBody.ScrollBars = "Vertical"
    $txtMegaPresetBody.AcceptsReturn = $true
    $txtMegaPresetBody.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9)
    $grpMegaPreset.Controls.Add($txtMegaPresetBody)

    # --- メッセージ定型文タブの内部ロジック ---
    $syncCurrentTemplateFromUI = {
        if ($script:IsPopulatingMsgTplUI) { return }
        $idx = $lstTemplates.SelectedIndex
        if ($idx -lt 0 -or $idx -ge $script:TplWorkingList.Count) { return }
        $item = $script:TplWorkingList[$idx]
        $item["Name"] = $txtTplName.Text.Trim()
        $item["Category"] = [string]$cmbTplCat.SelectedItem
        $item["IsDefault"] = [bool]$chkTplDefault.Checked
        $item["Body"] = $txtTplBody.Text
        if ($item["IsDefault"]) {
            for ($j = 0; $j -lt $script:TplWorkingList.Count; $j++) {
                if ($j -ne $idx -and [string]$script:TplWorkingList[$j]["Category"] -eq [string]$item["Category"]) {
                    $script:TplWorkingList[$j]["IsDefault"] = $false
                }
            }
        }
    }

    $refreshTemplateListBox = {
        param([int]$SelectIdx = 0)
        $script:IsPopulatingMsgTplUI = $true
        try {
            $lstTemplates.Items.Clear()
            for ($i = 0; $i -lt $script:TplWorkingList.Count; $i++) {
                $t = $script:TplWorkingList[$i]
                $nm = if ([string]::IsNullOrWhiteSpace([string]$t["Name"])) { "(無題)" } else { [string]$t["Name"] }
                $ct = [string]$t["Category"]
                $df = if ([bool]$t["IsDefault"]) { " ★" } else { "" }
                [void]$lstTemplates.Items.Add("[$ct] $nm$df")
            }
            $hasItems = ($script:TplWorkingList.Count -gt 0)
            $txtTplName.Enabled = $hasItems
            $cmbTplCat.Enabled = $hasItems
            $chkTplDefault.Enabled = $hasItems
            $txtTplBody.Enabled = $hasItems
            $btnTplDup.Enabled = $hasItems
            $btnTplDel.Enabled = $hasItems
            if ($hasItems) {
                if ($SelectIdx -lt 0) { $SelectIdx = 0 }
                if ($SelectIdx -ge $script:TplWorkingList.Count) { $SelectIdx = $script:TplWorkingList.Count - 1 }
                $lstTemplates.SelectedIndex = $SelectIdx
                $cur = $script:TplWorkingList[$SelectIdx]
                $txtTplName.Text = [string]$cur["Name"]
                if ($cmbTplCat.Items.Contains([string]$cur["Category"])) { $cmbTplCat.SelectedItem = [string]$cur["Category"] } else { $cmbTplCat.SelectedIndex = 0 }
                $chkTplDefault.Checked = [bool]$cur["IsDefault"]
                $txtTplBody.Text = ([string]$cur["Body"]).Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
            } else {
                $txtTplName.Text = ""
                $cmbTplCat.SelectedIndex = 0
                $chkTplDefault.Checked = $false
                $txtTplBody.Text = ""
            }
        } finally {
            $script:IsPopulatingMsgTplUI = $false
        }
    }

    $syncCurrentMegaPresetFromUI = {
        if ($script:IsPopulatingMsgTplUI) { return }
        $idx = $cmbMegaPreset.SelectedIndex
        if ($idx -lt 0 -or $idx -ge $script:MegaPresetWorkingList.Count) { return }
        $mp = $script:MegaPresetWorkingList[$idx]
        $mp["Name"] = $txtMegaPresetName.Text.Trim()
        $mp["Body"] = $txtMegaPresetBody.Text
        if ($chkMegaPresetDefault.Checked) {
            $script:DefaultMegaPresetId = [string]$mp["Id"]
        }
    }

    $refreshMegaPresetCombo = {
        param([int]$SelectIdx = -1)
        $script:IsPopulatingMsgTplUI = $true
        try {
            $cmbMegaPreset.Items.Clear()
            $defIdx = 0
            for ($i = 0; $i -lt $script:MegaPresetWorkingList.Count; $i++) {
                $mp = $script:MegaPresetWorkingList[$i]
                $isDef = ([string]$mp["Id"] -eq $script:DefaultMegaPresetId)
                if ($isDef) { $defIdx = $i }
                $tag = if ($isDef) { " ★既定" } else { "" }
                [void]$cmbMegaPreset.Items.Add(([string]$mp["Name"]) + $tag)
            }
            if ($script:MegaPresetWorkingList.Count -gt 0) {
                if ($SelectIdx -lt 0 -or $SelectIdx -ge $script:MegaPresetWorkingList.Count) { $SelectIdx = $defIdx }
                $cmbMegaPreset.SelectedIndex = $SelectIdx
                $curMp = $script:MegaPresetWorkingList[$SelectIdx]
                $txtMegaPresetName.Text = [string]$curMp["Name"]
                $txtMegaPresetBody.Text = ([string]$curMp["Body"]).Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
                $chkMegaPresetDefault.Checked = ([string]$curMp["Id"] -eq $script:DefaultMegaPresetId)
            }
        } finally {
            $script:IsPopulatingMsgTplUI = $false
        }
    }

    $script:PrevTplIdx = -1
    $lstTemplates.Add_SelectedIndexChanged({
        if ($script:IsPopulatingMsgTplUI) { return }
        if ($script:PrevTplIdx -ge 0 -and $script:PrevTplIdx -lt $script:TplWorkingList.Count -and $script:PrevTplIdx -ne $lstTemplates.SelectedIndex) {
            $prevItem = $script:TplWorkingList[$script:PrevTplIdx]
            $prevItem["Name"] = $txtTplName.Text.Trim()
            $prevItem["Category"] = [string]$cmbTplCat.SelectedItem
            $prevItem["IsDefault"] = [bool]$chkTplDefault.Checked
            $prevItem["Body"] = $txtTplBody.Text
        }
        $idx = $lstTemplates.SelectedIndex
        $script:PrevTplIdx = $idx
        if ($idx -ge 0 -and $idx -lt $script:TplWorkingList.Count) {
            $script:IsPopulatingMsgTplUI = $true
            try {
                $cur = $script:TplWorkingList[$idx]
                $txtTplName.Text = [string]$cur["Name"]
                if ($cmbTplCat.Items.Contains([string]$cur["Category"])) { $cmbTplCat.SelectedItem = [string]$cur["Category"] } else { $cmbTplCat.SelectedIndex = 0 }
                $chkTplDefault.Checked = [bool]$cur["IsDefault"]
                $txtTplBody.Text = ([string]$cur["Body"]).Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
            } finally {
                $script:IsPopulatingMsgTplUI = $false
            }
        }
    })

    $btnTplAdd.Add_Click({
        & $syncCurrentTemplateFromUI
        $newTpl = [ordered]@{
            Id        = [Guid]::NewGuid().ToString("N")
            Name      = "新規テンプレート" + ($script:TplWorkingList.Count + 1)
            Category  = "イベント"
            IsDefault = ($script:TplWorkingList.Count -eq 0)
            Body      = ""
        }
        [void]$script:TplWorkingList.Add($newTpl)
        $script:PrevTplIdx = $script:TplWorkingList.Count - 1
        & $refreshTemplateListBox ($script:TplWorkingList.Count - 1)
        $txtTplName.Focus()
        $txtTplName.SelectAll()
    })

    $btnTplDup.Add_Click({
        & $syncCurrentTemplateFromUI
        $idx = $lstTemplates.SelectedIndex
        if ($idx -lt 0 -or $idx -ge $script:TplWorkingList.Count) { return }
        $src = $script:TplWorkingList[$idx]
        $dup = [ordered]@{
            Id        = [Guid]::NewGuid().ToString("N")
            Name      = ([string]$src["Name"]) + " (コピー)"
            Category  = [string]$src["Category"]
            IsDefault = $false
            Body      = [string]$src["Body"]
        }
        [void]$script:TplWorkingList.Add($dup)
        $script:PrevTplIdx = $script:TplWorkingList.Count - 1
        & $refreshTemplateListBox ($script:TplWorkingList.Count - 1)
    })

    $btnTplDel.Add_Click({
        $idx = $lstTemplates.SelectedIndex
        if ($idx -lt 0 -or $idx -ge $script:TplWorkingList.Count) { return }
        $ans = [System.Windows.Forms.MessageBox]::Show($dlg, "選択中のテンプレート「$($script:TplWorkingList[$idx]['Name'])」を削除しますか？", "削除確認", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $script:TplWorkingList.RemoveAt($idx)
        $nextIdx = [Math]::Max(0, $idx - 1)
        $script:PrevTplIdx = if ($script:TplWorkingList.Count -gt 0) { $nextIdx } else { -1 }
        & $refreshTemplateListBox $nextIdx
    })

    $script:PrevMegaIdx = -1
    $cmbMegaPreset.Add_SelectedIndexChanged({
        if ($script:IsPopulatingMsgTplUI) { return }
        if ($script:PrevMegaIdx -ge 0 -and $script:PrevMegaIdx -lt $script:MegaPresetWorkingList.Count -and $script:PrevMegaIdx -ne $cmbMegaPreset.SelectedIndex) {
            $prevMp = $script:MegaPresetWorkingList[$script:PrevMegaIdx]
            $prevMp["Name"] = $txtMegaPresetName.Text.Trim()
            $prevMp["Body"] = $txtMegaPresetBody.Text
        }
        $idx = $cmbMegaPreset.SelectedIndex
        $script:PrevMegaIdx = $idx
        if ($idx -ge 0 -and $idx -lt $script:MegaPresetWorkingList.Count) {
            $script:IsPopulatingMsgTplUI = $true
            try {
                $curMp = $script:MegaPresetWorkingList[$idx]
                $txtMegaPresetName.Text = [string]$curMp["Name"]
                $txtMegaPresetBody.Text = ([string]$curMp["Body"]).Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
                $chkMegaPresetDefault.Checked = ([string]$curMp["Id"] -eq $script:DefaultMegaPresetId)
            } finally {
                $script:IsPopulatingMsgTplUI = $false
            }
        }
    })

    $btnMegaPresetAdd.Add_Click({
        & $syncCurrentMegaPresetFromUI
        $newMp = [ordered]@{
            Id   = "mega_custom_" + ([Guid]::NewGuid().ToString("N").Substring(0, 8))
            Name = "カスタムコメント" + ($script:MegaPresetWorkingList.Count + 1)
            Body = ""
        }
        [void]$script:MegaPresetWorkingList.Add($newMp)
        $script:PrevMegaIdx = $script:MegaPresetWorkingList.Count - 1
        & $refreshMegaPresetCombo ($script:MegaPresetWorkingList.Count - 1)
        $txtMegaPresetName.Focus()
        $txtMegaPresetName.SelectAll()
    })

    $btnMegaPresetDel.Add_Click({
        $idx = $cmbMegaPreset.SelectedIndex
        if ($idx -lt 0 -or $idx -ge $script:MegaPresetWorkingList.Count) { return }
        if ($script:MegaPresetWorkingList.Count -le 1) {
            [System.Windows.Forms.MessageBox]::Show($dlg, "MEGAコメントパターンは最低1件必要です。", "確認", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        $ans = [System.Windows.Forms.MessageBox]::Show($dlg, "パターン「$($script:MegaPresetWorkingList[$idx]['Name'])」を削除しますか？", "削除確認", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $script:MegaPresetWorkingList.RemoveAt($idx)
        $nextIdx = [Math]::Max(0, $idx - 1)
        $script:PrevMegaIdx = $nextIdx
        & $refreshMegaPresetCombo $nextIdx
    })

    $chkMegaPresetDefault.Add_CheckedChanged({
        if ($script:IsPopulatingMsgTplUI) { return }
        if ($chkMegaPresetDefault.Checked -and $cmbMegaPreset.SelectedIndex -ge 0 -and $cmbMegaPreset.SelectedIndex -lt $script:MegaPresetWorkingList.Count) {
            $script:DefaultMegaPresetId = [string]$script:MegaPresetWorkingList[$cmbMegaPreset.SelectedIndex]["Id"]
            & $refreshMegaPresetCombo $cmbMegaPreset.SelectedIndex
        }
    })

    $btnSaveMsgTemplates.Add_Click({
        & $syncCurrentTemplateFromUI
        & $syncCurrentMegaPresetFromUI
        try {
            $storeToSave = [ordered]@{
                Version              = 1
                Templates            = @($script:TplWorkingList.ToArray())
                MegaCommentPresets   = @($script:MegaPresetWorkingList.ToArray())
                DefaultMegaCommentId = $script:DefaultMegaPresetId
            }
            $savedPath = Save-MessageTemplateStore -Store $storeToSave -FilePath $msgTplPath -RootDir $RootDir -Config $cfg
            & $refreshTemplateListBox ([Math]::Max(0, $lstTemplates.SelectedIndex))
            & $refreshMegaPresetCombo ([Math]::Max(0, $cmbMegaPreset.SelectedIndex))
            [System.Windows.Forms.MessageBox]::Show($dlg, "メッセージ定型文・MEGAコメント設定を保存しました:`n$savedPath", "保存完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show($dlg, "定型文の保存に失敗しました:`n$($_.Exception.Message)", "保存エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    & $refreshTemplateListBox 0
    $script:PrevTplIdx = $lstTemplates.SelectedIndex
    & $refreshMegaPresetCombo -1
    $script:PrevMegaIdx = $cmbMegaPreset.SelectedIndex

    # --------------------------------------------------------------------------
    # タブ5: AIキャラ判定設定（漏洩対策・Windows DPAPI暗号化キー管理）
    # --------------------------------------------------------------------------
    $tpAi = New-Object System.Windows.Forms.TabPage
    $tpAi.Text = "AIキャラ判定"
    $tpAi.BackColor = [System.Drawing.Color]::White
    $tabs.Controls.Add($tpAi)

    $aiSettingsObj = if (Get-Command Get-GeminiCharacterSettings -ErrorAction SilentlyContinue) {
        Get-GeminiCharacterSettings -RootDir $RootDir -Config $cfg
    } else {
        [ordered]@{ Version = 1; ModelName = "gemini-2.5-flash"; PaidTierConfirmed = $false; MaxImageEdgePx = 640; JpegQuality = 75; DefaultMaskStyle = "Black"; DefaultOutputFormat = "CharWithSeries" }
    }
    $aiKeyFilePath = if (Get-Command Get-GeminiKeyPath -ErrorAction SilentlyContinue) {
        Get-GeminiKeyPath -RootDir $RootDir -Config $cfg
    } else { Join-Path $RootDir "data\gemini_api_key.dat" }
    $aiSettingsFilePath = if (Get-Command Get-GeminiSettingsPath -ErrorAction SilentlyContinue) {
        Get-GeminiSettingsPath -RootDir $RootDir -Config $cfg
    } else { Join-Path $RootDir "data\ai_character_settings.json" }

    # 1. APIキー管理 (DPAPI)
    $grpAiKey = New-Object System.Windows.Forms.GroupBox
    $grpAiKey.Text = "1. Gemini APIキー（Windows DPAPI 暗号化保存・settings.ini/ZIP には一切出力しません）"
    $grpAiKey.Location = New-Object System.Drawing.Point(14, 12)
    $grpAiKey.Size = New-Object System.Drawing.Size(804, 134)
    $grpAiKey.Anchor = "Top, Left, Right"
    $tpAi.Controls.Add($grpAiKey)

    $lblAiKeyStatus = New-Object System.Windows.Forms.Label
    $lblAiKeyStatus.Location = New-Object System.Drawing.Point(14, 26)
    $lblAiKeyStatus.Size = New-Object System.Drawing.Size(774, 20)
    $lblAiKeyStatus.Font = New-Object System.Drawing.Font("Meiryo UI", 9, [System.Drawing.FontStyle]::Bold)
    $grpAiKey.Controls.Add($lblAiKeyStatus)

    $lblAiKeyInput = New-Object System.Windows.Forms.Label
    $lblAiKeyInput.Text = "新しいAPIキー:"
    $lblAiKeyInput.Location = New-Object System.Drawing.Point(14, 56)
    $lblAiKeyInput.Size = New-Object System.Drawing.Size(102, 22)
    $grpAiKey.Controls.Add($lblAiKeyInput)

    $txtAiKeyInput = New-Object System.Windows.Forms.TextBox
    $txtAiKeyInput.Location = New-Object System.Drawing.Point(120, 53)
    $txtAiKeyInput.Size = New-Object System.Drawing.Size(376, 24)
    $txtAiKeyInput.UseSystemPasswordChar = $true
    $grpAiKey.Controls.Add($txtAiKeyInput)

    $btnAiSaveKey = New-Object System.Windows.Forms.Button
    $btnAiSaveKey.Text = "暗号化して保存"
    $btnAiSaveKey.Location = New-Object System.Drawing.Point(504, 51)
    $btnAiSaveKey.Size = New-Object System.Drawing.Size(134, 28)
    $btnAiSaveKey.BackColor = [System.Drawing.Color]::FromArgb(15, 118, 110)
    $btnAiSaveKey.ForeColor = [System.Drawing.Color]::White
    $btnAiSaveKey.FlatStyle = "Flat"
    $grpAiKey.Controls.Add($btnAiSaveKey)

    $btnAiDeleteKey = New-Object System.Windows.Forms.Button
    $btnAiDeleteKey.Text = "保存キーを削除"
    $btnAiDeleteKey.Location = New-Object System.Drawing.Point(646, 51)
    $btnAiDeleteKey.Size = New-Object System.Drawing.Size(142, 28)
    $btnAiDeleteKey.BackColor = [System.Drawing.Color]::White
    $grpAiKey.Controls.Add($btnAiDeleteKey)

    $lblAiKeyNote = New-Object System.Windows.Forms.Label
    $lblAiKeyNote.Text = "保存先: $aiKeyFilePath`r`n※現在の Windows ログインユーザー専用キーで暗号化されるため、他PCへコピーしても復号できません。"
    $lblAiKeyNote.Location = New-Object System.Drawing.Point(14, 86)
    $lblAiKeyNote.Size = New-Object System.Drawing.Size(774, 38)
    $lblAiKeyNote.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $lblAiKeyNote.Font = New-Object System.Drawing.Font("Meiryo UI", 8)
    $grpAiKey.Controls.Add($lblAiKeyNote)

    # 2. 漏洩リスク対策・有料枠確認
    $grpAiPrivacy = New-Object System.Windows.Forms.GroupBox
    $grpAiPrivacy.Text = "2. 漏洩リスク対策・有料枠確認（必須）"
    $grpAiPrivacy.Location = New-Object System.Drawing.Point(14, 156)
    $grpAiPrivacy.Size = New-Object System.Drawing.Size(804, 112)
    $grpAiPrivacy.Anchor = "Top, Left, Right"
    $tpAi.Controls.Add($grpAiPrivacy)

    $chkAiPaidTier = New-Object System.Windows.Forms.CheckBox
    $chkAiPaidTier.Text = "Google Cloud 請求先アカウントを紐づけ済み（有料枠・モデル学習/製品改善に使用されない規約）であることを確認しました"
    $chkAiPaidTier.Location = New-Object System.Drawing.Point(14, 24)
    $chkAiPaidTier.Size = New-Object System.Drawing.Size(774, 24)
    $chkAiPaidTier.Font = New-Object System.Drawing.Font("Meiryo UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $chkAiPaidTier.ForeColor = [System.Drawing.Color]::FromArgb(153, 27, 27)
    $chkAiPaidTier.Checked = [bool]$aiSettingsObj["PaidTierConfirmed"]
    $grpAiPrivacy.Controls.Add($chkAiPaidTier)

    $lblAiGuards = New-Object System.Windows.Forms.Label
    $lblAiGuards.Text = "自動適用される保護: ①送信前プレビューでの顔マスク（未設定時は警告確認）  ②Exif/メタデータ完全削除  ③低解像度自動縮小`r`n④一時ファイル保存なし（完全インメモリ処理）  ⑤モデル名・Xアカウント・日付・ファイル名等の個人情報非送信  ⑥手動実行のみ"
    $lblAiGuards.Location = New-Object System.Drawing.Point(14, 54)
    $lblAiGuards.Size = New-Object System.Drawing.Size(774, 46)
    $lblAiGuards.ForeColor = [System.Drawing.Color]::FromArgb(30, 64, 175)
    $lblAiGuards.Font = New-Object System.Drawing.Font("Meiryo UI", 8.5)
    $grpAiPrivacy.Controls.Add($lblAiGuards)

    # 3. モデル・画像保護・出力書式設定
    $grpAiOpts = New-Object System.Windows.Forms.GroupBox
    $grpAiOpts.Text = "3. モデル・画像縮小・出力書式設定（保存先: $aiSettingsFilePath）"
    $grpAiOpts.Location = New-Object System.Drawing.Point(14, 278)
    $grpAiOpts.Size = New-Object System.Drawing.Size(804, 210)
    $grpAiOpts.Anchor = "Top, Left, Right"
    $tpAi.Controls.Add($grpAiOpts)

    $lblAiModel = New-Object System.Windows.Forms.Label
    $lblAiModel.Text = "使用モデル:"
    $lblAiModel.Location = New-Object System.Drawing.Point(14, 30)
    $lblAiModel.Size = New-Object System.Drawing.Size(140, 22)
    $grpAiOpts.Controls.Add($lblAiModel)

    $cmbAiModel = New-Object System.Windows.Forms.ComboBox
    $cmbAiModel.Location = New-Object System.Drawing.Point(160, 27)
    $cmbAiModel.Size = New-Object System.Drawing.Size(260, 24)
    $cmbAiModel.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    [void]$cmbAiModel.Items.AddRange(@("gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-2.5-pro"))
    $cmbAiModel.Text = [string]$aiSettingsObj["ModelName"]
    $grpAiOpts.Controls.Add($cmbAiModel)

    $lblAiMaxPx = New-Object System.Windows.Forms.Label
    $lblAiMaxPx.Text = "送信時の最大長辺 (px):"
    $lblAiMaxPx.Location = New-Object System.Drawing.Point(14, 66)
    $lblAiMaxPx.Size = New-Object System.Drawing.Size(140, 22)
    $grpAiOpts.Controls.Add($lblAiMaxPx)

    $cmbAiMaxPx = New-Object System.Windows.Forms.ComboBox
    $cmbAiMaxPx.Location = New-Object System.Drawing.Point(160, 63)
    $cmbAiMaxPx.Size = New-Object System.Drawing.Size(140, 24)
    $cmbAiMaxPx.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$cmbAiMaxPx.Items.AddRange(@("512", "640", "768", "1024"))
    $curPxStr = [string]$aiSettingsObj["MaxImageEdgePx"]
    $pxIdx = $cmbAiMaxPx.Items.IndexOf($curPxStr)
    $cmbAiMaxPx.SelectedIndex = if ($pxIdx -ge 0) { $pxIdx } else { 1 }
    $grpAiOpts.Controls.Add($cmbAiMaxPx)

    $lblAiMaskStyle = New-Object System.Windows.Forms.Label
    $lblAiMaskStyle.Text = "既定マスク方式:"
    $lblAiMaskStyle.Location = New-Object System.Drawing.Point(450, 66)
    $lblAiMaskStyle.Size = New-Object System.Drawing.Size(108, 22)
    $grpAiOpts.Controls.Add($lblAiMaskStyle)

    $cmbAiMaskStyle = New-Object System.Windows.Forms.ComboBox
    $cmbAiMaskStyle.Location = New-Object System.Drawing.Point(564, 63)
    $cmbAiMaskStyle.Size = New-Object System.Drawing.Size(140, 24)
    $cmbAiMaskStyle.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$cmbAiMaskStyle.Items.AddRange(@("黒塗り", "モザイク"))
    $cmbAiMaskStyle.SelectedIndex = if ([string]$aiSettingsObj["DefaultMaskStyle"] -eq "Mosaic") { 1 } else { 0 }
    $grpAiOpts.Controls.Add($cmbAiMaskStyle)

    $lblAiOutFmt = New-Object System.Windows.Forms.Label
    $lblAiOutFmt.Text = "衣装・キャラ反映書式:"
    $lblAiOutFmt.Location = New-Object System.Drawing.Point(14, 102)
    $lblAiOutFmt.Size = New-Object System.Drawing.Size(140, 22)
    $grpAiOpts.Controls.Add($lblAiOutFmt)

    $cmbAiOutFmt = New-Object System.Windows.Forms.ComboBox
    $cmbAiOutFmt.Location = New-Object System.Drawing.Point(160, 99)
    $cmbAiOutFmt.Size = New-Object System.Drawing.Size(260, 24)
    $cmbAiOutFmt.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$cmbAiOutFmt.Items.Add("キャラ名（作品名）")
    [void]$cmbAiOutFmt.Items.Add("キャラ名のみ")
    [void]$cmbAiOutFmt.Items.Add("作品名 / キャラ名")
    switch ([string]$aiSettingsObj["DefaultOutputFormat"]) {
        "CharOnly"        { $cmbAiOutFmt.SelectedIndex = 1 }
        "SeriesSlashChar" { $cmbAiOutFmt.SelectedIndex = 2 }
        default           { $cmbAiOutFmt.SelectedIndex = 0 }
    }
    $grpAiOpts.Controls.Add($cmbAiOutFmt)

    $btnAiTestConn = New-Object System.Windows.Forms.Button
    $btnAiTestConn.Text = "接続テスト（無料・トークン消費なし）"
    $btnAiTestConn.Location = New-Object System.Drawing.Point(14, 152)
    $btnAiTestConn.Size = New-Object System.Drawing.Size(260, 34)
    $btnAiTestConn.BackColor = [System.Drawing.Color]::AliceBlue
    $grpAiOpts.Controls.Add($btnAiTestConn)

    $btnAiSaveSettings = New-Object System.Windows.Forms.Button
    $btnAiSaveSettings.Text = "AIキャラ判定設定を保存"
    $btnAiSaveSettings.Location = New-Object System.Drawing.Point(588, 152)
    $btnAiSaveSettings.Size = New-Object System.Drawing.Size(200, 34)
    $btnAiSaveSettings.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnAiSaveSettings.ForeColor = [System.Drawing.Color]::White
    $btnAiSaveSettings.FlatStyle = "Flat"
    $btnAiSaveSettings.Font = New-Object System.Drawing.Font("Meiryo UI", 9, [System.Drawing.FontStyle]::Bold)
    $grpAiOpts.Controls.Add($btnAiSaveSettings)

    $refreshAiKeyStatus = {
        $hasKey = if (Get-Command Test-GeminiApiKeyStored -ErrorAction SilentlyContinue) {
            Test-GeminiApiKeyStored -RootDir $RootDir -Config $cfg
        } else { $false }
        if ($hasKey) {
            $lblAiKeyStatus.Text = "状態: 登録済み（Windows DPAPI で暗号化保護されています）"
            $lblAiKeyStatus.ForeColor = [System.Drawing.Color]::FromArgb(4, 120, 87)
        } else {
            $lblAiKeyStatus.Text = "状態: 未登録（Gemini APIキーを入力して「暗号化して保存」を押してください）"
            $lblAiKeyStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 83, 9)
        }
    }
    & $refreshAiKeyStatus

    $btnAiSaveKey.Add_Click({
        $k = $txtAiKeyInput.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($k)) {
            [System.Windows.Forms.MessageBox]::Show($dlg, "保存する Gemini APIキーを入力してください。", "入力確認", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        try {
            [void](Save-GeminiApiKeyProtected -PlainApiKey $k -RootDir $RootDir -Config $cfg)
            $txtAiKeyInput.Text = ""
            & $refreshAiKeyStatus
            [System.Windows.Forms.MessageBox]::Show($dlg, "Gemini APIキーを Windows DPAPI で暗号化保存しました。`n入力欄はセキュリティのためクリアされました。", "保存完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show($dlg, "APIキーの暗号化保存に失敗しました:`n$($_.Exception.Message)", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $btnAiDeleteKey.Add_Click({
        if (-not (Test-GeminiApiKeyStored -RootDir $RootDir -Config $cfg)) {
            [System.Windows.Forms.MessageBox]::Show($dlg, "保存されているAPIキーはありません。", "確認", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        $ansDel = [System.Windows.Forms.MessageBox]::Show($dlg, "暗号化保存されている Gemini APIキーを削除しますか？", "削除確認", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ansDel -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        [void](Remove-GeminiApiKeyProtected -RootDir $RootDir -Config $cfg)
        & $refreshAiKeyStatus
        [System.Windows.Forms.MessageBox]::Show($dlg, "保存済みAPIキーを削除しました。", "削除完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    })

    $btnAiSaveSettings.Add_Click({
        try {
            $fmtCode = switch ($cmbAiOutFmt.SelectedIndex) {
                1 { "CharOnly" }
                2 { "SeriesSlashChar" }
                default { "CharWithSeries" }
            }
            $maskCode = if ($cmbAiMaskStyle.SelectedIndex -eq 1) { "Mosaic" } else { "Black" }
            $maxEdgeVal = 640
            [void][int]::TryParse([string]$cmbAiMaxPx.SelectedItem, [ref]$maxEdgeVal)
            $payload = [ordered]@{
                Version             = 1
                ModelName           = if (-not [string]::IsNullOrWhiteSpace($cmbAiModel.Text.Trim())) { $cmbAiModel.Text.Trim() } else { "gemini-2.5-flash" }
                PaidTierConfirmed   = [bool]$chkAiPaidTier.Checked
                MaxImageEdgePx      = $maxEdgeVal
                JpegQuality         = 75
                DefaultMaskStyle    = $maskCode
                DefaultOutputFormat = $fmtCode
            }
            $savedP = Save-GeminiCharacterSettings -Settings $payload -RootDir $RootDir -Config $cfg
            [System.Windows.Forms.MessageBox]::Show($dlg, "AIキャラ判定設定を保存しました:`n$savedP", "保存完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show($dlg, "AI設定の保存に失敗しました:`n$($_.Exception.Message)", "保存エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $btnAiTestConn.Add_Click({
        try {
            $apiKey = $txtAiKeyInput.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($apiKey)) {
                $apiKey = Get-GeminiApiKeyDecrypted -RootDir $RootDir -Config $cfg
            }
            if ([string]::IsNullOrWhiteSpace($apiKey)) {
                [System.Windows.Forms.MessageBox]::Show($dlg, "テストするAPIキーが登録・入力されていません。", "確認", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                return
            }
            $mdl = if (-not [string]::IsNullOrWhiteSpace($cmbAiModel.Text.Trim())) { $cmbAiModel.Text.Trim() } else { "gemini-2.5-flash" }
            $btnAiTestConn.Enabled = $false
            $btnAiTestConn.Text = "接続確認中..."
            [System.Windows.Forms.Application]::DoEvents()
            $res = Test-GeminiApiConnection -ApiKey $apiKey -ModelName $mdl
            [System.Windows.Forms.MessageBox]::Show($dlg, "接続に成功しました！`n`nモデルID: $($res.ModelName)`n表示名: $($res.DisplayName)", "接続テスト成功", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show($dlg, "接続テストに失敗しました:`n`n$($_.Exception.Message)", "接続テスト失敗", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        } finally {
            $btnAiTestConn.Enabled = $true
            $btnAiTestConn.Text = "接続テスト（無料・トークン消費なし）"
        }
    })

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
            3 {
                return $msgTplPath
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
    if ($InitialTabIndex -ge 0 -and $InitialTabIndex -lt $tabs.TabPages.Count) {
        $tabs.SelectedIndex = $InitialTabIndex
    }

    if ($null -ne $OwnerForm) {
        [void]$dlg.ShowDialog($OwnerForm)
    } else {
        [void]$dlg.ShowDialog()
    }
    $dlg.Dispose()
    return $script:SettingsSaved
}

if ($MyInvocation.InvocationName -ne '.') {
    [void](Show-PhotoToolsSettingsDialog -RootDir $RootDir -InitialTabIndex $InitialTabIndex)
}
