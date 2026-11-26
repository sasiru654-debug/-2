#requires -Version 5.1
# ==============================================================================
# MessageComposerDialog.ps1 - 送付メッセージ作成・MEGA自動取得・送付済連動GUI (UTF-8 BOM / CRLF)
# ==============================================================================
param(
    [string[]]$FolderPaths = @(),
    [ValidateSet("Single", "Combined")]
    [string]$Mode = "Single",
    [string]$PrimaryFolder = "",
    [string[]]$DateSearchRoots = @(),
    [ValidateSet("", "GigaFile", "MEGA")]
    [string]$PreferredLinkType = "",
    [string]$OverrideGigaUrl = "",
    [string]$OverrideDlPassword = "",
    [string]$OverrideExpiryDate = "",
    [int]$SelectedModelIndex = 0,
    [string]$SelectedModelX = "",
    [string]$SelectedModelName = "",
    [string]$RootDir = "",
    [hashtable]$Config = @{}
)

Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-MessageComposerDialog {
    param(
        [string[]]$FolderPaths = @(),
        [ValidateSet("Single", "Combined")]
        [string]$Mode = "Single",
        [string]$PrimaryFolder = "",
        [string[]]$DateSearchRoots = @(),
        [ValidateSet("", "GigaFile", "MEGA")]
        [string]$PreferredLinkType = "",
        [string]$OverrideGigaUrl = "",
        [string]$OverrideDlPassword = "",
        [string]$OverrideExpiryDate = "",
        [int]$SelectedModelIndex = 0,
        [string]$SelectedModelX = "",
        [string]$SelectedModelName = "",
        [string]$RootDir = "",
        [hashtable]$Config = @{},
        [System.Windows.Forms.IWin32Window]$OwnerForm = $null
    )

    if ([string]::IsNullOrWhiteSpace($RootDir)) {
        $scriptDir = $PSScriptRoot
        if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = "D:\PhotoTools\editor" }
        $RootDir = Split-Path -Parent $scriptDir
        if (-not (Test-Path -LiteralPath (Join-Path $RootDir "settings.ini"))) {
            if (Test-Path -LiteralPath "D:\PhotoTools\settings.ini") { $RootDir = "D:\PhotoTools" }
        }
    }

    $commonDir = Join-Path $RootDir "common"
    foreach ($helper in @("LogHelper.ps1", "ConfigHelper.ps1", "SceneHelper.ps1", "XHelper.ps1", "PhotoInfoHelper.ps1", "PhotoEditorLogic.ps1", "ExcelHelper.ps1", "MegaHelper.ps1", "MessageTemplateHelper.ps1")) {
        $hp = Join-Path $commonDir $helper
        if (Test-Path -LiteralPath $hp) {
            . $hp
        }
    }

    $effConfig = if ($null -ne $Config -and $Config.Count -gt 0) {
        $Config
    } elseif (Get-Command Get-PhotoToolsConfig -ErrorAction SilentlyContinue) {
        Get-PhotoToolsConfig -RootDir $RootDir
    } else {
        @{ RootDir = $RootDir; DataDir = (Join-Path $RootDir "data") }
    }

    $tplFilePath = Get-MessageTemplateFilePath -RootDir $RootDir -Config $effConfig
    $script:MsgStore = Get-MessageTemplateStore -FilePath $tplFilePath -RootDir $RootDir -Config $effConfig
    $script:ComposerResult = [ordered]@{
        Copied      = $false
        MarkedSent  = $false
        UpdatedMega = $false
        MessageText = ""
    }

    # --- ヘルパー：フォルダ情報読込（ペアフォルダ同期・scene.txt解決含む） ---
    $loadFolderRecord = {
        param([string]$DirPath)
        if ([string]::IsNullOrWhiteSpace($DirPath)) { return $null }
        $normDir = $DirPath.Trim().Trim('"').TrimEnd('\')
        if (-not (Test-Path -LiteralPath $normDir -PathType Container)) { return $null }

        $paired = if (Get-Command Resolve-PairedPhotoFolders -ErrorAction SilentlyContinue) {
            Resolve-PairedPhotoFolders -Folder $normDir -EffectiveConfig $effConfig
        } else {
            @{ Target = $normDir; ImportFolder = ""; DevFolder = $normDir; DateStr = ""; FolderName = (Split-Path -Leaf $normDir); RelPath = "" }
        }

        $infoFile = ""
        foreach ($candDir in @($paired.DevFolder, $paired.Target, $paired.ImportFolder)) {
            if (-not [string]::IsNullOrWhiteSpace($candDir) -and (Test-Path -LiteralPath (Join-Path $candDir "写真情報.txt"))) {
                $infoFile = Join-Path $candDir "写真情報.txt"
                break
            }
        }

        $info = if (-not [string]::IsNullOrWhiteSpace($infoFile)) {
            Read-PhotoInfoTxt -FolderPath (Split-Path -Parent $infoFile) -FilePath $infoFile -Config $effConfig
        } else {
            Read-PhotoInfoTxt -FolderPath $normDir -Config $effConfig
        }

        if (Get-Command Resolve-SceneFromFolders -ErrorAction SilentlyContinue) {
            $sc = Resolve-SceneFromFolders -PairedObj $paired
            if ($null -ne $sc -and -not [string]::IsNullOrWhiteSpace([string]$sc.SceneName)) {
                $info.EventName = [string]$sc.SceneName
                if (-not [string]::IsNullOrWhiteSpace([string]$sc.Category)) {
                    $info.Category = [string]$sc.Category
                }
            }
        }
        if ([string]::IsNullOrWhiteSpace([string]$info.DateStr) -and -not [string]::IsNullOrWhiteSpace([string]$paired.DateStr)) {
            $info.DateStr = [string]$paired.DateStr
            $info.ShootDate = [string]$paired.DateStr
        }

        return [ordered]@{
            FolderPath     = $normDir
            FolderName     = [string]$paired.FolderName
            Paired         = $paired
            Info           = $info
            Category       = [string]$info.Category
            DateStr        = [string]$info.DateStr
            EventName      = [string]$info.EventName
            MegaLink       = [string]$info.MegaLink
            GigaFileLink   = [string]$info.GigaFileLink
            DlPassword     = [string]$info.DlPassword
            GigaFileExpiry = [string]$info.GigaFileExpiry
            SentStatus     = [string]$info.SentStatus
            IsSent         = [bool]$info.IsSent
            Persons        = @($info.Persons)
            CostumeOrChar  = [string]$info.CostumeOrChar
            Notes          = [string]$info.Notes
            Checked        = $true
        }
    }

    # --- 初期フォルダ群の解決 ---
    $seedFolders = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($PrimaryFolder)) {
        $pf = $PrimaryFolder.Trim().Trim('"').TrimEnd('\')
        if (Test-Path -LiteralPath $pf -PathType Container) { [void]$seedFolders.Add($pf) }
    }
    foreach ($fp in @($FolderPaths)) {
        if ([string]::IsNullOrWhiteSpace($fp)) { continue }
        $nfp = $fp.Trim().Trim('"').TrimEnd('\')
        if ((Test-Path -LiteralPath $nfp -PathType Container) -and -not $seedFolders.Contains($nfp)) {
            [void]$seedFolders.Add($nfp)
        }
    }

    $primaryRec = if ($seedFolders.Count -gt 0) { & $loadFolderRecord $seedFolders[0] } else { $null }

    # --- 送信先モデル候補の収集 ---
    $modelCandidates = New-Object System.Collections.ArrayList
    $seenModelKeys = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    $addCandidate = {
        param([string]$Name, [string]$XAcc, [string]$XUrl)
        $cleanN = if ($null -eq $Name) { "" } else { $Name.Trim() }
        $normX = ConvertTo-NormXForMatch -RawX $XAcc
        $dispX = if (-not [string]::IsNullOrWhiteSpace($normX)) { $normX } else { "" }
        $dispUrl = if (-not [string]::IsNullOrWhiteSpace($XUrl)) { $XUrl.Trim() } elseif (-not [string]::IsNullOrWhiteSpace($dispX)) { "https://x.com/" + $dispX.TrimStart('@') } else { "" }
        if ([string]::IsNullOrWhiteSpace($cleanN) -and [string]::IsNullOrWhiteSpace($dispX)) { return }
        $key = if (-not [string]::IsNullOrWhiteSpace($dispX)) { "X:" + $dispX } else { "N:" + $cleanN.ToLowerInvariant() }
        if ($seenModelKeys.Add($key)) {
            [void]$modelCandidates.Add([ordered]@{
                Name     = $cleanN
                XAccount = $dispX
                XUrl     = $dispUrl
                Display  = if (-not [string]::IsNullOrWhiteSpace($cleanN) -and -not [string]::IsNullOrWhiteSpace($dispX)) { "$cleanN ($dispX)" }
                           elseif (-not [string]::IsNullOrWhiteSpace($cleanN)) { $cleanN }
                           else { $dispX }
            })
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($SelectedModelName) -or -not [string]::IsNullOrWhiteSpace($SelectedModelX)) {
        & $addCandidate $SelectedModelName $SelectedModelX ""
    }

    $seedRecords = New-Object System.Collections.ArrayList
    foreach ($sf in $seedFolders) {
        $rec = & $loadFolderRecord $sf
        if ($null -ne $rec) {
            if (-not [string]::IsNullOrWhiteSpace($OverrideGigaUrl) -and $seedRecords.Count -eq 0) {
                $rec.GigaFileLink = $OverrideGigaUrl.Trim()
            }
            if (-not [string]::IsNullOrWhiteSpace($OverrideDlPassword)) {
                $rec.DlPassword = $OverrideDlPassword.Trim()
            }
            if (-not [string]::IsNullOrWhiteSpace($OverrideExpiryDate)) {
                $rec.GigaFileExpiry = Format-GigaFileExpiryText -RawExpiry $OverrideExpiryDate
            }
            [void]$seedRecords.Add($rec)
            foreach ($p in @($rec.Persons)) {
                if ($null -eq $p) { continue }
                & $addCandidate (ConvertTo-SafeStringProp $p "Name") (ConvertTo-SafeStringProp $p "XAccount") (ConvertTo-SafeStringProp $p "XUrl")
            }
        }
    }

    if ($modelCandidates.Count -eq 0) {
        [void]$modelCandidates.Add([ordered]@{ Name = ""; XAccount = ""; XUrl = ""; Display = "(モデル未登録)" })
    }

    # --- 同日フォルダ一覧を探索して同一Xアカウントのフォルダを収集（まとめモード用） ---
    $collectFoldersForRecipient = {
        param([hashtable]$Recipient)
        $results = New-Object System.Collections.ArrayList
        $seenRelKeys = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

        if ($Mode -eq "Single" -or (@($DateSearchRoots).Count -eq 0 -and $seedRecords.Count -gt 1)) {
            foreach ($sr in $seedRecords) {
                [void]$results.Add($sr)
            }
            return ,(@($results.ToArray()))
        }

        $targetXNorm = ConvertTo-NormXForMatch -RawX ([string]$Recipient.XAccount)
        $targetName  = ([string]$Recipient.Name).Trim()

        $rootsToScan = New-Object System.Collections.Generic.List[string]
        foreach ($dr in @($DateSearchRoots)) {
            if (-not [string]::IsNullOrWhiteSpace($dr) -and (Test-Path -LiteralPath $dr -PathType Container)) {
                $ndr = $dr.TrimEnd('\')
                if (-not $rootsToScan.Contains($ndr)) { [void]$rootsToScan.Add($ndr) }
            }
        }
        if ($rootsToScan.Count -eq 0 -and $null -ne $primaryRec) {
            $parentCand = Split-Path -Parent $primaryRec.FolderPath
            if (-not [string]::IsNullOrWhiteSpace($parentCand) -and (Test-Path -LiteralPath $parentCand -PathType Container)) {
                [void]$rootsToScan.Add($parentCand)
            }
        }

        # まずプライマリフォルダを最優先登録
        foreach ($sr in $seedRecords) {
            $relKey = if (-not [string]::IsNullOrWhiteSpace([string]$sr.Paired.RelPath)) { [string]$sr.Paired.RelPath } else { [string]$sr.FolderPath }
            if ($seenRelKeys.Add($relKey)) {
                [void]$results.Add($sr)
            }
        }

        foreach ($rootDirScan in $rootsToScan) {
            $infoFiles = @()
            try {
                $infoFiles = @([System.IO.Directory]::GetFiles($rootDirScan, "写真情報.txt", [System.IO.SearchOption]::AllDirectories))
            } catch {
                $infoFiles = @(Get-ChildItem -LiteralPath $rootDirScan -Filter "写真情報.txt" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
            }
            foreach ($infFile in $infoFiles) {
                $candDir = Split-Path -Parent $infFile
                $candRec = & $loadFolderRecord $candDir
                if ($null -eq $candRec) { continue }
                $relKey = if (-not [string]::IsNullOrWhiteSpace([string]$candRec.Paired.RelPath)) { [string]$candRec.Paired.RelPath } else { [string]$candRec.FolderPath }
                if ($seenRelKeys.Contains($relKey)) { continue }

                $isMatch = $false
                foreach ($p in @($candRec.Persons)) {
                    if ($null -eq $p) { continue }
                    $px = ConvertTo-NormXForMatch -RawX (ConvertTo-SafeStringProp $p "XAccount")
                    $pn = (ConvertTo-SafeStringProp $p "Name").Trim()
                    if (-not [string]::IsNullOrWhiteSpace($targetXNorm) -and -not [string]::IsNullOrWhiteSpace($px) -and ($px -eq $targetXNorm)) {
                        $isMatch = $true
                        break
                    }
                    if ([string]::IsNullOrWhiteSpace($targetXNorm) -and -not [string]::IsNullOrWhiteSpace($targetName) -and ($pn -ieq $targetName)) {
                        $isMatch = $true
                        break
                    }
                }
                if ($isMatch) {
                    [void]$seenRelKeys.Add($relKey)
                    [void]$results.Add($candRec)
                }
            }
        }

        return ,(@($results.ToArray()))
    }

    # --- フォーム構築 ---
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "送付メッセージ作成 - PhotoTools"
    $dlg.Size = New-Object System.Drawing.Size(840, 760)
    $dlg.MinimumSize = New-Object System.Drawing.Size(760, 680)
    $dlg.StartPosition = if ($null -ne $OwnerForm) { "CenterParent" } else { "CenterScreen" }
    $dlg.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5)
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 250)

    # ヘッダーバー
    $pnlHeader = New-Object System.Windows.Forms.Panel
    $pnlHeader.Dock = "Top"
    $pnlHeader.Height = 52
    $pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(20, 45, 60)
    $dlg.Controls.Add($pnlHeader)

    $lblTitle = New-Object System.Windows.Forms.Label
    $modeLabel = if ($Mode -eq "Combined") { "まとめ送付モード（同日・同一Xアカウント自動抽出）" } else { "単独送付モード" }
    $lblTitle.Text = "送付メッセージ作成  |  $modeLabel"
    $lblTitle.Font = New-Object System.Drawing.Font("Yu Gothic UI", 11, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Location = New-Object System.Drawing.Point(16, 14)
    $lblTitle.AutoSize = $true
    $pnlHeader.Controls.Add($lblTitle)

    $btnOpenTplSettings = New-Object System.Windows.Forms.Button
    $btnOpenTplSettings.Text = "定型文・MEGAコメント設定"
    $btnOpenTplSettings.Size = New-Object System.Drawing.Size(185, 30)
    $btnOpenTplSettings.Location = New-Object System.Drawing.Point(626, 11)
    $btnOpenTplSettings.Anchor = "Top, Right"
    $btnOpenTplSettings.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
    $btnOpenTplSettings.FlatStyle = "Flat"
    $pnlHeader.Controls.Add($btnOpenTplSettings)

    # 下部フッター
    $pnlFooter = New-Object System.Windows.Forms.Panel
    $pnlFooter.Dock = "Bottom"
    $pnlFooter.Height = 56
    $pnlFooter.BackColor = [System.Drawing.Color]::FromArgb(236, 240, 245)
    $dlg.Controls.Add($pnlFooter)

    $chkMarkSent = New-Object System.Windows.Forms.CheckBox
    $chkMarkSent.Text = "コピー後にステータスを「送付済み」へ更新する（写真情報.txt・Excel台帳）"
    $chkMarkSent.Location = New-Object System.Drawing.Point(16, 18)
    $chkMarkSent.AutoSize = $true
    $chkMarkSent.Checked = $true
    $chkMarkSent.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9, [System.Drawing.FontStyle]::Bold)
    $pnlFooter.Controls.Add($chkMarkSent)

    $btnCopyMsg = New-Object System.Windows.Forms.Button
    $btnCopyMsg.Text = "クリップボードにコピー"
    $btnCopyMsg.Location = New-Object System.Drawing.Point(536, 11)
    $btnCopyMsg.Size = New-Object System.Drawing.Size(180, 34)
    $btnCopyMsg.Anchor = "Top, Right"
    $btnCopyMsg.BackColor = [System.Drawing.Color]::FromArgb(16, 124, 65)
    $btnCopyMsg.ForeColor = [System.Drawing.Color]::White
    $btnCopyMsg.FlatStyle = "Flat"
    $btnCopyMsg.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $pnlFooter.Controls.Add($btnCopyMsg)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "閉じる"
    $btnClose.Location = New-Object System.Drawing.Point(724, 11)
    $btnClose.Size = New-Object System.Drawing.Size(88, 34)
    $btnClose.Anchor = "Top, Right"
    $btnClose.BackColor = [System.Drawing.Color]::White
    $pnlFooter.Controls.Add($btnClose)

    # メインコンテナ
    $pnlMain = New-Object System.Windows.Forms.Panel
    $pnlMain.Dock = "Fill"
    $pnlMain.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 10)
    $dlg.Controls.Add($pnlMain)
    $pnlMain.BringToFront()

    # 1. 送付条件・テンプレート選択グループ
    $grpCond = New-Object System.Windows.Forms.GroupBox
    $grpCond.Text = "1. 送信先・テンプレート・リンク種別"
    $grpCond.Location = New-Object System.Drawing.Point(14, 8)
    $grpCond.Size = New-Object System.Drawing.Size(796, 152)
    $grpCond.Anchor = "Top, Left, Right"
    $grpCond.BackColor = [System.Drawing.Color]::White
    $pnlMain.Controls.Add($grpCond)

    $lblRec = New-Object System.Windows.Forms.Label
    $lblRec.Text = "送信先モデル:"
    $lblRec.Location = New-Object System.Drawing.Point(14, 28)
    $lblRec.Size = New-Object System.Drawing.Size(96, 22)
    $grpCond.Controls.Add($lblRec)

    $cmbRecipient = New-Object System.Windows.Forms.ComboBox
    $cmbRecipient.Location = New-Object System.Drawing.Point(114, 24)
    $cmbRecipient.Size = New-Object System.Drawing.Size(268, 25)
    $cmbRecipient.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    foreach ($mc in $modelCandidates) {
        [void]$cmbRecipient.Items.Add($mc.Display)
    }
    $initRecIdx = if ($SelectedModelIndex -ge 0 -and $SelectedModelIndex -lt $cmbRecipient.Items.Count) { $SelectedModelIndex } else { 0 }
    $cmbRecipient.SelectedIndex = $initRecIdx
    $grpCond.Controls.Add($cmbRecipient)

    $lblTpl = New-Object System.Windows.Forms.Label
    $lblTpl.Text = "定型文テンプレート:"
    $lblTpl.Location = New-Object System.Drawing.Point(398, 28)
    $lblTpl.Size = New-Object System.Drawing.Size(124, 22)
    $grpCond.Controls.Add($lblTpl)

    $cmbTemplate = New-Object System.Windows.Forms.ComboBox
    $cmbTemplate.Location = New-Object System.Drawing.Point(526, 24)
    $cmbTemplate.Size = New-Object System.Drawing.Size(254, 25)
    $cmbTemplate.Anchor = "Top, Left, Right"
    $cmbTemplate.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $grpCond.Controls.Add($cmbTemplate)

    $lblLinkType = New-Object System.Windows.Forms.Label
    $lblLinkType.Text = "記載するリンク:"
    $lblLinkType.Location = New-Object System.Drawing.Point(14, 64)
    $lblLinkType.Size = New-Object System.Drawing.Size(96, 22)
    $grpCond.Controls.Add($lblLinkType)

    $rdoGiga = New-Object System.Windows.Forms.RadioButton
    $rdoGiga.Text = "ギガファイル便"
    $rdoGiga.Location = New-Object System.Drawing.Point(114, 62)
    $rdoGiga.Size = New-Object System.Drawing.Size(120, 24)
    $grpCond.Controls.Add($rdoGiga)

    $rdoMega = New-Object System.Windows.Forms.RadioButton
    $rdoMega.Text = "MEGA"
    $rdoMega.Location = New-Object System.Drawing.Point(242, 62)
    $rdoMega.Size = New-Object System.Drawing.Size(80, 24)
    $grpCond.Controls.Add($rdoMega)

    $lblMegaCmt = New-Object System.Windows.Forms.Label
    $lblMegaCmt.Text = "MEGAコメント:"
    $lblMegaCmt.Location = New-Object System.Drawing.Point(398, 64)
    $lblMegaCmt.Size = New-Object System.Drawing.Size(124, 22)
    $grpCond.Controls.Add($lblMegaCmt)

    $cmbMegaComment = New-Object System.Windows.Forms.ComboBox
    $cmbMegaComment.Location = New-Object System.Drawing.Point(526, 60)
    $cmbMegaComment.Size = New-Object System.Drawing.Size(254, 25)
    $cmbMegaComment.Anchor = "Top, Left, Right"
    $cmbMegaComment.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $grpCond.Controls.Add($cmbMegaComment)

    $lblDlPw = New-Object System.Windows.Forms.Label
    $lblDlPw.Text = "DLパスワード:"
    $lblDlPw.Location = New-Object System.Drawing.Point(14, 102)
    $lblDlPw.Size = New-Object System.Drawing.Size(96, 22)
    $grpCond.Controls.Add($lblDlPw)

    $txtDlPw = New-Object System.Windows.Forms.TextBox
    $txtDlPw.Location = New-Object System.Drawing.Point(114, 98)
    $txtDlPw.Size = New-Object System.Drawing.Size(175, 25)
    $grpCond.Controls.Add($txtDlPw)

    $lblExpiry = New-Object System.Windows.Forms.Label
    $lblExpiry.Text = "保持期限 (例: 2026/12/25まで):"
    $lblExpiry.Location = New-Object System.Drawing.Point(306, 102)
    $lblExpiry.Size = New-Object System.Drawing.Size(214, 22)
    $grpCond.Controls.Add($lblExpiry)

    $txtExpiry = New-Object System.Windows.Forms.TextBox
    $txtExpiry.Location = New-Object System.Drawing.Point(526, 98)
    $txtExpiry.Size = New-Object System.Drawing.Size(254, 25)
    $txtExpiry.Anchor = "Top, Left, Right"
    $grpCond.Controls.Add($txtExpiry)

    $lblCondHint = New-Object System.Windows.Forms.Label
    $lblCondHint.Text = "※DLパスワード・保持期限はギガファイル便選択時のみ出力されます（空欄の項目は自動省略）。"
    $lblCondHint.Location = New-Object System.Drawing.Point(114, 127)
    $lblCondHint.Size = New-Object System.Drawing.Size(665, 18)
    $lblCondHint.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
    $lblCondHint.Font = New-Object System.Drawing.Font("Yu Gothic UI", 8.2)
    $grpCond.Controls.Add($lblCondHint)

    # 2. 対象フォルダ一覧
    $grpFolders = New-Object System.Windows.Forms.GroupBox
    $grpFolders.Text = "2. 対象フォルダ一覧（チェックを付けたフォルダがメッセージに含まれます）"
    $grpFolders.Location = New-Object System.Drawing.Point(14, 166)
    $grpFolders.Size = New-Object System.Drawing.Size(796, 152)
    $grpFolders.Anchor = "Top, Left, Right"
    $grpFolders.BackColor = [System.Drawing.Color]::White
    $pnlMain.Controls.Add($grpFolders)

    $lvFolders = New-Object System.Windows.Forms.ListView
    $lvFolders.Location = New-Object System.Drawing.Point(12, 22)
    $lvFolders.Size = New-Object System.Drawing.Size(772, 118)
    $lvFolders.Anchor = "Top, Bottom, Left, Right"
    $lvFolders.View = [System.Windows.Forms.View]::Details
    $lvFolders.CheckBoxes = $true
    $lvFolders.FullRowSelect = $true
    $lvFolders.GridLines = $true
    [void]$lvFolders.Columns.Add("フォルダ名", 160)
    [void]$lvFolders.Columns.Add("区分 / 人数", 115)
    [void]$lvFolders.Columns.Add("衣装・キャラ", 160)
    [void]$lvFolders.Columns.Add("ギガファイル便", 105)
    [void]$lvFolders.Columns.Add("MEGA", 105)
    [void]$lvFolders.Columns.Add("送付状況", 95)
    $grpFolders.Controls.Add($lvFolders)

    # 3. メッセージ作成ボタン行
    $btnCreateMsg = New-Object System.Windows.Forms.Button
    $btnCreateMsg.Text = "メッセージを作成"
    $btnCreateMsg.Location = New-Object System.Drawing.Point(14, 326)
    $btnCreateMsg.Size = New-Object System.Drawing.Size(210, 36)
    $btnCreateMsg.BackColor = [System.Drawing.Color]::FromArgb(26, 115, 232)
    $btnCreateMsg.ForeColor = [System.Drawing.Color]::White
    $btnCreateMsg.FlatStyle = "Flat"
    $btnCreateMsg.Font = New-Object System.Drawing.Font("Yu Gothic UI", 10, [System.Drawing.FontStyle]::Bold)
    $pnlMain.Controls.Add($btnCreateMsg)

    $lblStatusMsg = New-Object System.Windows.Forms.Label
    $lblStatusMsg.Text = "条件を確認し、「メッセージを作成」ボタンを押してください。"
    $lblStatusMsg.Location = New-Object System.Drawing.Point(236, 334)
    $lblStatusMsg.Size = New-Object System.Drawing.Size(574, 22)
    $lblStatusMsg.Anchor = "Top, Left, Right"
    $lblStatusMsg.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $pnlMain.Controls.Add($lblStatusMsg)

    # 4. 生成されたメッセージ本文
    $grpBody = New-Object System.Windows.Forms.GroupBox
    $grpBody.Text = "3. 作成メッセージ（コピー前に直接編集することも可能です）"
    $grpBody.Location = New-Object System.Drawing.Point(14, 368)
    $grpBody.Size = New-Object System.Drawing.Size(796, 232)
    $grpBody.Anchor = "Top, Bottom, Left, Right"
    $grpBody.BackColor = [System.Drawing.Color]::White
    $pnlMain.Controls.Add($grpBody)

    $txtMessage = New-Object System.Windows.Forms.TextBox
    $txtMessage.Location = New-Object System.Drawing.Point(12, 22)
    $txtMessage.Size = New-Object System.Drawing.Size(772, 198)
    $txtMessage.Anchor = "Top, Bottom, Left, Right"
    $txtMessage.Multiline = $true
    $txtMessage.ScrollBars = "Vertical"
    $txtMessage.Font = New-Object System.Drawing.Font("Yu Gothic UI", 10)
    $txtMessage.Text = ""
    $grpBody.Controls.Add($txtMessage)

    # --- UI 状態管理 ---
    $script:ActiveFolderRecords = @()
    $script:TemplateItems = @()
    $script:MegaPresetItems = @()

    $updateLinkTypeControlState = {
        $isMega = $rdoMega.Checked
        $cmbMegaComment.Enabled = $isMega
        $lblMegaCmt.Enabled = $isMega
        $txtDlPw.Enabled = (-not $isMega)
        $txtExpiry.Enabled = (-not $isMega)
        $lblDlPw.Enabled = (-not $isMega)
        $lblExpiry.Enabled = (-not $isMega)
    }

    $populateTemplatesAndMegaPresets = {
        param([string]$TargetCategory = "")
        $script:MsgStore = Get-MessageTemplateStore -FilePath $tplFilePath -RootDir $RootDir -Config $effConfig

        $cmbTemplate.Items.Clear()
        $script:TemplateItems = @($script:MsgStore.Templates)
        if (@($script:TemplateItems).Count -eq 0) {
            [void]$cmbTemplate.Items.Add("（テンプレート未登録：右上の「定型文設定」から追加）")
            $cmbTemplate.SelectedIndex = 0
        } else {
            $defaultTpl = Select-DefaultTemplateForCategory -Store $script:MsgStore -Category $TargetCategory
            $selIdx = 0
            for ($i = 0; $i -lt $script:TemplateItems.Count; $i++) {
                $t = $script:TemplateItems[$i]
                $tCat = ConvertTo-SafeStringProp $t "Category" "共通"
                $tNm  = ConvertTo-SafeStringProp $t "Name" ""
                $tDef = if (ConvertTo-SafeBoolProp $t "IsDefault") { " ★既定" } else { "" }
                [void]$cmbTemplate.Items.Add("[$tCat] $tNm$tDef")
                if ($null -ne $defaultTpl -and (ConvertTo-SafeStringProp $t "Id") -eq (ConvertTo-SafeStringProp $defaultTpl "Id")) {
                    $selIdx = $i
                }
            }
            $cmbTemplate.SelectedIndex = $selIdx
        }

        $cmbMegaComment.Items.Clear()
        $script:MegaPresetItems = @($script:MsgStore.MegaCommentPresets)
        $defMegaId = [string]$script:MsgStore.DefaultMegaCommentId
        $selMegaIdx = 0
        for ($i = 0; $i -lt $script:MegaPresetItems.Count; $i++) {
            $mp = $script:MegaPresetItems[$i]
            [void]$cmbMegaComment.Items.Add((ConvertTo-SafeStringProp $mp "Name"))
            if ((ConvertTo-SafeStringProp $mp "Id") -eq $defMegaId) {
                $selMegaIdx = $i
            }
        }
        if ($cmbMegaComment.Items.Count -gt 0) {
            $cmbMegaComment.SelectedIndex = $selMegaIdx
        }
    }

    $refreshFolderListView = {
        $lvFolders.BeginUpdate()
        try {
            $lvFolders.Items.Clear()
            foreach ($rec in @($script:ActiveFolderRecords)) {
                $validP = 0
                $cosList = New-Object System.Collections.Generic.List[string]
                foreach ($p in @($rec.Persons)) {
                    if ($null -eq $p) { continue }
                    $pn = ConvertTo-SafeStringProp $p "Name"
                    $px = ConvertTo-SafeStringProp $p "XAccount"
                    $pc = ConvertTo-SafeStringProp $p "CostumeOrChar"
                    if (-not [string]::IsNullOrWhiteSpace($pn) -or -not [string]::IsNullOrWhiteSpace($px) -or -not [string]::IsNullOrWhiteSpace($pc)) {
                        $validP++
                    }
                    if (-not [string]::IsNullOrWhiteSpace($pc) -and -not $cosList.Contains($pc)) {
                        [void]$cosList.Add($pc)
                    }
                }
                $cntLabel = if ($validP -ge 2) { "$($rec.Category) / 複数(${validP}名)" } else { "$($rec.Category) / 1名" }
                $gigaState = if (-not [string]::IsNullOrWhiteSpace($rec.GigaFileLink)) { "あり" } else { "なし" }
                $megaState = if (-not [string]::IsNullOrWhiteSpace($rec.MegaLink)) { "取得済" } else { "未取得" }
                $sentState = if ($rec.IsSent -or $rec.SentStatus -eq "送付済み" -or $rec.SentStatus -eq "送付済") { "送付済み" } else { "未送付" }

                $lvi = New-Object System.Windows.Forms.ListViewItem([string]$rec.FolderName)
                $lvi.Checked = [bool]$rec.Checked
                [void]$lvi.SubItems.Add($cntLabel)
                [void]$lvi.SubItems.Add(($cosList -join " / "))
                [void]$lvi.SubItems.Add($gigaState)
                [void]$lvi.SubItems.Add($megaState)
                [void]$lvi.SubItems.Add($sentState)
                $lvi.Tag = $rec
                if ($megaState -eq "未取得") {
                    $lvi.SubItems[4].ForeColor = [System.Drawing.Color]::DarkOrange
                }
                [void]$lvFolders.Items.Add($lvi)
            }
        } finally {
            $lvFolders.EndUpdate()
        }
    }

    $reloadForCurrentRecipient = {
        $recIdx = $cmbRecipient.SelectedIndex
        if ($recIdx -lt 0 -or $recIdx -ge $modelCandidates.Count) { return }
        $curRec = $modelCandidates[$recIdx]
        $script:ActiveFolderRecords = & $collectFoldersForRecipient $curRec
        & $refreshFolderListView

        $firstCat = if (@($script:ActiveFolderRecords).Count -gt 0) { [string]$script:ActiveFolderRecords[0].Category } else { "" }
        & $populateTemplatesAndMegaPresets $firstCat

        # DLパスワード・保持期限の初期補完
        $foundPw = $OverrideDlPassword
        $foundExp = if (-not [string]::IsNullOrWhiteSpace($OverrideExpiryDate)) { Format-GigaFileExpiryText -RawExpiry $OverrideExpiryDate } else { "" }
        $hasAnyGiga = $false
        foreach ($r in @($script:ActiveFolderRecords)) {
            if (-not [string]::IsNullOrWhiteSpace($r.GigaFileLink)) { $hasAnyGiga = $true }
            if ([string]::IsNullOrWhiteSpace($foundPw) -and -not [string]::IsNullOrWhiteSpace($r.DlPassword)) { $foundPw = $r.DlPassword }
            if ([string]::IsNullOrWhiteSpace($foundExp) -and -not [string]::IsNullOrWhiteSpace($r.GigaFileExpiry)) { $foundExp = Format-GigaFileExpiryText -RawExpiry $r.GigaFileExpiry }
        }
        $txtDlPw.Text = $foundPw
        $txtExpiry.Text = $foundExp

        if ($PreferredLinkType -eq "GigaFile") {
            $rdoGiga.Checked = $true
        } elseif ($PreferredLinkType -eq "MEGA") {
            $rdoMega.Checked = $true
        } else {
            if ($hasAnyGiga) { $rdoGiga.Checked = $true } else { $rdoMega.Checked = $true }
        }
        & $updateLinkTypeControlState
    }

    $rdoGiga.Add_CheckedChanged($updateLinkTypeControlState)
    $rdoMega.Add_CheckedChanged($updateLinkTypeControlState)
    $cmbRecipient.Add_SelectedIndexChanged({
        & $reloadForCurrentRecipient
        $txtMessage.Text = ""
        $lblStatusMsg.Text = "送信先を変更しました。「メッセージを作成」ボタンを押してください。"
    })

    $btnOpenTplSettings.Add_Click({
        $settingsScript = Join-Path $RootDir "editor\SettingsEditor.ps1"
        if (-not (Test-Path -LiteralPath $settingsScript)) {
            [System.Windows.Forms.MessageBox]::Show($dlg, "SettingsEditor.ps1 が見つかりません:`n$settingsScript", "確認", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        . $settingsScript
        [void](Show-PhotoToolsSettingsDialog -RootDir $RootDir -OwnerForm $dlg -InitialTabIndex 3)
        $firstCat = if (@($script:ActiveFolderRecords).Count -gt 0) { [string]$script:ActiveFolderRecords[0].Category } else { "" }
        & $populateTemplatesAndMegaPresets $firstCat
    })

    # --- ヘルパー：対象フォルダ群の 写真情報.txt（ペア含む）＆Excel台帳を更新 ---
    $persistFolderRecordChanges = {
        param([hashtable]$FolderRec)
        $infoObj = $FolderRec.Info
        $infoObj.MegaLink = $FolderRec.MegaLink
        $infoObj.GigaFileLink = $FolderRec.GigaFileLink
        $infoObj.ShareUrl = $FolderRec.GigaFileLink
        $infoObj.DlPassword = $FolderRec.DlPassword
        $infoObj.GigaFileExpiry = $FolderRec.GigaFileExpiry
        $infoObj.SentStatus = $FolderRec.SentStatus
        $infoObj.IsSent = [bool]$FolderRec.IsSent

        $savedDirs = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        $paired = $FolderRec.Paired
        foreach ($d in @($FolderRec.FolderPath, $paired.Target, $paired.ImportFolder, $paired.DevFolder)) {
            if ([string]::IsNullOrWhiteSpace($d) -or -not (Test-Path -LiteralPath $d -PathType Container)) { continue }
            $nd = $d.TrimEnd('\')
            if ($savedDirs.Add($nd)) {
                [void](Write-PhotoInfoTxt -FolderPath $nd -Info $infoObj)
            }
        }
    }

    $syncUpdatedRecordsToExcel = {
        param([array]$FolderRecs)
        if (-not (Get-Command Update-PhotoExcelLedger -ErrorAction SilentlyContinue)) { return }
        $excelRows = New-Object System.Collections.Generic.List[hashtable]
        foreach ($fr in @($FolderRecs)) {
            $ps = @($fr.Persons)
            if ($ps.Count -eq 0) { $ps = @(@{ Name = ""; CostumeOrChar = ""; XAccount = ""; XUrl = ""; Comment = "" }) }
            for ($pi = 0; $pi -lt $ps.Count; $pi++) {
                $p = $ps[$pi]
                $px = ConvertTo-SafeStringProp $p "XAccount"
                $pxUrl = ConvertTo-SafeStringProp $p "XUrl"
                if ([string]::IsNullOrWhiteSpace($pxUrl) -and -not [string]::IsNullOrWhiteSpace($px)) {
                    $pxUrl = "https://x.com/" + $px.TrimStart('@')
                }
                $rowCom = ConvertTo-SafeStringProp $p "Comment"
                if ($pi -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$fr.Notes)) {
                    $rowCom = if ([string]::IsNullOrWhiteSpace($rowCom)) { [string]$fr.Notes } else { "$rowCom`r`n$($fr.Notes)" }
                }
                [void]$excelRows.Add(@{
                    Category        = [string]$fr.Category
                    DateStr         = [string]$fr.DateStr
                    EventName       = [string]$fr.EventName
                    CostumeOrChar   = ConvertTo-SafeStringProp $p "CostumeOrChar"
                    Name            = ConvertTo-SafeStringProp $p "Name"
                    XAccount        = $px
                    XUrl            = $pxUrl
                    Comment         = $rowCom
                    SentStatus      = [string]$fr.SentStatus
                    MegaLink        = [string]$fr.MegaLink
                    GigaFileLink    = [string]$fr.GigaFileLink
                    MultiFolder     = ""
                    MultiFolderFlag = ""
                    RelPath         = [string]$fr.Paired.RelPath
                    ImportRoot      = [string]$effConfig.ImportRoot1
                    ImportFolder    = [string]$fr.Paired.ImportFolder
                    DevRoot         = [string]$effConfig.DevRoot
                    DevFolder       = [string]$fr.Paired.DevFolder
                    FolderName      = [string]$fr.FolderName
                    PersonIndex     = ($pi + 1)
                })
            }
        }
        if ($excelRows.Count -gt 0) {
            try {
                Update-PhotoExcelLedger -Records ([object[]]$excelRows.ToArray()) -Config $effConfig
            } catch {}
        }
    }

    # --- メッセージ作成ボタン ---
    $btnCreateMsg.Add_Click({
        $checkedRecs = New-Object System.Collections.ArrayList
        foreach ($lvi in $lvFolders.Items) {
            $rec = $lvi.Tag
            $rec.Checked = $lvi.Checked
            if ($lvi.Checked) {
                [void]$checkedRecs.Add($rec)
            }
        }
        if ($checkedRecs.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show($dlg, "対象フォルダを1つ以上チェックしてください。", "確認", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }

        if (@($script:TemplateItems).Count -eq 0) {
            $ansTpl = [System.Windows.Forms.MessageBox]::Show(
                $dlg,
                "メッセージ定型文がまだ登録されていません。`n設定画面（メッセージ定型文タブ）を開いてテンプレートを作成しますか？",
                "テンプレート未登録",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($ansTpl -eq [System.Windows.Forms.DialogResult]::Yes) {
                $btnOpenTplSettings.PerformClick()
            }
            return
        }

        $tplIdx = $cmbTemplate.SelectedIndex
        if ($tplIdx -lt 0 -or $tplIdx -ge @($script:TemplateItems).Count) { $tplIdx = 0 }
        $selectedTpl = $script:TemplateItems[$tplIdx]
        $tplBody = ConvertTo-SafeStringProp $selectedTpl "Body"

        $linkType = if ($rdoMega.Checked) { "MEGA" } else { "GigaFile" }

        # MEGA選択時のみ：未取得フォルダがあれば確認画面を出してから取得・写真情報へ反映
        if ($linkType -eq "MEGA") {
            $missingMega = @($checkedRecs | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.MegaLink) })
            if ($missingMega.Count -gt 0) {
                $missNames = ($missingMega | ForEach-Object { "・" + [string]$_.FolderName }) -join "`n"
                $confirmMsg = "MEGAリンクが未取得のフォルダが $($missingMega.Count) 件あります:`n`n$missNames`n`nMEGAリンクを取得して写真情報.txt・Excel台帳へ反映してからメッセージを作成しますか？`n（はい：取得して作成 / いいえ：取得せず作成 / キャンセル：中止）"
                $ansMega = [System.Windows.Forms.MessageBox]::Show(
                    $dlg,
                    $confirmMsg,
                    "MEGAリンク未取得の確認",
                    [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )
                if ($ansMega -eq [System.Windows.Forms.DialogResult]::Cancel) {
                    return
                }
                if ($ansMega -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $btnCreateMsg.Enabled = $false
                    $lblStatusMsg.Text = "MEGAリンクを取得して写真情報へ反映しています..."
                    $dlg.Refresh()
                    $megaUpdatedList = New-Object System.Collections.ArrayList
                    try {
                        foreach ($mRec in $missingMega) {
                            $megaTargetDir = if (-not [string]::IsNullOrWhiteSpace([string]$mRec.Paired.DevFolder) -and (Test-Path -LiteralPath ([string]$mRec.Paired.DevFolder))) {
                                [string]$mRec.Paired.DevFolder
                            } else {
                                [string]$mRec.FolderPath
                            }
                            $mUrl = ""
                            if (Get-Command Get-MegaFolderLink -ErrorAction SilentlyContinue) {
                                $mRes = Get-MegaFolderLink -FolderPath $megaTargetDir -Config $effConfig
                                if ($mRes -is [System.Collections.IDictionary] -and $mRes.Contains("Url")) {
                                    $mUrl = [string]$mRes["Url"]
                                }
                            }
                            if (-not [string]::IsNullOrWhiteSpace($mUrl)) {
                                $mRec.MegaLink = $mUrl.Trim()
                                & $persistFolderRecordChanges $mRec
                                [void]$megaUpdatedList.Add($mRec)
                                $script:ComposerResult.UpdatedMega = $true
                            }
                        }
                        if ($megaUpdatedList.Count -gt 0) {
                            & $syncUpdatedRecordsToExcel (@($megaUpdatedList.ToArray()))
                        }
                    } finally {
                        $btnCreateMsg.Enabled = $true
                        & $refreshFolderListView
                    }
                }
            }
        }

        $curRec = $modelCandidates[$cmbRecipient.SelectedIndex]
        $megaCommentBody = ""
        if ($linkType -eq "MEGA" -and $cmbMegaComment.SelectedIndex -ge 0 -and $cmbMegaComment.SelectedIndex -lt @($script:MegaPresetItems).Count) {
            $megaCommentBody = ConvertTo-SafeStringProp $script:MegaPresetItems[$cmbMegaComment.SelectedIndex] "Body"
        }

        $renderedMsg = Render-DeliveryMessage `
            -TemplateBody $tplBody `
            -LinkType $linkType `
            -FolderEntries (@($checkedRecs.ToArray())) `
            -RecipientName ([string]$curRec.Name) `
            -RecipientXAccount ([string]$curRec.XAccount) `
            -RecipientXUrl ([string]$curRec.XUrl) `
            -OverrideDlPassword $txtDlPw.Text.Trim() `
            -OverrideExpiryText $txtExpiry.Text.Trim() `
            -MegaCommentText $megaCommentBody

        $txtMessage.Text = $renderedMsg
        $script:ComposerResult.MessageText = $renderedMsg
        $lblStatusMsg.Text = "メッセージを作成しました（対象: $($checkedRecs.Count)件 / リンク種別: $linkType）。内容を確認してコピーしてください。"
    })

    # --- クリップボードにコピー（＋送付済みステータス連動） ---
    $btnCopyMsg.Add_Click({
        $textToCopy = $txtMessage.Text
        if ([string]::IsNullOrWhiteSpace($textToCopy)) {
            [System.Windows.Forms.MessageBox]::Show($dlg, "コピーするメッセージが作成されていません。先に「メッセージを作成」ボタンを押してください。", "確認", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }

        [System.Windows.Forms.Clipboard]::SetText($textToCopy)
        $script:ComposerResult.Copied = $true
        $script:ComposerResult.MessageText = $textToCopy

        $statusNotice = "メッセージをクリップボードにコピーしました。"
        if ($chkMarkSent.Checked) {
            $checkedRecs = New-Object System.Collections.ArrayList
            foreach ($lvi in $lvFolders.Items) {
                if ($lvi.Checked) {
                    $rec = $lvi.Tag
                    $rec.SentStatus = "送付済み"
                    $rec.IsSent = $true
                    if ($rdoGiga.Checked) {
                        if (-not [string]::IsNullOrWhiteSpace($txtDlPw.Text.Trim())) { $rec.DlPassword = $txtDlPw.Text.Trim() }
                        if (-not [string]::IsNullOrWhiteSpace($txtExpiry.Text.Trim())) { $rec.GigaFileExpiry = Format-GigaFileExpiryText -RawExpiry $txtExpiry.Text.Trim() }
                    }
                    & $persistFolderRecordChanges $rec
                    [void]$checkedRecs.Add($rec)
                }
            }
            if ($checkedRecs.Count -gt 0) {
                & $syncUpdatedRecordsToExcel (@($checkedRecs.ToArray()))
                $script:ComposerResult.MarkedSent = $true
                & $refreshFolderListView
                $statusNotice += "`n対象フォルダ（$($checkedRecs.Count)件）のステータスを「送付済み」へ更新しました。"
            }
        }

        $lblStatusMsg.Text = $statusNotice.Replace("`n", " ")
        [System.Windows.Forms.MessageBox]::Show($dlg, $statusNotice, "コピー完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    })

    $btnClose.Add_Click({ $dlg.Close() })

    # 初期読み込み（本文は空のまま待機）
    & $reloadForCurrentRecipient

    if ($null -ne $OwnerForm) {
        [void]$dlg.ShowDialog($OwnerForm)
    } else {
        [void]$dlg.ShowDialog()
    }
    $dlg.Dispose()
    return $script:ComposerResult
}

if ($MyInvocation.InvocationName -ne '.') {
    [void](Show-MessageComposerDialog `
        -FolderPaths $FolderPaths `
        -Mode $Mode `
        -PrimaryFolder $PrimaryFolder `
        -DateSearchRoots $DateSearchRoots `
        -PreferredLinkType $PreferredLinkType `
        -OverrideGigaUrl $OverrideGigaUrl `
        -OverrideDlPassword $OverrideDlPassword `
        -OverrideExpiryDate $OverrideExpiryDate `
        -SelectedModelIndex $SelectedModelIndex `
        -SelectedModelX $SelectedModelX `
        -SelectedModelName $SelectedModelName `
        -RootDir $RootDir `
        -Config $Config)
}
