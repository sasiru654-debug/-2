#requires -Version 5.1
# ==============================================================================
# CharacterLookupDialog.ps1 - 漏洩対策付き 写真キャラ名検索ダイアログ (UTF-8 BOM / CRLF)
#   - 送信前プレビュー上で顔・背景をマウスドラッグでマスク（黒塗り/モザイク）
#   - マスクなし時は警告確認ダイアログを表示（A方式）
#   - Exif完全削除・低解像度縮小・完全インメモリ処理・個人情報非送信
#   - 既定反映書式: キャラ名（作品名）
# ==============================================================================
param(
    [string[]]$FolderPaths = @(),
    [string]$RootDir = "",
    [hashtable]$Config = @{}
)

Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-CharacterLookupDialog {
    param(
        [string[]]$FolderPaths = @(),
        [string]$RootDir = "",
        [hashtable]$Config = @{},
        [System.Windows.Forms.IWin32Window]$OwnerForm = $null
    )

    if ([string]::IsNullOrWhiteSpace($RootDir)) {
        $sd = $PSScriptRoot
        if ([string]::IsNullOrWhiteSpace($sd)) { $sd = "D:\PhotoTools\editor" }
        $RootDir = Split-Path -Parent $sd
        if (-not (Test-Path -LiteralPath (Join-Path $RootDir "settings.ini"))) {
            if (Test-Path -LiteralPath "D:\PhotoTools\settings.ini") { $RootDir = "D:\PhotoTools" }
        }
    }

    $commonDir = Join-Path $RootDir "common"
    $geminiHelper = Join-Path $commonDir "GeminiCharacterHelper.ps1"
    $logHelper = Join-Path $commonDir "LogHelper.ps1"
    if (Test-Path -LiteralPath $geminiHelper) { . $geminiHelper }
    if (Test-Path -LiteralPath $logHelper) { . $logHelper }

    $script:AiSettings = Get-GeminiCharacterSettings -RootDir $RootDir -Config $Config
    $script:CandidateImages = New-Object System.Collections.ArrayList
    foreach ($img in @(Get-FolderCandidateImages -FolderPaths $FolderPaths)) {
        [void]$script:CandidateImages.Add($img)
    }

    $script:CurrentBitmap = $null
    $script:CurrentImagePath = ""
    $script:MaskRects = New-Object System.Collections.ArrayList
    $script:IsDraggingMask = $false
    $script:DragStartPt = [System.Drawing.Point]::Empty
    $script:DragCurrentPt = [System.Drawing.Point]::Empty
    $script:LastDisplayRect = [System.Drawing.RectangleF]::Empty
    $script:LastCandidates = @()
    $script:SelectedResultText = ""
    $script:DialogApplied = $false

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "写真からキャラクター名を調べる（漏洩対策プレビュー付き）"
    $dlg.Size = New-Object System.Drawing.Size(1020, 700)
    $dlg.MinimumSize = New-Object System.Drawing.Size(960, 650)
    $dlg.StartPosition = if ($null -ne $OwnerForm) { "CenterParent" } else { "CenterScreen" }
    $dlg.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9)
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)

    # 上部: プライバシー保護ステータスバー
    $pnlTop = New-Object System.Windows.Forms.Panel
    $pnlTop.Dock = "Top"
    $pnlTop.Height = 58
    $pnlTop.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
    $dlg.Controls.Add($pnlTop)

    $lblTopTitle = New-Object System.Windows.Forms.Label
    $lblTopTitle.Text = "AI キャラクター名判定（プライバシー保護モード）"
    $lblTopTitle.Font = New-Object System.Drawing.Font("Yu Gothic UI", 10.5, [System.Drawing.FontStyle]::Bold)
    $lblTopTitle.ForeColor = [System.Drawing.Color]::White
    $lblTopTitle.Location = New-Object System.Drawing.Point(14, 8)
    $lblTopTitle.AutoSize = $true
    $pnlTop.Controls.Add($lblTopTitle)

    $lblPrivacyStatus = New-Object System.Windows.Forms.Label
    $lblPrivacyStatus.Location = New-Object System.Drawing.Point(15, 33)
    $lblPrivacyStatus.Size = New-Object System.Drawing.Size(810, 18)
    $lblPrivacyStatus.ForeColor = [System.Drawing.Color]::FromArgb(153, 246, 228)
    $lblPrivacyStatus.Font = New-Object System.Drawing.Font("Yu Gothic UI", 8.5)
    $pnlTop.Controls.Add($lblPrivacyStatus)

    $btnOpenAiSettings = New-Object System.Windows.Forms.Button
    $btnOpenAiSettings.Text = "AI設定を開く..."
    $btnOpenAiSettings.Location = New-Object System.Drawing.Point(868, 13)
    $btnOpenAiSettings.Size = New-Object System.Drawing.Size(122, 32)
    $btnOpenAiSettings.Anchor = "Top, Right"
    $btnOpenAiSettings.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
    $btnOpenAiSettings.ForeColor = [System.Drawing.Color]::White
    $btnOpenAiSettings.FlatStyle = "Flat"
    $pnlTop.Controls.Add($btnOpenAiSettings)

    # 下部: 反映アクションバー
    $pnlBottom = New-Object System.Windows.Forms.Panel
    $pnlBottom.Dock = "Bottom"
    $pnlBottom.Height = 62
    $pnlBottom.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
    $dlg.Controls.Add($pnlBottom)

    $lblFmt = New-Object System.Windows.Forms.Label
    $lblFmt.Text = "反映書式:"
    $lblFmt.Location = New-Object System.Drawing.Point(14, 21)
    $lblFmt.Size = New-Object System.Drawing.Size(62, 20)
    $pnlBottom.Controls.Add($lblFmt)

    $cmbOutFormat = New-Object System.Windows.Forms.ComboBox
    $cmbOutFormat.Location = New-Object System.Drawing.Point(78, 18)
    $cmbOutFormat.Size = New-Object System.Drawing.Size(160, 24)
    $cmbOutFormat.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$cmbOutFormat.Items.Add("キャラ名（作品名）")
    [void]$cmbOutFormat.Items.Add("キャラ名のみ")
    [void]$cmbOutFormat.Items.Add("作品名 / キャラ名")
    $pnlBottom.Controls.Add($cmbOutFormat)

    $lblApplyPreview = New-Object System.Windows.Forms.Label
    $lblApplyPreview.Text = "反映文字列:"
    $lblApplyPreview.Location = New-Object System.Drawing.Point(250, 21)
    $lblApplyPreview.Size = New-Object System.Drawing.Size(72, 20)
    $pnlBottom.Controls.Add($lblApplyPreview)

    $txtApplyText = New-Object System.Windows.Forms.TextBox
    $txtApplyText.Location = New-Object System.Drawing.Point(324, 18)
    $txtApplyText.Size = New-Object System.Drawing.Size(374, 25)
    $txtApplyText.Anchor = "Bottom, Left, Right"
    $pnlBottom.Controls.Add($txtApplyText)

    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = "衣装・キャラ欄へ反映"
    $btnApply.Location = New-Object System.Drawing.Point(710, 14)
    $btnApply.Size = New-Object System.Drawing.Size(176, 34)
    $btnApply.Anchor = "Bottom, Right"
    $btnApply.BackColor = [System.Drawing.Color]::FromArgb(15, 118, 110)
    $btnApply.ForeColor = [System.Drawing.Color]::White
    $btnApply.FlatStyle = "Flat"
    $btnApply.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $pnlBottom.Controls.Add($btnApply)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "閉じる"
    $btnClose.Location = New-Object System.Drawing.Point(896, 14)
    $btnClose.Size = New-Object System.Drawing.Size(94, 34)
    $btnClose.Anchor = "Bottom, Right"
    $btnClose.BackColor = [System.Drawing.Color]::White
    $pnlBottom.Controls.Add($btnClose)

    # メイン領域
    $pnlMain = New-Object System.Windows.Forms.Panel
    $pnlMain.Dock = "Fill"
    $dlg.Controls.Add($pnlMain)
    $pnlMain.BringToFront()

    # 左パネル: フォルダ内写真リスト
    $grpImages = New-Object System.Windows.Forms.GroupBox
    $grpImages.Text = "1. 判定する写真を選択"
    $grpImages.Location = New-Object System.Drawing.Point(12, 10)
    $grpImages.Size = New-Object System.Drawing.Size(210, 520)
    $grpImages.Anchor = "Top, Bottom, Left"
    $pnlMain.Controls.Add($grpImages)

    $lstImages = New-Object System.Windows.Forms.ListBox
    $lstImages.Location = New-Object System.Drawing.Point(10, 24)
    $lstImages.Size = New-Object System.Drawing.Size(190, 444)
    $lstImages.Anchor = "Top, Bottom, Left, Right"
    $lstImages.IntegralHeight = $false
    $grpImages.Controls.Add($lstImages)

    $btnPickOther = New-Object System.Windows.Forms.Button
    $btnPickOther.Text = "別の画像を参照..."
    $btnPickOther.Location = New-Object System.Drawing.Point(10, 476)
    $btnPickOther.Size = New-Object System.Drawing.Size(190, 32)
    $btnPickOther.Anchor = "Bottom, Left, Right"
    $btnPickOther.BackColor = [System.Drawing.Color]::White
    $grpImages.Controls.Add($btnPickOther)

    # 中央パネル: 送信前プレビュー & 顔マスク編集
    $grpPreview = New-Object System.Windows.Forms.GroupBox
    $grpPreview.Text = "2. 送信前プレビュー（ドラッグで顔や背景をマスク）"
    $grpPreview.Location = New-Object System.Drawing.Point(230, 10)
    $grpPreview.Size = New-Object System.Drawing.Size(432, 520)
    $grpPreview.Anchor = "Top, Bottom, Left, Right"
    $pnlMain.Controls.Add($grpPreview)

    $lblMaskMode = New-Object System.Windows.Forms.Label
    $lblMaskMode.Text = "マスク方式:"
    $lblMaskMode.Location = New-Object System.Drawing.Point(10, 26)
    $lblMaskMode.Size = New-Object System.Drawing.Size(68, 20)
    $grpPreview.Controls.Add($lblMaskMode)

    $rbMaskBlack = New-Object System.Windows.Forms.RadioButton
    $rbMaskBlack.Text = "黒塗り"
    $rbMaskBlack.Location = New-Object System.Drawing.Point(82, 24)
    $rbMaskBlack.AutoSize = $true
    $grpPreview.Controls.Add($rbMaskBlack)

    $rbMaskMosaic = New-Object System.Windows.Forms.RadioButton
    $rbMaskMosaic.Text = "モザイク"
    $rbMaskMosaic.Location = New-Object System.Drawing.Point(150, 24)
    $rbMaskMosaic.AutoSize = $true
    $grpPreview.Controls.Add($rbMaskMosaic)

    $btnUndoMask = New-Object System.Windows.Forms.Button
    $btnUndoMask.Text = "1つ戻す"
    $btnUndoMask.Location = New-Object System.Drawing.Point(242, 21)
    $btnUndoMask.Size = New-Object System.Drawing.Size(80, 26)
    $btnUndoMask.BackColor = [System.Drawing.Color]::White
    $grpPreview.Controls.Add($btnUndoMask)

    $btnClearMask = New-Object System.Windows.Forms.Button
    $btnClearMask.Text = "全消去"
    $btnClearMask.Location = New-Object System.Drawing.Point(328, 21)
    $btnClearMask.Size = New-Object System.Drawing.Size(92, 26)
    $btnClearMask.BackColor = [System.Drawing.Color]::White
    $grpPreview.Controls.Add($btnClearMask)

    $picPreview = New-Object System.Windows.Forms.PictureBox
    $picPreview.Location = New-Object System.Drawing.Point(10, 54)
    $picPreview.Size = New-Object System.Drawing.Size(412, 412)
    $picPreview.Anchor = "Top, Bottom, Left, Right"
    $picPreview.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $picPreview.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $picPreview.Cursor = [System.Windows.Forms.Cursors]::Cross
    $grpPreview.Controls.Add($picPreview)

    $lblSendSpec = New-Object System.Windows.Forms.Label
    $lblSendSpec.Location = New-Object System.Drawing.Point(10, 474)
    $lblSendSpec.Size = New-Object System.Drawing.Size(412, 38)
    $lblSendSpec.Anchor = "Bottom, Left, Right"
    $lblSendSpec.ForeColor = [System.Drawing.Color]::FromArgb(30, 64, 175)
    $lblSendSpec.Font = New-Object System.Drawing.Font("Yu Gothic UI", 8.5)
    $grpPreview.Controls.Add($lblSendSpec)

    # 右パネル: 判定実行 & 候補一覧
    $grpResult = New-Object System.Windows.Forms.GroupBox
    $grpResult.Text = "3. AI判定実行・候補選択"
    $grpResult.Location = New-Object System.Drawing.Point(670, 10)
    $grpResult.Size = New-Object System.Drawing.Size(322, 520)
    $grpResult.Anchor = "Top, Bottom, Right"
    $pnlMain.Controls.Add($grpResult)

    $lblHint = New-Object System.Windows.Forms.Label
    $lblHint.Text = "補足ヒント（作品ジャンル等・任意／個人情報は入力不可）:"
    $lblHint.Location = New-Object System.Drawing.Point(10, 24)
    $lblHint.Size = New-Object System.Drawing.Size(302, 18)
    $lblHint.Font = New-Object System.Drawing.Font("Yu Gothic UI", 8)
    $lblHint.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $grpResult.Controls.Add($lblHint)

    $txtHint = New-Object System.Windows.Forms.TextBox
    $txtHint.Location = New-Object System.Drawing.Point(10, 44)
    $txtHint.Size = New-Object System.Drawing.Size(302, 24)
    $grpResult.Controls.Add($txtHint)

    $btnRunLookup = New-Object System.Windows.Forms.Button
    $btnRunLookup.Text = "この画像でキャラ判定を実行"
    $btnRunLookup.Location = New-Object System.Drawing.Point(10, 76)
    $btnRunLookup.Size = New-Object System.Drawing.Size(302, 36)
    $btnRunLookup.BackColor = [System.Drawing.Color]::FromArgb(29, 78, 216)
    $btnRunLookup.ForeColor = [System.Drawing.Color]::White
    $btnRunLookup.FlatStyle = "Flat"
    $btnRunLookup.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $grpResult.Controls.Add($btnRunLookup)

    $lblLookupStatus = New-Object System.Windows.Forms.Label
    $lblLookupStatus.Text = "待機中（自動送信は行いません）"
    $lblLookupStatus.Location = New-Object System.Drawing.Point(10, 118)
    $lblLookupStatus.Size = New-Object System.Drawing.Size(302, 20)
    $lblLookupStatus.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $lblLookupStatus.Font = New-Object System.Drawing.Font("Yu Gothic UI", 8.5)
    $grpResult.Controls.Add($lblLookupStatus)

    $lvResults = New-Object System.Windows.Forms.ListView
    $lvResults.Location = New-Object System.Drawing.Point(10, 142)
    $lvResults.Size = New-Object System.Drawing.Size(302, 250)
    $lvResults.Anchor = "Top, Bottom, Left, Right"
    $lvResults.View = [System.Windows.Forms.View]::Details
    $lvResults.FullRowSelect = $true
    $lvResults.GridLines = $true
    $lvResults.HideSelection = $false
    $lvResults.MultiSelect = $false
    [void]$lvResults.Columns.Add("キャラ名", 115)
    [void]$lvResults.Columns.Add("作品名", 130)
    [void]$lvResults.Columns.Add("確信", 46)
    $grpResult.Controls.Add($lvResults)

    $lblReasonTitle = New-Object System.Windows.Forms.Label
    $lblReasonTitle.Text = "判定根拠メモ:"
    $lblReasonTitle.Location = New-Object System.Drawing.Point(10, 398)
    $lblReasonTitle.Size = New-Object System.Drawing.Size(120, 18)
    $lblReasonTitle.Anchor = "Bottom, Left"
    $lblReasonTitle.Font = New-Object System.Drawing.Font("Yu Gothic UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $grpResult.Controls.Add($lblReasonTitle)

    $txtReason = New-Object System.Windows.Forms.TextBox
    $txtReason.Location = New-Object System.Drawing.Point(10, 418)
    $txtReason.Size = New-Object System.Drawing.Size(302, 90)
    $txtReason.Anchor = "Bottom, Left, Right"
    $txtReason.Multiline = $true
    $txtReason.ReadOnly = $true
    $txtReason.ScrollBars = "Vertical"
    $txtReason.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
    $grpResult.Controls.Add($txtReason)

    # ヘルパー関数群
    $getSelectedFormatKey = {
        switch ($cmbOutFormat.SelectedIndex) {
            1 { return "CharOnly" }
            2 { return "SeriesSlashChar" }
            default { return "CharWithSeries" }
        }
    }

    $refreshPrivacyBanner = {
        $script:AiSettings = Get-GeminiCharacterSettings -RootDir $RootDir -Config $Config
        $hasKey = Test-GeminiApiKeyStored -RootDir $RootDir -Config $Config
        $keyTxt = if ($hasKey) { "APIキー:暗号化済(DPAPI)" } else { "APIキー:未登録" }
        $paidTxt = if ([bool]$script:AiSettings["PaidTierConfirmed"]) { "有料枠確認済(学習なし)" } else { "有料枠:未確認" }
        $px = [int]$script:AiSettings["MaxImageEdgePx"]
        $mdl = [string]$script:AiSettings["ModelName"]
        $lblPrivacyStatus.Text = "$keyTxt  |  $paidTxt  |  モデル:$mdl  |  長辺${px}px縮小・Exif完全削除・一時ファイル保存なし・個人情報非送信"
        if ($hasKey -and [bool]$script:AiSettings["PaidTierConfirmed"]) {
            $lblPrivacyStatus.ForeColor = [System.Drawing.Color]::FromArgb(153, 246, 228)
        } else {
            $lblPrivacyStatus.ForeColor = [System.Drawing.Color]::FromArgb(253, 224, 71)
        }
    }

    $updateSendSpecLabel = {
        if ($null -eq $script:CurrentBitmap) {
            $lblSendSpec.Text = "写真を選択してください（JPG / PNG 対応）。`r`n送信時は Exif 完全削除＋縮小＋個人情報非送信でメモリ上のみ処理します。"
            return
        }
        $px = [int]$script:AiSettings["MaxImageEdgePx"]
        $origW = $script:CurrentBitmap.Width
        $origH = $script:CurrentBitmap.Height
        $scale = if ([Math]::Max($origW, $origH) -gt $px) { [double]$px / [double][Math]::Max($origW, $origH) } else { 1.0 }
        $sw = [int][Math]::Round($origW * $scale)
        $sh = [int][Math]::Round($origH * $scale)
        $mc = $script:MaskRects.Count
        $maskNote = if ($mc -gt 0) { "マスク: ${mc}箇所適用済" } else { "マスク: 未設定（送信時に確認ダイアログ表示）" }
        $lblSendSpec.Text = "送信サイズ: ${sw}x${sh}px（元 ${origW}x${origH}） / Exif完全削除 / 一時ファイルなし`r`n$maskNote"
    }

    $computeDisplayRect = {
        if ($null -eq $script:CurrentBitmap -or $picPreview.ClientSize.Width -le 0 -or $picPreview.ClientSize.Height -le 0) {
            return [System.Drawing.RectangleF]::Empty
        }
        $cw = [float]$picPreview.ClientSize.Width
        $ch = [float]$picPreview.ClientSize.Height
        $iw = [float]$script:CurrentBitmap.Width
        $ih = [float]$script:CurrentBitmap.Height
        $ratio = [Math]::Min($cw / $iw, $ch / $ih)
        $dw = $iw * $ratio
        $dh = $ih * $ratio
        $dx = ($cw - $dw) / 2.0
        $dy = ($ch - $dh) / 2.0
        return (New-Object System.Drawing.RectangleF([float]$dx, [float]$dy, [float]$dw, [float]$dh))
    }

    $loadImageFile = {
        param([string]$ImgPath)
        if ([string]::IsNullOrWhiteSpace($ImgPath) -or -not (Test-Path -LiteralPath $ImgPath -PathType Leaf)) { return }
        if ($null -ne $script:CurrentBitmap) {
            $script:CurrentBitmap.Dispose()
            $script:CurrentBitmap = $null
        }
        try {
            $script:CurrentBitmap = New-DisplayBitmapWithoutLock -ImagePath $ImgPath
            $script:CurrentImagePath = $ImgPath
            $script:MaskRects.Clear()
            & $updateSendSpecLabel
            $picPreview.Invalidate()
        } catch {
            [System.Windows.Forms.MessageBox]::Show($dlg, "画像の読み込みに失敗しました:`n$($_.Exception.Message)", "画像読込エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    }

    $updateApplyPreviewFromSelection = {
        if ($lvResults.SelectedItems.Count -eq 0) { return }
        $selItem = $lvResults.SelectedItems[0]
        $cand = $selItem.Tag
        if ($null -eq $cand) { return }
        $fmtKey = & $getSelectedFormatKey
        $txtApplyText.Text = Format-CharacterResultText -CharacterName ([string]$cand.CharacterName) -SeriesName ([string]$cand.SeriesName) -FormatType $fmtKey
        $txtReason.Text = [string]$cand.Reason
    }

    # 初期UI値設定
    if ([string]$script:AiSettings["DefaultMaskStyle"] -eq "Mosaic") {
        $rbMaskMosaic.Checked = $true
    } else {
        $rbMaskBlack.Checked = $true
    }
    switch ([string]$script:AiSettings["DefaultOutputFormat"]) {
        "CharOnly"        { $cmbOutFormat.SelectedIndex = 1 }
        "SeriesSlashChar" { $cmbOutFormat.SelectedIndex = 2 }
        default           { $cmbOutFormat.SelectedIndex = 0 }
    }
    & $refreshPrivacyBanner

    foreach ($ci in @($script:CandidateImages)) {
        [void]$lstImages.Items.Add("$($ci.Name)  ($($ci.SizeKB) KB)")
    }

    # Preview Paint & Drag Masking
    $picPreview.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        if ($null -eq $script:CurrentBitmap) {
            $sf = New-Object System.Drawing.StringFormat
            $sf.Alignment = [System.Drawing.StringAlignment]::Center
            $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
            $br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(148, 163, 184))
            try {
                $g.DrawString("左の一覧から写真を選択するか`n「別の画像を参照...」で開いてください", $dlg.Font, $br, [System.Drawing.RectangleF]$picPreview.ClientRectangle, $sf)
            } finally {
                $br.Dispose()
                $sf.Dispose()
            }
            return
        }

        $dr = & $computeDisplayRect
        $script:LastDisplayRect = $dr
        $g.DrawImage($script:CurrentBitmap, $dr)

        $isMosaic = $rbMaskMosaic.Checked
        $fillBrush = if ($isMosaic) {
            New-Object System.Drawing.Drawing2D.HatchBrush([System.Drawing.Drawing2D.HatchStyle]::LargeCheckerBoard, [System.Drawing.Color]::FromArgb(220, 30, 41, 59), [System.Drawing.Color]::FromArgb(220, 148, 163, 184))
        } else {
            New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 20, 20, 20))
        }
        $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(56, 189, 248), 1.5)
        try {
            foreach ($mr in @($script:MaskRects)) {
                $rx = $dr.X + ([float]$mr.X * $dr.Width)
                $ry = $dr.Y + ([float]$mr.Y * $dr.Height)
                $rw = [float]$mr.W * $dr.Width
                $rh = [float]$mr.H * $dr.Height
                $g.FillRectangle($fillBrush, $rx, $ry, $rw, $rh)
                $g.DrawRectangle($borderPen, $rx, $ry, $rw, $rh)
            }
        } finally {
            $fillBrush.Dispose()
            $borderPen.Dispose()
        }

        if ($script:IsDraggingMask) {
            $x0 = [Math]::Min($script:DragStartPt.X, $script:DragCurrentPt.X)
            $y0 = [Math]::Min($script:DragStartPt.Y, $script:DragCurrentPt.Y)
            $w0 = [Math]::Abs($script:DragCurrentPt.X - $script:DragStartPt.X)
            $h0 = [Math]::Abs($script:DragCurrentPt.Y - $script:DragStartPt.Y)
            $dragBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140, 14, 165, 233))
            $dragPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 1.5)
            $dragPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
            try {
                $g.FillRectangle($dragBrush, $x0, $y0, $w0, $h0)
                $g.DrawRectangle($dragPen, $x0, $y0, $w0, $h0)
            } finally {
                $dragBrush.Dispose()
                $dragPen.Dispose()
            }
        }
    })

    $picPreview.Add_Resize({ $picPreview.Invalidate() })

    $picPreview.Add_MouseDown({
        param($sender, $e)
        if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        if ($null -eq $script:CurrentBitmap) { return }
        $script:IsDraggingMask = $true
        $script:DragStartPt = $e.Location
        $script:DragCurrentPt = $e.Location
        $picPreview.Invalidate()
    })

    $picPreview.Add_MouseMove({
        param($sender, $e)
        if (-not $script:IsDraggingMask) { return }
        $script:DragCurrentPt = $e.Location
        $picPreview.Invalidate()
    })

    $picPreview.Add_MouseUp({
        param($sender, $e)
        if (-not $script:IsDraggingMask) { return }
        $script:IsDraggingMask = $false
        $dr = $script:LastDisplayRect
        if ($dr.Width -gt 0 -and $dr.Height -gt 0) {
            $x0 = [Math]::Max($dr.Left, [Math]::Min($script:DragStartPt.X, $e.Location.X))
            $y0 = [Math]::Max($dr.Top, [Math]::Min($script:DragStartPt.Y, $e.Location.Y))
            $x1 = [Math]::Min($dr.Right, [Math]::Max($script:DragStartPt.X, $e.Location.X))
            $y1 = [Math]::Min($dr.Bottom, [Math]::Max($script:DragStartPt.Y, $e.Location.Y))
            if (($x1 - $x0) -ge 6 -and ($y1 - $y0) -ge 6) {
                $normRect = [PSCustomObject]@{
                    X = [double](($x0 - $dr.Left) / $dr.Width)
                    Y = [double](($y0 - $dr.Top) / $dr.Height)
                    W = [double](($x1 - $x0) / $dr.Width)
                    H = [double](($y1 - $y0) / $dr.Height)
                }
                [void]$script:MaskRects.Add($normRect)
                & $updateSendSpecLabel
            }
        }
        $picPreview.Invalidate()
    })

    $rbMaskBlack.Add_CheckedChanged({ $picPreview.Invalidate() })
    $rbMaskMosaic.Add_CheckedChanged({ $picPreview.Invalidate() })

    $btnUndoMask.Add_Click({
        if ($script:MaskRects.Count -gt 0) {
            $script:MaskRects.RemoveAt($script:MaskRects.Count - 1)
            & $updateSendSpecLabel
            $picPreview.Invalidate()
        }
    })

    $btnClearMask.Add_Click({
        if ($script:MaskRects.Count -gt 0) {
            $script:MaskRects.Clear()
            & $updateSendSpecLabel
            $picPreview.Invalidate()
        }
    })

    $lstImages.Add_SelectedIndexChanged({
        $idx = $lstImages.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $script:CandidateImages.Count) {
            & $loadImageFile ([string]$script:CandidateImages[$idx].FullName)
        }
    })

    $btnPickOther.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Title = "キャラ判定に使用する画像を選択"
        $ofd.Filter = "画像ファイル (*.jpg;*.jpeg;*.png;*.bmp)|*.jpg;*.jpeg;*.png;*.bmp"
        foreach ($fp in @($FolderPaths)) {
            if (-not [string]::IsNullOrWhiteSpace($fp) -and (Test-Path -LiteralPath $fp -PathType Container)) {
                $ofd.InitialDirectory = $fp
                break
            }
        }
        if ($ofd.ShowDialog($dlg) -eq [System.Windows.Forms.DialogResult]::OK) {
            $fi = Get-Item -LiteralPath $ofd.FileName
            $entry = [PSCustomObject]@{
                Name     = $fi.Name
                FullName = $fi.FullName
                DirName  = Split-Path -Leaf $fi.DirectoryName
                SizeKB   = [Math]::Round($fi.Length / 1024.0, 1)
            }
            [void]$script:CandidateImages.Add($entry)
            $newIdx = $lstImages.Items.Add("$($entry.Name)  ($($entry.SizeKB) KB)")
            $lstImages.SelectedIndex = $newIdx
        }
        $ofd.Dispose()
    })

    $btnOpenAiSettings.Add_Click({
        $settingsScript = Join-Path $RootDir "editor\SettingsEditor.ps1"
        if (-not (Test-Path -LiteralPath $settingsScript)) {
            [System.Windows.Forms.MessageBox]::Show($dlg, "SettingsEditor.ps1 が見つかりません:`n$settingsScript", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            return
        }
        . $settingsScript
        [void](Show-PhotoToolsSettingsDialog -RootDir $RootDir -OwnerForm $dlg -InitialTabIndex 4)
        & $refreshPrivacyBanner
        & $updateSendSpecLabel
    })

    $cmbOutFormat.Add_SelectedIndexChanged({
        & $updateApplyPreviewFromSelection
    })

    $lvResults.Add_SelectedIndexChanged({
        & $updateApplyPreviewFromSelection
    })

    $lvResults.Add_DoubleClick({
        & $updateApplyPreviewFromSelection
        if (-not [string]::IsNullOrWhiteSpace($txtApplyText.Text.Trim())) {
            $script:SelectedResultText = $txtApplyText.Text.Trim()
            $script:DialogApplied = $true
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dlg.Close()
        }
    })

    # 判定実行
    $btnRunLookup.Add_Click({
        if ([string]::IsNullOrWhiteSpace($script:CurrentImagePath) -or $null -eq $script:CurrentBitmap) {
            [System.Windows.Forms.MessageBox]::Show($dlg, "先に判定対象の写真を選択してください。", "確認", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }

        & $refreshPrivacyBanner
        $hasKey = Test-GeminiApiKeyStored -RootDir $RootDir -Config $Config
        if (-not $hasKey) {
            $ansKey = [System.Windows.Forms.MessageBox]::Show($dlg, "Gemini APIキーがまだ登録されていません。`n設定画面の「AIキャラ判定」タブを開いて登録しますか？", "APIキー未設定", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($ansKey -eq [System.Windows.Forms.DialogResult]::Yes) {
                $btnOpenAiSettings.PerformClick()
            }
            return
        }

        if (-not [bool]$script:AiSettings["PaidTierConfirmed"]) {
            $ansPaid = [System.Windows.Forms.MessageBox]::Show($dlg, "漏洩リスク対策のため、Google Cloud 請求先紐づけ済み（有料枠・学習利用なし規約）の確認が未チェックの状態では送信できません。`n`n設定画面の「AIキャラ判定」タブを開いて確認・保存しますか？", "有料枠確認が必要です", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($ansPaid -eq [System.Windows.Forms.DialogResult]::Yes) {
                $btnOpenAiSettings.PerformClick()
            }
            return
        }

        # A方式: 顔マスク未設定時は警告ダイアログで確認
        if ($script:MaskRects.Count -eq 0) {
            $ansMask = [System.Windows.Forms.MessageBox]::Show(
                $dlg,
                "顔マスクが1箇所も設定されていません。`n`n後ろ姿や小物アップなど顔が写っていない写真ですか？`n顔が写っている場合は「いいえ」を押してプレビュー上で顔部分をドラッグして隠してから送信してください。`n`nこのままマスクなしで送信してよろしいですか？",
                "顔マスク未設定の確認",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($ansMask -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }
        }

        $btnRunLookup.Enabled = $false
        $btnRunLookup.Text = "判定中...（縮小・Exif除去→送信）"
        $lblLookupStatus.Text = "画像をメモリ上で縮小・Exif除去して送信中..."
        $lblLookupStatus.ForeColor = [System.Drawing.Color]::FromArgb(29, 78, 216)
        $dlg.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        [System.Windows.Forms.Application]::DoEvents()

        try {
            $apiKey = Get-GeminiApiKeyDecrypted -RootDir $RootDir -Config $Config
            $maskStyle = if ($rbMaskMosaic.Checked) { "Mosaic" } else { "Black" }
            $maxPx = [int]$script:AiSettings["MaxImageEdgePx"]
            $jpgQ = [int]$script:AiSettings["JpegQuality"]
            $modelName = [string]$script:AiSettings["ModelName"]

            $payload = New-SanitizedImagePayload `
                -ImagePath $script:CurrentImagePath `
                -MaskRectsNormalized @($script:MaskRects.ToArray()) `
                -MaskStyle $maskStyle `
                -MaxEdgePx $maxPx `
                -JpegQuality $jpgQ

            $kb = [Math]::Round($payload.ByteLength / 1024.0, 1)
            $lblLookupStatus.Text = "送信中 ($($payload.Width)x$($payload.Height)px / ${kb}KB / マスク$($payload.MaskCount)箇所)..."
            [System.Windows.Forms.Application]::DoEvents()

            $cands = @(Invoke-GeminiCharacterLookup `
                -Base64Image ([string]$payload.Base64) `
                -MimeType ([string]$payload.MimeType) `
                -ApiKey $apiKey `
                -ModelName $modelName `
                -ExtraHint $txtHint.Text)

            $script:LastCandidates = $cands
            $lvResults.Items.Clear()
            foreach ($c in $cands) {
                $item = New-Object System.Windows.Forms.ListViewItem([string]$c.CharacterName)
                [void]$item.SubItems.Add([string]$c.SeriesName)
                [void]$item.SubItems.Add([string]$c.Confidence)
                $item.Tag = $c
                [void]$lvResults.Items.Add($item)
            }

            if ($lvResults.Items.Count -gt 0) {
                $lvResults.Items[0].Selected = $true
                & $updateApplyPreviewFromSelection
                $lblLookupStatus.Text = "判定完了: $($lvResults.Items.Count)件の候補を取得（送信データ ${kb}KB / Exif除去済）"
                $lblLookupStatus.ForeColor = [System.Drawing.Color]::FromArgb(4, 120, 87)
            } else {
                $txtReason.Text = "該当する候補を取得できませんでした。別の写真や補足ヒントを試してください。"
                $lblLookupStatus.Text = "候補なし"
                $lblLookupStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 83, 9)
            }

            if (Get-Command Write-PhotoLog -ErrorAction SilentlyContinue) {
                [void](Write-PhotoLog -Message "AIキャラ判定実行完了: Model=$modelName, Res=$($payload.Width)x$($payload.Height), Masks=$($payload.MaskCount), Candidates=$($cands.Count)" -ModuleName "CharacterLookup" -Level "INFO")
            }
        } catch {
            $errMsg = $_.Exception.Message
            $lblLookupStatus.Text = "判定エラーが発生しました"
            $lblLookupStatus.ForeColor = [System.Drawing.Color]::Crimson
            $txtReason.Text = $errMsg
            if (Get-Command Write-PhotoError -ErrorAction SilentlyContinue) {
                [void](Write-PhotoError -Message "AIキャラ判定エラー: $errMsg" -ModuleName "CharacterLookup")
            }
            [System.Windows.Forms.MessageBox]::Show($dlg, "キャラクター判定に失敗しました:`n`n$errMsg", "判定エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        } finally {
            $btnRunLookup.Enabled = $true
            $btnRunLookup.Text = "この画像でキャラ判定を実行"
            $dlg.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    })

    $btnApply.Add_Click({
        $val = $txtApplyText.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            [System.Windows.Forms.MessageBox]::Show($dlg, "反映する文字列が空です。候補を選択するか入力してください。", "確認", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        $script:SelectedResultText = $val
        $script:DialogApplied = $true
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    })

    $btnClose.Add_Click({
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dlg.Close()
    })

    $dlg.Add_FormClosed({
        if ($null -ne $script:CurrentBitmap) {
            $script:CurrentBitmap.Dispose()
            $script:CurrentBitmap = $null
        }
    })

    if ($lstImages.Items.Count -gt 0) {
        $lstImages.SelectedIndex = 0
    } else {
        & $updateSendSpecLabel
    }

    if ($null -ne $OwnerForm) {
        [void]$dlg.ShowDialog($OwnerForm)
    } else {
        [void]$dlg.ShowDialog()
    }
    $dlg.Dispose()

    return @{
        Applied      = $script:DialogApplied
        SelectedText = $script:SelectedResultText
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    [void](Show-CharacterLookupDialog -FolderPaths $FolderPaths -RootDir $RootDir -Config $Config)
}
