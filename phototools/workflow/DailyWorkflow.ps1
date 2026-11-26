#requires -Version 5.1
# ==============================================================================
# DailyWorkflow.ps1 - 日次写真整理ワークフローGUI (UTF-8 BOM / CRLF)
# ==============================================================================
param(
    [Parameter(Position = 0)]
    [Alias("TargetFolder", "DateFolder", "Path")]
    [string]$TargetPath = ""
)

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $ErrorActionPreference = "Stop"

    $WorkflowDir = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($WorkflowDir)) { $WorkflowDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
    if ([string]::IsNullOrWhiteSpace($WorkflowDir)) { $WorkflowDir = "D:\PhotoTools\workflow" }
    $RootDir = Split-Path -Parent $WorkflowDir
    if (-not (Test-Path -LiteralPath (Join-Path $RootDir "settings.ini"))) {
        if (Test-Path -LiteralPath "D:\PhotoTools\settings.ini") { $RootDir = "D:\PhotoTools" }
    }
    $CommonDir = Join-Path $RootDir "common"

    . (Join-Path $CommonDir "LogHelper.ps1")
    . (Join-Path $CommonDir "ConfigHelper.ps1")
    . (Join-Path $CommonDir "SceneHelper.ps1")
    . (Join-Path $CommonDir "XHelper.ps1")
    . (Join-Path $CommonDir "PhotoInfoHelper.ps1")
    . (Join-Path $CommonDir "ExcelHelper.ps1")
    . (Join-Path $CommonDir "GigaFileHelper.ps1")

    . (Join-Path $WorkflowDir "WorkflowStep1Helper.ps1")
    . (Join-Path $WorkflowDir "WorkflowStep2Helper.ps1")
    . (Join-Path $WorkflowDir "WorkflowStep3Helper.ps1")
    . (Join-Path $WorkflowDir "WorkflowStep4Helper.ps1")
    . (Join-Path $WorkflowDir "WorkflowStep5Helper.ps1")

    Initialize-PhotoLogger -RootDir $RootDir | Out-Null
    $Config = Get-PhotoToolsConfig -RootDir $RootDir
    if (Get-Command Ensure-XHistoryFile -ErrorAction SilentlyContinue) {
        Ensure-XHistoryFile -HistoryPath ([string]$Config.XHistoryPath)
    }

$script:ActiveDateName = ""
$script:ActiveDateKey = ""
$script:ActiveDateFolder = ""
$script:ActiveImportDateFolder = ""
$script:ActiveDevDateFolder = ""
$script:ActiveRawDateFolder = ""
$script:SelectedChildSceneRoot = ""
$script:IsUpdatingSceneUI = $false
$script:StepButtons = @{}
$script:LaunchedEditorProcs = New-Object System.Collections.ArrayList
$script:IsStepBusy = $false
$script:RunningHelperProc = $null

function Test-IsSameOrSubPath {
    param([string]$Path, [string]$BaseRoot)
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($BaseRoot)) { return $false }
    $np = $Path.Trim().TrimEnd('\')
    $nb = $BaseRoot.Trim().TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($np) -or [string]::IsNullOrWhiteSpace($nb)) { return $false }
    return ($np -ieq $nb) -or $np.StartsWith(($nb + "\"), [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-IsAllowedImportPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return (Test-IsSameOrSubPath -Path $Path -BaseRoot ([string]$Config.ImportRoot1)) -or
           (Test-IsSameOrSubPath -Path $Path -BaseRoot ([string]$Config.ImportRoot2))
}

function Get-NormalizedDateKeyFromName {
    param([string]$FolderName)
    if ([string]::IsNullOrWhiteSpace($FolderName)) { return "" }
    $dt = Resolve-DateFromFolderName -FolderName $FolderName
    if ($null -ne $dt) {
        return $dt.ToString("yyyy-MM-dd")
    }
    return ""
}

function Find-DateFolderInBaseRoot {
    param(
        [string]$BaseRoot,
        [string]$DateFolderName,
        [string]$DateKey = ""
    )
    if ([string]::IsNullOrWhiteSpace($BaseRoot)) { return "" }
    $normBase = $BaseRoot.Trim().TrimEnd('\')
    if (-not (Test-Path -LiteralPath $normBase)) { return "" }

    if (-not [string]::IsNullOrWhiteSpace($DateFolderName)) {
        $exact = Join-Path $normBase $DateFolderName
        if (Test-Path -LiteralPath $exact -PathType Container) {
            return $exact
        }
    }

    $targetKey = if (-not [string]::IsNullOrWhiteSpace($DateKey)) { $DateKey } else { Get-NormalizedDateKeyFromName -FolderName $DateFolderName }
    if (-not [string]::IsNullOrWhiteSpace($targetKey)) {
        $dirs = @(Get-ChildItem -LiteralPath $normBase -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($d in $dirs) {
            $k = Get-NormalizedDateKeyFromName -FolderName $d.Name
            if ($k -eq $targetKey) {
                return $d.FullName
            }
        }
    }
    return ""
}

function Resolve-DateFolderFromTarget {
    param([string]$InputPath)
    $dateRegex = '^\d{4}(?:[-_.]\d{2}[-_.]\d{2}|\d{4})(?:$|[_\-\s].*)'
    if (-not [string]::IsNullOrWhiteSpace($InputPath)) {
        $norm = $InputPath.Trim().Trim('"').TrimEnd('\')
        if (Test-Path -LiteralPath $norm -PathType Leaf) {
            $norm = [System.IO.Path]::GetDirectoryName($norm)
        }
        $curr = $norm
        for ($i = 0; $i -lt 10; $i++) {
            if ([string]::IsNullOrWhiteSpace($curr)) { break }
            $leaf = [System.IO.Path]::GetFileName($curr)
            if ($leaf -match $dateRegex) {
                $relSub = ""
                if ($curr -ine $norm -and $norm.Length -gt $curr.Length) {
                    $relSub = $norm.Substring($curr.Length).TrimStart('\')
                }
                return @{
                    DateFolder      = $curr
                    DateFolderName  = $leaf
                    DateKey         = (Get-NormalizedDateKeyFromName -FolderName $leaf)
                    SelectedSubRel  = $relSub
                    SelectedSubPath = if ([string]::IsNullOrWhiteSpace($relSub)) { "" } else { $norm }
                }
            }
            $curr = [System.IO.Path]::GetDirectoryName($curr)
        }
        $leafFallback = [System.IO.Path]::GetFileName($norm)
        return @{
            DateFolder      = $norm
            DateFolderName  = $leafFallback
            DateKey         = (Get-NormalizedDateKeyFromName -FolderName $leafFallback)
            SelectedSubRel  = ""
            SelectedSubPath = ""
        }
    }

    # 引数未指定時：取り込み元・現像後・RAW から最新の日付フォルダを検出
    $latestDir = ""
    $latestKey = ""
    foreach ($root in @([string]$Config.ImportRoot1, [string]$Config.ImportRoot2, [string]$Config.DevelopedRoot, [string]$Config.RawSaveRoot)) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) { continue }
        $dirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $dateRegex } | Sort-Object Name -Descending)
        if (@($dirs).Count -gt 0) {
            $cand = $dirs[0]
            $ck = Get-NormalizedDateKeyFromName -FolderName $cand.Name
            if ([string]::IsNullOrWhiteSpace($latestDir) -or ($ck -gt $latestKey)) {
                $latestDir = $cand.FullName
                $latestKey = $ck
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($latestDir)) {
        $lf = [System.IO.Path]::GetFileName($latestDir)
        return @{
            DateFolder      = $latestDir
            DateFolderName  = $lf
            DateKey         = (Get-NormalizedDateKeyFromName -FolderName $lf)
            SelectedSubRel  = ""
            SelectedSubPath = ""
        }
    }

    $fallbackBase = if (-not [string]::IsNullOrWhiteSpace([string]$Config.ImportRoot1)) { [string]$Config.ImportRoot1 }
                    elseif (-not [string]::IsNullOrWhiteSpace([string]$Config.DevelopedRoot)) { [string]$Config.DevelopedRoot }
                    elseif (-not [string]::IsNullOrWhiteSpace([string]$Config.ImportRoot2)) { [string]$Config.ImportRoot2 }
                    else { $RootDir }
    $todayName = (Get-Date).ToString("yyyy_MM_dd")
    return @{
        DateFolder      = (Join-Path $fallbackBase $todayName)
        DateFolderName  = $todayName
        DateKey         = (Get-Date).ToString("yyyy-MM-dd")
        SelectedSubRel  = ""
        SelectedSubPath = ""
    }
}

function Get-ActiveAnchorFolder {
    if (-not [string]::IsNullOrWhiteSpace($script:ActiveDevDateFolder) -and (Test-Path -LiteralPath $script:ActiveDevDateFolder)) {
        return $script:ActiveDevDateFolder
    }
    if (-not [string]::IsNullOrWhiteSpace($script:ActiveImportDateFolder) -and (Test-Path -LiteralPath $script:ActiveImportDateFolder)) {
        return $script:ActiveImportDateFolder
    }
    if (-not [string]::IsNullOrWhiteSpace($script:ActiveRawDateFolder) -and (Test-Path -LiteralPath $script:ActiveRawDateFolder)) {
        return $script:ActiveRawDateFolder
    }
    return $script:ActiveDateFolder
}

function Get-RelativeSubPathFromActiveRoots {
    param([string]$FolderPath)
    if ([string]::IsNullOrWhiteSpace($FolderPath)) { return "" }
    $norm = $FolderPath.Trim().TrimEnd('\')
    foreach ($base in @($script:ActiveDevDateFolder, $script:ActiveImportDateFolder, $script:ActiveRawDateFolder, $script:ActiveDateFolder)) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        $nb = $base.Trim().TrimEnd('\')
        if ($norm -ieq $nb) { return "" }
        if ($norm.StartsWith(($nb + "\"), [System.StringComparison]::OrdinalIgnoreCase)) {
            return $norm.Substring($nb.Length).TrimStart('\')
        }
    }
    return ""
}

function Resolve-PreferredSubFolderPath {
    param([string]$RelSubPath = "")
    $cleanRel = if ($null -eq $RelSubPath) { "" } else { $RelSubPath.Trim().Trim('\') }
    $bases = @($script:ActiveDevDateFolder, $script:ActiveImportDateFolder, $script:ActiveRawDateFolder, $script:ActiveDateFolder)
    foreach ($b in $bases) {
        if ([string]::IsNullOrWhiteSpace($b)) { continue }
        $cand = if ([string]::IsNullOrWhiteSpace($cleanRel)) { $b } else { Join-Path $b $cleanRel }
        if (Test-Path -LiteralPath $cand -PathType Container) {
            return $cand
        }
    }
    $anchor = Get-ActiveAnchorFolder
    if ([string]::IsNullOrWhiteSpace($anchor)) { return "" }
    return $(if ([string]::IsNullOrWhiteSpace($cleanRel)) { $anchor } else { Join-Path $anchor $cleanRel })
}

function Get-PairedDirsForActiveSubPath {
    param(
        [string]$SubFolderPath = "",
        [string]$RelSubPath = ""
    )
    $rel = if (-not [string]::IsNullOrWhiteSpace($RelSubPath)) {
        $RelSubPath.Trim().Trim('\')
    } else {
        Get-RelativeSubPathFromActiveRoots -FolderPath $SubFolderPath
    }

    $list = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($SubFolderPath)) {
        $ns = $SubFolderPath.Trim().TrimEnd('\')
        if (-not $list.Contains($ns)) { [void]$list.Add($ns) }
    }

    foreach ($base in @($script:ActiveDevDateFolder, $script:ActiveImportDateFolder, $script:ActiveRawDateFolder, $script:ActiveDateFolder)) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        $cand = if ([string]::IsNullOrWhiteSpace($rel)) { $base.Trim().TrimEnd('\') } else { Join-Path ($base.Trim().TrimEnd('\')) $rel }
        if (-not $list.Contains($cand)) { [void]$list.Add($cand) }
    }

    if (-not [string]::IsNullOrWhiteSpace($script:ActiveDateName)) {
        foreach ($root in @([string]$Config.DevelopedRoot, [string]$Config.ImportRoot1, [string]$Config.ImportRoot2, [string]$Config.RawSaveRoot)) {
            if ([string]::IsNullOrWhiteSpace($root)) { continue }
            $candDate = Join-Path ($root.Trim().TrimEnd('\')) $script:ActiveDateName
            $candFull = if ([string]::IsNullOrWhiteSpace($rel)) { $candDate } else { Join-Path $candDate $rel }
            if (-not $list.Contains($candFull)) { [void]$list.Add($candFull) }
        }
    }
    return @($list)
}

function Find-ExistingPhotoInfoTxt {
    param(
        [string]$FolderPath = "",
        [string]$RelSubPath = ""
    )
    $bestPath = ""
    $bestTime = [datetime]::MinValue
    foreach ($dir in @(Get-PairedDirsForActiveSubPath -SubFolderPath $FolderPath -RelSubPath $RelSubPath)) {
        if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($fn in @("写真情報.txt", "info.txt")) {
            $fp = Join-Path $dir $fn
            if (Test-Path -LiteralPath $fp) {
                $fi = Get-Item -LiteralPath $fp -ErrorAction SilentlyContinue
                if ($null -ne $fi -and $fi.LastWriteTime -ge $bestTime) {
                    $bestTime = $fi.LastWriteTime
                    $bestPath = $fp
                }
            }
        }
    }
    return $bestPath
}

function Find-ExistingSceneInDirs {
    param(
        [string]$FolderPath = "",
        [string]$RelSubPath = ""
    )
    foreach ($dir in @(Get-PairedDirsForActiveSubPath -SubFolderPath $FolderPath -RelSubPath $RelSubPath)) {
        if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) { continue }
        $parsed = Read-SceneFileRaw -DirPath $dir
        if ($null -ne $parsed -and -not [string]::IsNullOrWhiteSpace([string]$parsed.SceneName)) {
            return $parsed
        }
    }
    return $null
}

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "PhotoTools 日次ワークフロー (取込元・現像後 日付紐づけ / scene.txt設定 / Step1～5)"
$Form.Size = New-Object System.Drawing.Size(920, 810)
$Form.MinimumSize = New-Object System.Drawing.Size(880, 740)
$Form.StartPosition = "CenterScreen"
$Form.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5)
$Form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 250)

$ToolTip = New-Object System.Windows.Forms.ToolTip

$LblDateCaption = New-Object System.Windows.Forms.Label
$LblDateCaption.Text = "対象日付:"
$LblDateCaption.Location = New-Object System.Drawing.Point(16, 12)
$LblDateCaption.Size = New-Object System.Drawing.Size(72, 22)
$LblDateCaption.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
$Form.Controls.Add($LblDateCaption)

$LblDateSummary = New-Object System.Windows.Forms.Label
$LblDateSummary.Location = New-Object System.Drawing.Point(92, 12)
$LblDateSummary.Size = New-Object System.Drawing.Size(634, 22)
$LblDateSummary.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
$LblDateSummary.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
$Form.Controls.Add($LblDateSummary)

$BtnRefresh = New-Object System.Windows.Forms.Button
$BtnRefresh.Text = "一覧更新"
$BtnRefresh.Location = New-Object System.Drawing.Point(736, 9)
$BtnRefresh.Size = New-Object System.Drawing.Size(150, 27)
$Form.Controls.Add($BtnRefresh)

$LblImportFolder = New-Object System.Windows.Forms.Label
$LblImportFolder.Text = "カメラ取り込み元:"
$LblImportFolder.Location = New-Object System.Drawing.Point(16, 44)
$LblImportFolder.Size = New-Object System.Drawing.Size(118, 22)
$Form.Controls.Add($LblImportFolder)

$TxtImportFolder = New-Object System.Windows.Forms.TextBox
$TxtImportFolder.Location = New-Object System.Drawing.Point(138, 41)
$TxtImportFolder.Size = New-Object System.Drawing.Size(748, 25)
$TxtImportFolder.ReadOnly = $true
$TxtImportFolder.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($TxtImportFolder)

$LblRawFolder = New-Object System.Windows.Forms.Label
$LblRawFolder.Text = "RAWフォルダ:"
$LblRawFolder.Location = New-Object System.Drawing.Point(16, 76)
$LblRawFolder.Size = New-Object System.Drawing.Size(118, 22)
$Form.Controls.Add($LblRawFolder)

$TxtRawFolder = New-Object System.Windows.Forms.TextBox
$TxtRawFolder.Location = New-Object System.Drawing.Point(138, 73)
$TxtRawFolder.Size = New-Object System.Drawing.Size(748, 25)
$TxtRawFolder.ReadOnly = $true
$TxtRawFolder.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($TxtRawFolder)

$LblDevFolder = New-Object System.Windows.Forms.Label
$LblDevFolder.Text = "現像後フォルダ:"
$LblDevFolder.Location = New-Object System.Drawing.Point(16, 108)
$LblDevFolder.Size = New-Object System.Drawing.Size(118, 22)
$Form.Controls.Add($LblDevFolder)

$TxtDevFolder = New-Object System.Windows.Forms.TextBox
$TxtDevFolder.Location = New-Object System.Drawing.Point(138, 105)
$TxtDevFolder.Size = New-Object System.Drawing.Size(748, 25)
$TxtDevFolder.ReadOnly = $true
$TxtDevFolder.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($TxtDevFolder)

$LblRouteBadge = New-Object System.Windows.Forms.Label
$LblRouteBadge.Location = New-Object System.Drawing.Point(138, 134)
$LblRouteBadge.Size = New-Object System.Drawing.Size(748, 20)
$LblRouteBadge.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9, [System.Drawing.FontStyle]::Bold)
$Form.Controls.Add($LblRouteBadge)

$GrpScene = New-Object System.Windows.Forms.GroupBox
$GrpScene.Text = "scene.txt 配置・イベント / 併せ / スタジオ / 場所 登録"
$GrpScene.Location = New-Object System.Drawing.Point(16, 158)
$GrpScene.Size = New-Object System.Drawing.Size(870, 108)
$Form.Controls.Add($GrpScene)

$LblSceneMode = New-Object System.Windows.Forms.Label
$LblSceneMode.Text = "置き場:"
$LblSceneMode.Location = New-Object System.Drawing.Point(14, 26)
$LblSceneMode.Size = New-Object System.Drawing.Size(52, 22)
$GrpScene.Controls.Add($LblSceneMode)

$RdoPatternA = New-Object System.Windows.Forms.RadioButton
$RdoPatternA.Text = "日付フォルダ直下 (通常：1日1件)"
$RdoPatternA.Location = New-Object System.Drawing.Point(68, 24)
$RdoPatternA.Size = New-Object System.Drawing.Size(222, 24)
$RdoPatternA.Checked = $true
$GrpScene.Controls.Add($RdoPatternA)

$RdoPatternB = New-Object System.Windows.Forms.RadioButton
$RdoPatternB.Text = "子フォルダ直下 (1日2件以上)"
$RdoPatternB.Location = New-Object System.Drawing.Point(296, 24)
$RdoPatternB.Size = New-Object System.Drawing.Size(204, 24)
$GrpScene.Controls.Add($RdoPatternB)

$LblPatternTarget = New-Object System.Windows.Forms.Label
$LblPatternTarget.Location = New-Object System.Drawing.Point(506, 26)
$LblPatternTarget.Size = New-Object System.Drawing.Size(236, 22)
$LblPatternTarget.ForeColor = [System.Drawing.Color]::DimGray
$LblPatternTarget.AutoEllipsis = $true
$GrpScene.Controls.Add($LblPatternTarget)

$BtnAddChildFolder = New-Object System.Windows.Forms.Button
$BtnAddChildFolder.Text = "＋子フォルダ作成"
$BtnAddChildFolder.Location = New-Object System.Drawing.Point(748, 22)
$BtnAddChildFolder.Size = New-Object System.Drawing.Size(108, 26)
$ToolTip.SetToolTip($BtnAddChildFolder, "現在の日付フォルダ直下に新しい子フォルダを作成します（1日2件以上の仕分け等に利用）")
$GrpScene.Controls.Add($BtnAddChildFolder)

$LblSceneCat = New-Object System.Windows.Forms.Label
$LblSceneCat.Text = "撮影区分:"
$LblSceneCat.Location = New-Object System.Drawing.Point(14, 64)
$LblSceneCat.Size = New-Object System.Drawing.Size(68, 22)
$GrpScene.Controls.Add($LblSceneCat)

$CmbSceneCat = New-Object System.Windows.Forms.ComboBox
$CmbSceneCat.Location = New-Object System.Drawing.Point(84, 61)
$CmbSceneCat.Size = New-Object System.Drawing.Size(112, 25)
$CmbSceneCat.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$CmbSceneCat.Items.AddRange(@("イベント", "個撮", "併せ", "その他"))
$CmbSceneCat.SelectedIndex = 0
$GrpScene.Controls.Add($CmbSceneCat)

$LblSceneName = New-Object System.Windows.Forms.Label
$LblSceneName.Text = "イベント名:"
$LblSceneName.Location = New-Object System.Drawing.Point(206, 64)
$LblSceneName.Size = New-Object System.Drawing.Size(80, 22)
$GrpScene.Controls.Add($LblSceneName)

$CmbSceneName = New-Object System.Windows.Forms.ComboBox
$CmbSceneName.Location = New-Object System.Drawing.Point(290, 61)
$CmbSceneName.Size = New-Object System.Drawing.Size(412, 25)
$CmbSceneName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
$GrpScene.Controls.Add($CmbSceneName)

$BtnSaveScene = New-Object System.Windows.Forms.Button
$BtnSaveScene.Text = "scene.txt を保存"
$BtnSaveScene.Location = New-Object System.Drawing.Point(712, 59)
$BtnSaveScene.Size = New-Object System.Drawing.Size(144, 29)
$BtnSaveScene.BackColor = [System.Drawing.Color]::FromArgb(15, 118, 110)
$BtnSaveScene.ForeColor = [System.Drawing.Color]::White
$BtnSaveScene.FlatStyle = "Flat"
$BtnSaveScene.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
$GrpScene.Controls.Add($BtnSaveScene)

$LblHeader = New-Object System.Windows.Forms.Label
$LblHeader.Text = "開いている日付以下の統合フォルダ構成（ダブルクリックで被写体プロパティを開く／1日1人の場合は日付フォルダ自体も設定可）"
$LblHeader.Location = New-Object System.Drawing.Point(16, 272)
$LblHeader.AutoSize = $true
$Form.Controls.Add($LblHeader)

$TreeFolders = New-Object System.Windows.Forms.TreeView
$TreeFolders.Location = New-Object System.Drawing.Point(16, 296)
$TreeFolders.Size = New-Object System.Drawing.Size(870, 214)
$TreeFolders.CheckBoxes = $false
$TreeFolders.FullRowSelect = $true
$TreeFolders.HideSelection = $false
$TreeFolders.ShowLines = $true
$TreeFolders.ShowPlusMinus = $true
$TreeFolders.ShowRootLines = $true
$TreeFolders.ItemHeight = 22
$TreeFolders.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($TreeFolders)

$BtnOpenEditor = New-Object System.Windows.Forms.Button
$BtnOpenEditor.Text = "被写体プロパティ"
$BtnOpenEditor.Location = New-Object System.Drawing.Point(16, 514)
$BtnOpenEditor.Size = New-Object System.Drawing.Size(155, 32)
$Form.Controls.Add($BtnOpenEditor)

$BtnGigaSend = New-Object System.Windows.Forms.Button
$BtnGigaSend.Text = "ギガファイル便で送る"
$BtnGigaSend.Location = New-Object System.Drawing.Point(177, 514)
$BtnGigaSend.Size = New-Object System.Drawing.Size(205, 32)
$BtnGigaSend.BackColor = [System.Drawing.Color]::FromArgb(26, 115, 232)
$BtnGigaSend.ForeColor = [System.Drawing.Color]::White
$BtnGigaSend.FlatStyle = "Flat"
$Form.Controls.Add($BtnGigaSend)

$BtnCreateMessage = New-Object System.Windows.Forms.Button
$BtnCreateMessage.Text = "メッセージ作成(まとめ可)"
$BtnCreateMessage.Location = New-Object System.Drawing.Point(388, 514)
$BtnCreateMessage.Size = New-Object System.Drawing.Size(182, 32)
$BtnCreateMessage.BackColor = [System.Drawing.Color]::FromArgb(15, 118, 110)
$BtnCreateMessage.ForeColor = [System.Drawing.Color]::White
$BtnCreateMessage.FlatStyle = "Flat"
$BtnCreateMessage.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
$ToolTip.SetToolTip($BtnCreateMessage, "選択フォルダのモデルと同一Xアカウントを含む同日フォルダをまとめて送付メッセージ作成します")
$Form.Controls.Add($BtnCreateMessage)

$BtnOpenExplorer = New-Object System.Windows.Forms.Button
$BtnOpenExplorer.Text = "フォルダを開く"
$BtnOpenExplorer.Location = New-Object System.Drawing.Point(576, 514)
$BtnOpenExplorer.Size = New-Object System.Drawing.Size(148, 32)
$Form.Controls.Add($BtnOpenExplorer)

$BtnRenameSubFolder = New-Object System.Windows.Forms.Button
$BtnRenameSubFolder.Text = "フォルダ名変更(3同期)"
$BtnRenameSubFolder.Location = New-Object System.Drawing.Point(730, 514)
$BtnRenameSubFolder.Size = New-Object System.Drawing.Size(156, 32)
$ToolTip.SetToolTip($BtnRenameSubFolder, "選択した子フォルダ名を取込元・現像後・RAWの3ルートおよびExcel台帳で一括変更・同期します")
$Form.Controls.Add($BtnRenameSubFolder)

$TreeCtxMenu = New-Object System.Windows.Forms.ContextMenuStrip
$MnuCtxRename = $TreeCtxMenu.Items.Add("子フォルダ名を変更（取込・現像後・RAW 3ルート一括同期）")
$MnuCtxEditor = $TreeCtxMenu.Items.Add("被写体プロパティを開く")
$MnuCtxMessage = $TreeCtxMenu.Items.Add("メッセージ作成（同一Xアカウントまとめ可）")
$TreeFolders.ContextMenuStrip = $TreeCtxMenu

$TxtWorkflowLog = New-Object System.Windows.Forms.TextBox
$TxtWorkflowLog.Location = New-Object System.Drawing.Point(16, 594)
$TxtWorkflowLog.Size = New-Object System.Drawing.Size(870, 156)
$TxtWorkflowLog.Multiline = $true
$TxtWorkflowLog.ReadOnly = $true
$TxtWorkflowLog.ScrollBars = "Vertical"
$TxtWorkflowLog.BackColor = [System.Drawing.Color]::White
$TxtWorkflowLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$Form.Controls.Add($TxtWorkflowLog)

$EditorWatchTimer = New-Object System.Windows.Forms.Timer
$EditorWatchTimer.Interval = 800

function Append-WfLog {
    param([string]$Msg)
    $ts = (Get-Date).ToString("HH:mm:ss")
    $TxtWorkflowLog.AppendText("[$ts] $Msg`r`n")
    Write-LogInfo -ModuleName "DailyWorkflow" -Message $Msg | Out-Null
}

function Update-SceneCategoryLabel {
    switch ([string]$CmbSceneCat.SelectedItem) {
        "イベント" { $LblSceneName.Text = "イベント名:" }
        "個撮"     { $LblSceneName.Text = "スタジオ名:" }
        "併せ"     { $LblSceneName.Text = "併せ名:" }
        "その他"   { $LblSceneName.Text = "場所:" }
        default    { $LblSceneName.Text = "イベント名:" }
    }
}
$CmbSceneCat.Add_SelectedIndexChanged({ Update-SceneCategoryLabel })

function Load-SceneHistoryToCombo {
    $curText = $CmbSceneName.Text
    $CmbSceneName.Items.Clear()
    if (Get-Command Get-SceneHistoryData -ErrorAction SilentlyContinue) {
        $hist = Get-SceneHistoryData -HistoryPath ([string]$Config.SceneHistoryPath) -Config $Config
        if ($null -ne $hist) {
            foreach ($s in @($hist.Scenes)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$s)) {
                    [void]$CmbSceneName.Items.Add([string]$s)
                }
            }
        }
    }
    $CmbSceneName.Text = $curText
}

function Get-MergedChildDirNames {
    param([string]$RelParent = "")
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($baseRoot in @($script:ActiveDevDateFolder, $script:ActiveImportDateFolder, $script:ActiveRawDateFolder)) {
        if ([string]::IsNullOrWhiteSpace($baseRoot)) { continue }
        $scanDir = if ([string]::IsNullOrWhiteSpace($RelParent)) { $baseRoot } else { Join-Path $baseRoot $RelParent }
        if (-not (Test-Path -LiteralPath $scanDir -PathType Container)) { continue }
        foreach ($sd in @(Get-ChildItem -LiteralPath $scanDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
            if ($seen.Add($sd.Name)) {
                [void]$names.Add($sd.Name)
            }
        }
    }
    $arr = @($names | Sort-Object)
    return ,$arr
}

function Get-PatternBTargetChildRel {
    if (-not [string]::IsNullOrWhiteSpace($script:SelectedChildSceneRoot)) {
        $rel = Get-RelativeSubPathFromActiveRoots -FolderPath $script:SelectedChildSceneRoot
        if (-not [string]::IsNullOrWhiteSpace($rel)) {
            $topName = ($rel -split '\\')[0]
            if (-not [string]::IsNullOrWhiteSpace($topName)) { return $topName }
        }
        return [System.IO.Path]::GetFileName($script:SelectedChildSceneRoot)
    }
    $topNames = Get-MergedChildDirNames -RelParent ""
    if (@($topNames).Count -gt 0) {
        return [string]$topNames[0]
    }
    return ""
}

function Load-SceneInputsForTarget {
    param([string]$RelSubPath = "")
    $script:IsUpdatingSceneUI = $true
    try {
        $sc = Find-ExistingSceneInDirs -RelSubPath $RelSubPath
        if ($null -ne $sc) {
            if (-not [string]::IsNullOrWhiteSpace([string]$sc.Category) -and $CmbSceneCat.Items.Contains([string]$sc.Category)) {
                $CmbSceneCat.SelectedItem = [string]$sc.Category
            } else {
                $CmbSceneCat.SelectedIndex = 0
            }
            Update-SceneCategoryLabel
            $CmbSceneName.Text = [string]$sc.SceneName
        } else {
            $CmbSceneName.Text = ""
        }
    } finally {
        $script:IsUpdatingSceneUI = $false
    }
}

function Update-SceneModeUI {
    param([switch]$ReloadContent)
    if ($RdoPatternA.Checked) {
        $dateLeaf = if ([string]::IsNullOrWhiteSpace($script:ActiveDateName)) { "(日付)" } else { $script:ActiveDateName }
        $LblPatternTarget.Text = "配置先: $dateLeaf\scene.txt"
        $LblPatternTarget.ForeColor = [System.Drawing.Color]::FromArgb(3, 105, 161)
        if ($ReloadContent) {
            Load-SceneInputsForTarget -RelSubPath ""
        }
    } else {
        $childRel = Get-PatternBTargetChildRel
        if (-not [string]::IsNullOrWhiteSpace($childRel)) {
            $script:SelectedChildSceneRoot = Resolve-PreferredSubFolderPath -RelSubPath $childRel
            $LblPatternTarget.Text = "配置先: $childRel\scene.txt"
            $LblPatternTarget.ForeColor = [System.Drawing.Color]::FromArgb(180, 83, 9)
            if ($ReloadContent) {
                Load-SceneInputsForTarget -RelSubPath $childRel
            }
        } else {
            $LblPatternTarget.Text = "配置先: (子フォルダを選択または作成)"
            $LblPatternTarget.ForeColor = [System.Drawing.Color]::Crimson
            if ($ReloadContent) {
                Load-SceneInputsForTarget -RelSubPath ""
            }
        }
    }
}

$RdoPatternA.Add_CheckedChanged({
    if ($script:IsUpdatingSceneUI -or (-not $RdoPatternA.Checked)) { return }
    Update-SceneModeUI -ReloadContent
})
$RdoPatternB.Add_CheckedChanged({
    if ($script:IsUpdatingSceneUI -or (-not $RdoPatternB.Checked)) { return }
    Update-SceneModeUI -ReloadContent
})

function Detect-AndLoadSceneSettings {
    $childNames = Get-MergedChildDirNames -RelParent ""
    $foundChildRel = ""
    foreach ($cn in @($childNames)) {
        $sc = Find-ExistingSceneInDirs -RelSubPath $cn
        if ($null -ne $sc) {
            $foundChildRel = $cn
            break
        }
    }
    $foundDateScene = Find-ExistingSceneInDirs -RelSubPath ""

    $script:IsUpdatingSceneUI = $true
    try {
        if (-not [string]::IsNullOrWhiteSpace($foundChildRel) -and ($null -eq $foundDateScene)) {
            $script:SelectedChildSceneRoot = Resolve-PreferredSubFolderPath -RelSubPath $foundChildRel
            $RdoPatternB.Checked = $true
            $RdoPatternA.Checked = $false
        } else {
            $RdoPatternA.Checked = $true
            $RdoPatternB.Checked = $false
        }
    } finally {
        $script:IsUpdatingSceneUI = $false
    }
    Update-SceneModeUI -ReloadContent
}

function Add-SubFolderTreeNodes {
    param(
        [System.Windows.Forms.TreeNode]$ParentNode,
        [string]$RelParent,
        [int]$Depth,
        [string]$TopChildRel,
        [hashtable]$NodeByRel
    )
    $childNames = Get-MergedChildDirNames -RelParent $RelParent
    foreach ($name in @($childNames)) {
        $curRel = if ([string]::IsNullOrWhiteSpace($RelParent)) { $name } else { Join-Path $RelParent $name }
        $curTopChildRel = if ($Depth -eq 1) { $name } else { $TopChildRel }
        $prefDir = Resolve-PreferredSubFolderPath -RelSubPath $curRel

        $hasDev = (-not [string]::IsNullOrWhiteSpace($script:ActiveDevDateFolder)) -and (Test-Path -LiteralPath (Join-Path $script:ActiveDevDateFolder $curRel) -PathType Container)
        $hasImp = (-not [string]::IsNullOrWhiteSpace($script:ActiveImportDateFolder)) -and (Test-Path -LiteralPath (Join-Path $script:ActiveImportDateFolder $curRel) -PathType Container)
        $locTag = if ($hasDev -and -not $hasImp) { " [現像のみ]" }
                  elseif ($hasImp -and -not $hasDev) { " [取込のみ]" }
                  else { "" }

        $txtFile = Find-ExistingPhotoInfoTxt -RelSubPath $curRel
        $nodeText = "$name$locTag"
        $nodeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
        $personEntries = @()
        $sentLabel = ""

        if (-not [string]::IsNullOrWhiteSpace($txtFile)) {
            $info = Read-PhotoInfoTxt -FolderPath $prefDir -FilePath $txtFile -Config $Config
            $sentLabel = if ($info.IsSent -or $info.SentStatus -eq "送付済み" -or $info.SentStatus -eq "送付済") { "送付済み" } else { "未送付" }
            $rawPersons = @($info.Persons)
            if (@($rawPersons).Count -ge 2) {
                $nodeText = "${name}${locTag}  |  複数人 ($(@($rawPersons).Count)名)  |  $sentLabel"
                $nodeColor = if ($sentLabel -eq "送付済み") { [System.Drawing.Color]::FromArgb(4, 120, 87) } else { [System.Drawing.Color]::FromArgb(180, 83, 9) }
                for ($pi = 0; $pi -lt @($rawPersons).Count; $pi++) {
                    $p = $rawPersons[$pi]
                    $pn = if ([string]::IsNullOrWhiteSpace([string]$p["Name"])) { "(名前未入力)" } else { [string]$p["Name"] }
                    $pc = if ([string]::IsNullOrWhiteSpace([string]$p["CostumeOrChar"])) { "(キャラ未入力)" } else { [string]$p["CostumeOrChar"] }
                    $personEntries += ("{0}人目: {1} / {2}  |  {3}" -f ($pi + 1), $pn, $pc, $sentLabel)
                }
            } else {
                $p0 = if (@($rawPersons).Count -gt 0) { $rawPersons[0] } else { @{ Name = ""; CostumeOrChar = "" } }
                $pn = if ([string]::IsNullOrWhiteSpace([string]$p0["Name"])) { "(名前未入力)" } else { [string]$p0["Name"] }
                $pc = if ([string]::IsNullOrWhiteSpace([string]$p0["CostumeOrChar"])) { "(キャラ未入力)" } else { [string]$p0["CostumeOrChar"] }
                $nodeText = "${name}${locTag}  |  $pn / $pc  |  $sentLabel"
                $nodeColor = if ($sentLabel -eq "送付済み") { [System.Drawing.Color]::FromArgb(4, 120, 87) } else { [System.Drawing.Color]::FromArgb(180, 83, 9) }
            }
        } elseif ($Depth -eq 1) {
            $childScene = Find-ExistingSceneInDirs -RelSubPath $curRel
            if ($null -ne $childScene) {
                $nodeText = "${name}${locTag}  [scene: $($childScene.SceneName)]"
                $nodeColor = [System.Drawing.Color]::FromArgb(3, 105, 161)
            }
        }

        $node = New-Object System.Windows.Forms.TreeNode($nodeText)
        $node.ForeColor = $nodeColor
        $node.Tag = @{
            FolderPath     = $prefDir
            RelSubPath     = $curRel
            ChildSceneRoot = (Resolve-PreferredSubFolderPath -RelSubPath $curTopChildRel)
            IsDateRoot     = $false
            IsPersonNode   = $false
        }
        [void]$ParentNode.Nodes.Add($node)
        $NodeByRel[$curRel.ToLowerInvariant()] = $node

        foreach ($peText in $personEntries) {
            $pNode = New-Object System.Windows.Forms.TreeNode($peText)
            $pNode.ForeColor = if ($sentLabel -eq "送付済み") { [System.Drawing.Color]::FromArgb(4, 120, 87) } else { [System.Drawing.Color]::FromArgb(71, 85, 105) }
            $pNode.Tag = @{
                FolderPath     = $prefDir
                RelSubPath     = $curRel
                ChildSceneRoot = (Resolve-PreferredSubFolderPath -RelSubPath $curTopChildRel)
                IsDateRoot     = $false
                IsPersonNode   = $true
            }
            [void]$node.Nodes.Add($pNode)
        }

        Add-SubFolderTreeNodes -ParentNode $node -RelParent $curRel -Depth ($Depth + 1) -TopChildRel $curTopChildRel -NodeByRel $NodeByRel
    }
}

function Update-FolderTree {
    param(
        [string]$PreferredSelectRel = "",
        [string]$PreferredSelectPath = ""
    )
    $prevRel = $PreferredSelectRel
    if ([string]::IsNullOrWhiteSpace($prevRel) -and -not [string]::IsNullOrWhiteSpace($PreferredSelectPath)) {
        $prevRel = Get-RelativeSubPathFromActiveRoots -FolderPath $PreferredSelectPath
    }
    if ([string]::IsNullOrWhiteSpace($prevRel) -and $null -ne $TreeFolders.SelectedNode -and $null -ne $TreeFolders.SelectedNode.Tag) {
        $prevRel = [string]$TreeFolders.SelectedNode.Tag.RelSubPath
    }

    $TreeFolders.BeginUpdate()
    try {
        $TreeFolders.Nodes.Clear()
        if ([string]::IsNullOrWhiteSpace($script:ActiveDateName)) { return }

        $dateScene = Find-ExistingSceneInDirs -RelSubPath ""
        $hasAnyRoot = (-not [string]::IsNullOrWhiteSpace($script:ActiveImportDateFolder) -and (Test-Path -LiteralPath $script:ActiveImportDateFolder)) -or
                      (-not [string]::IsNullOrWhiteSpace($script:ActiveDevDateFolder) -and (Test-Path -LiteralPath $script:ActiveDevDateFolder))
        $rootBaseLabel = if ($null -ne $dateScene) {
            "$($script:ActiveDateName)  [scene: $($dateScene.Category) / $($dateScene.SceneName)]"
        } elseif (-not $hasAnyRoot) {
            "$($script:ActiveDateName)  (未作成フォルダ：取込元側でStep1実行またはフォルダ作成してください)"
        } else {
            $script:ActiveDateName
        }

        $rootText = $rootBaseLabel
        $rootColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
        $rootPersonEntries = @()
        $rootSentLabel = ""
        $rootTxtFile = Find-ExistingPhotoInfoTxt -RelSubPath ""
        $rootPrefDir = Resolve-PreferredSubFolderPath -RelSubPath ""
        if (-not [string]::IsNullOrWhiteSpace($rootTxtFile)) {
            $rootInfo = Read-PhotoInfoTxt -FolderPath $rootPrefDir -FilePath $rootTxtFile -Config $Config
            $rootSentLabel = if ($rootInfo.IsSent -or $rootInfo.SentStatus -eq "送付済み" -or $rootInfo.SentStatus -eq "送付済") { "送付済み" } else { "未送付" }
            $rootPersons = @($rootInfo.Persons)
            if (@($rootPersons).Count -ge 2) {
                $rootText = "${rootBaseLabel}  |  複数人 ($(@($rootPersons).Count)名)  |  $rootSentLabel"
                $rootColor = if ($rootSentLabel -eq "送付済み") { [System.Drawing.Color]::FromArgb(4, 120, 87) } else { [System.Drawing.Color]::FromArgb(180, 83, 9) }
                for ($pi = 0; $pi -lt @($rootPersons).Count; $pi++) {
                    $p = $rootPersons[$pi]
                    $pn = if ([string]::IsNullOrWhiteSpace([string]$p["Name"])) { "(名前未入力)" } else { [string]$p["Name"] }
                    $pc = if ([string]::IsNullOrWhiteSpace([string]$p["CostumeOrChar"])) { "(キャラ未入力)" } else { [string]$p["CostumeOrChar"] }
                    $rootPersonEntries += ("{0}人目: {1} / {2}  |  {3}" -f ($pi + 1), $pn, $pc, $rootSentLabel)
                }
            } else {
                $p0 = if (@($rootPersons).Count -gt 0) { $rootPersons[0] } else { @{ Name = ""; CostumeOrChar = "" } }
                $pn = if ([string]::IsNullOrWhiteSpace([string]$p0["Name"])) { "(名前未入力)" } else { [string]$p0["Name"] }
                $pc = if ([string]::IsNullOrWhiteSpace([string]$p0["CostumeOrChar"])) { "(キャラ未入力)" } else { [string]$p0["CostumeOrChar"] }
                $rootText = "${rootBaseLabel}  |  $pn / $pc  |  $rootSentLabel"
                $rootColor = if ($rootSentLabel -eq "送付済み") { [System.Drawing.Color]::FromArgb(4, 120, 87) } else { [System.Drawing.Color]::FromArgb(180, 83, 9) }
            }
        }

        $rootNode = New-Object System.Windows.Forms.TreeNode($rootText)
        $rootNode.ForeColor = $rootColor
        $rootNode.NodeFont = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
        $rootNode.Tag = @{
            FolderPath     = (Get-ActiveAnchorFolder)
            RelSubPath     = ""
            ChildSceneRoot = ""
            IsDateRoot     = $true
            IsPersonNode   = $false
        }
        [void]$TreeFolders.Nodes.Add($rootNode)

        foreach ($peText in $rootPersonEntries) {
            $pNode = New-Object System.Windows.Forms.TreeNode($peText)
            $pNode.ForeColor = if ($rootSentLabel -eq "送付済み") { [System.Drawing.Color]::FromArgb(4, 120, 87) } else { [System.Drawing.Color]::FromArgb(71, 85, 105) }
            $pNode.Tag = @{
                FolderPath     = (Get-ActiveAnchorFolder)
                RelSubPath     = ""
                ChildSceneRoot = ""
                IsDateRoot     = $true
                IsPersonNode   = $true
            }
            [void]$rootNode.Nodes.Add($pNode)
        }

        $nodeByRel = @{}
        $nodeByRel[""] = $rootNode
        Add-SubFolderTreeNodes -ParentNode $rootNode -RelParent "" -Depth 1 -TopChildRel "" -NodeByRel $nodeByRel
        $TreeFolders.ExpandAll()

        $relKey = if ($null -eq $prevRel) { "" } else { $prevRel.ToLowerInvariant() }
        if ($nodeByRel.ContainsKey($relKey)) {
            $TreeFolders.SelectedNode = $nodeByRel[$relKey]
        } else {
            $TreeFolders.SelectedNode = $rootNode
        }
    } finally {
        $TreeFolders.EndUpdate()
    }
}

function Refresh-LinkedFoldersUIState {
    $hasImport = (-not [string]::IsNullOrWhiteSpace($script:ActiveImportDateFolder)) -and (Test-Path -LiteralPath $script:ActiveImportDateFolder -PathType Container)
    $hasDev    = (-not [string]::IsNullOrWhiteSpace($script:ActiveDevDateFolder)) -and (Test-Path -LiteralPath $script:ActiveDevDateFolder -PathType Container)
    $hasRaw    = (-not [string]::IsNullOrWhiteSpace($script:ActiveRawDateFolder)) -and (Test-Path -LiteralPath $script:ActiveRawDateFolder -PathType Container)

    $keyNote = if ([string]::IsNullOrWhiteSpace($script:ActiveDateKey)) { "" } else { " (日付キー: $($script:ActiveDateKey))" }
    $impTag  = if ($hasImport) { "取込データ: あり" } else { "取込データ: なし(削減済)" }
    $rawTag  = if ($hasRaw)    { "RAWデータ: あり" } else { "RAWデータ: なし(削減済)" }
    $devTag  = if ($hasDev)    { "現像後: あり" } else { "現像後: なし" }
    $LblDateSummary.Text = "$($script:ActiveDateName)${keyNote}   [$impTag / $rawTag / $devTag]"

    if ($hasImport) {
        $TxtImportFolder.Text = $script:ActiveImportDateFolder
        $TxtImportFolder.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
        $TxtImportFolder.BackColor = [System.Drawing.Color]::White
    } else {
        $TxtImportFolder.Text = "(なし / データ削減済みまたは未作成)"
        $TxtImportFolder.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
        $TxtImportFolder.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
    }

    if ($hasDev) {
        $TxtDevFolder.Text = $script:ActiveDevDateFolder
        $TxtDevFolder.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
        $TxtDevFolder.BackColor = [System.Drawing.Color]::White
    } else {
        $TxtDevFolder.Text = "(なし / 現像前または未作成)"
        $TxtDevFolder.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
        $TxtDevFolder.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
    }

    if ($hasRaw) {
        $TxtRawFolder.Text = $script:ActiveRawDateFolder
        $TxtRawFolder.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
        $TxtRawFolder.BackColor = [System.Drawing.Color]::White
    } else {
        $TxtRawFolder.Text = "(なし / RAWデータ削減済みまたは未検出)"
        $TxtRawFolder.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
        $TxtRawFolder.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
    }

    if ($hasImport -and $hasDev) {
        $LblRouteBadge.Text = "日付紐づけ連携中：取り込み元・現像後ともに参照可（Step1～5 利用可）"
        $LblRouteBadge.ForeColor = [System.Drawing.Color]::FromArgb(3, 105, 161)
    } elseif ($hasImport -and -not $hasDev) {
        $LblRouteBadge.Text = "取り込み元のみ存在（現像後は未作成：Step1・Step2 で現像後フォルダ構成を作成可能）"
        $LblRouteBadge.ForeColor = [System.Drawing.Color]::FromArgb(3, 105, 161)
    } elseif (-not $hasImport -and $hasDev) {
        $LblRouteBadge.Text = "データ削減状態（取込/RAW なし）：現像後フォルダ基準で編集・一覧・アーカイブ可能（Step2・Step4 は無効）"
        $LblRouteBadge.ForeColor = [System.Drawing.Color]::FromArgb(4, 120, 87)
    } else {
        $LblRouteBadge.Text = "対象フォルダが未作成です（カメラ取り込み元または現像後フォルダを選択してください）"
        $LblRouteBadge.ForeColor = [System.Drawing.Color]::FromArgb(180, 83, 9)
    }

    if ($script:StepButtons.ContainsKey(1)) { $script:StepButtons[1].Enabled = $hasImport -or (-not [string]::IsNullOrWhiteSpace([string]$Config.ImportRoot1)) }
    if ($script:StepButtons.ContainsKey(2)) { $script:StepButtons[2].Enabled = $hasImport }
    if ($script:StepButtons.ContainsKey(3)) { $script:StepButtons[3].Enabled = $hasDev }
    if ($script:StepButtons.ContainsKey(4)) { $script:StepButtons[4].Enabled = $hasImport }
    if ($script:StepButtons.ContainsKey(5)) { $script:StepButtons[5].Enabled = ($hasDev -or $hasRaw) }
}

function Set-ActiveLinkedFolders {
    param(
        [string]$BaseFolderPath = "",
        [string]$ExplicitImportDateDir = "",
        [string]$ExplicitDevDateDir = "",
        [string]$SelectChildRel = "",
        [string]$SelectChildPath = ""
    )

    $anchorInput = if (-not [string]::IsNullOrWhiteSpace($BaseFolderPath)) { $BaseFolderPath }
                   elseif (-not [string]::IsNullOrWhiteSpace($ExplicitDevDateDir)) { $ExplicitDevDateDir }
                   else { $ExplicitImportDateDir }
    if ([string]::IsNullOrWhiteSpace($anchorInput)) { return }

    $resolved = Resolve-DateFolderFromTarget -InputPath $anchorInput
    $dateName = [string]$resolved.DateFolderName
    $dateKey  = [string]$resolved.DateKey
    $normDate = ([string]$resolved.DateFolder).Trim().TrimEnd('\')

    $prevKey = $script:ActiveDateKey
    $sameDateAsBefore = (-not [string]::IsNullOrWhiteSpace($dateKey)) -and ($dateKey -eq $prevKey)

    $script:ActiveDateName   = $dateName
    $script:ActiveDateKey    = $dateKey
    $script:ActiveDateFolder = $normDate
    $script:SelectedChildSceneRoot = ""

    # 1. カメラ取り込み元日付フォルダを日付で紐づけ解決
    if (-not [string]::IsNullOrWhiteSpace($ExplicitImportDateDir) -and (Test-Path -LiteralPath $ExplicitImportDateDir -PathType Container)) {
        $script:ActiveImportDateFolder = $ExplicitImportDateDir.Trim().TrimEnd('\')
    } elseif ($sameDateAsBefore -and -not [string]::IsNullOrWhiteSpace($script:ActiveImportDateFolder) -and (Test-Path -LiteralPath $script:ActiveImportDateFolder -PathType Container)) {
        # 同一日付内での現像後切り替え時は現在の取り込み元選択を保持
    } elseif ((Test-IsAllowedImportPath -Path $normDate) -and (Test-Path -LiteralPath $normDate -PathType Container)) {
        $script:ActiveImportDateFolder = $normDate
    } else {
        $foundImp = ""
        foreach ($ir in @([string]$Config.ImportRoot1, [string]$Config.ImportRoot2)) {
            $candImp = Find-DateFolderInBaseRoot -BaseRoot $ir -DateFolderName $dateName -DateKey $dateKey
            if (-not [string]::IsNullOrWhiteSpace($candImp)) { $foundImp = $candImp; break }
        }
        $script:ActiveImportDateFolder = $foundImp
    }

    # 2. 現像後日付フォルダを日付で紐づけ解決
    if (-not [string]::IsNullOrWhiteSpace($ExplicitDevDateDir) -and (Test-Path -LiteralPath $ExplicitDevDateDir -PathType Container)) {
        $script:ActiveDevDateFolder = $ExplicitDevDateDir.Trim().TrimEnd('\')
    } elseif ($sameDateAsBefore -and -not [string]::IsNullOrWhiteSpace($script:ActiveDevDateFolder) -and (Test-Path -LiteralPath $script:ActiveDevDateFolder -PathType Container)) {
        # 同一日付内での取り込み元切り替え時は現在の現像後選択を保持
    } elseif ((Test-IsSameOrSubPath -Path $normDate -BaseRoot ([string]$Config.DevelopedRoot)) -and (Test-Path -LiteralPath $normDate -PathType Container)) {
        $script:ActiveDevDateFolder = $normDate
    } else {
        $script:ActiveDevDateFolder = Find-DateFolderInBaseRoot -BaseRoot ([string]$Config.DevelopedRoot) -DateFolderName $dateName -DateKey $dateKey
    }

    # 3. RAW保存日付フォルダを日付で紐づけ解決（現像後ルートに応じたRAW候補切替）
    $rawCandidates = New-Object System.Collections.Generic.List[string]
    $devCheckPath = if (-not [string]::IsNullOrWhiteSpace($ExplicitDevDateDir)) { $ExplicitDevDateDir } elseif (-not [string]::IsNullOrWhiteSpace($script:ActiveDevDateFolder)) { $script:ActiveDevDateFolder } else { [string]$Config.DevelopedRoot }
    $isArchiveDev = (Test-IsSameOrSubPath -Path $devCheckPath -BaseRoot "J:\写真2\現像後") -or
                    (-not [string]::IsNullOrWhiteSpace([string]$Config.DevelopedArchiveRoot) -and (Test-IsSameOrSubPath -Path $devCheckPath -BaseRoot ([string]$Config.DevelopedArchiveRoot))) -or
                    ($devCheckPath -like "*写真2*")
    if ($isArchiveDev) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Config.RawArchiveRoot)) { [void]$rawCandidates.Add([string]$Config.RawArchiveRoot) }
        [void]$rawCandidates.Add("L:\")
    } else {
        if (-not [string]::IsNullOrWhiteSpace([string]$Config.RawSaveRoot2)) { [void]$rawCandidates.Add([string]$Config.RawSaveRoot2) }
        [void]$rawCandidates.Add("H:\写真作業用\作業用RAW")
        if (-not [string]::IsNullOrWhiteSpace([string]$Config.RawSaveRoot)) { [void]$rawCandidates.Add([string]$Config.RawSaveRoot) }
        [void]$rawCandidates.Add("G:\写真raw")
    }

    $foundRaw = ""
    foreach ($rr in $rawCandidates) {
        if ([string]::IsNullOrWhiteSpace($rr)) { continue }
        $cand = Find-DateFolderInBaseRoot -BaseRoot $rr -DateFolderName $dateName -DateKey $dateKey
        if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path -LiteralPath $cand)) {
            $foundRaw = $cand
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($foundRaw)) {
        foreach ($rr in $rawCandidates) {
            if (-not [string]::IsNullOrWhiteSpace($rr)) {
                $subCand = Join-Path $rr $dateName
                if (Test-Path -LiteralPath $subCand) {
                    $foundRaw = $subCand
                    break
                }
            }
        }
    }
    $script:ActiveRawDateFolder = $foundRaw

    # いずれの既知ルート配下にも該当しない任意フォルダが直接開かれた場合のフォールバック
    if ([string]::IsNullOrWhiteSpace($script:ActiveImportDateFolder) -and [string]::IsNullOrWhiteSpace($script:ActiveDevDateFolder) -and (Test-Path -LiteralPath $normDate -PathType Container)) {
        $script:ActiveDevDateFolder = $normDate
    }

    # 日付名を実在フォルダ基準に正規化
    if (-not [string]::IsNullOrWhiteSpace($script:ActiveDevDateFolder)) {
        $script:ActiveDateName = [System.IO.Path]::GetFileName($script:ActiveDevDateFolder)
    } elseif (-not [string]::IsNullOrWhiteSpace($script:ActiveImportDateFolder)) {
        $script:ActiveDateName = [System.IO.Path]::GetFileName($script:ActiveImportDateFolder)
    }

    $selRel = if (-not [string]::IsNullOrWhiteSpace($SelectChildRel)) { $SelectChildRel }
              elseif (-not [string]::IsNullOrWhiteSpace($resolved.SelectedSubRel)) { [string]$resolved.SelectedSubRel }
              else { "" }

    Refresh-LinkedFoldersUIState
    Load-SceneHistoryToCombo
    Detect-AndLoadSceneSettings
    Update-FolderTree -PreferredSelectRel $selRel -PreferredSelectPath $SelectChildPath
}

function Set-ActiveFolder {
    param(
        [string]$NewFolderPath,
        [string]$SelectChildPath = ""
    )
    Set-ActiveLinkedFolders -BaseFolderPath $NewFolderPath -SelectChildPath $SelectChildPath
}

function Show-SimpleInputDialog {
    param([string]$Title, [string]$Prompt, [string]$DefaultValue = "")
    $d = New-Object System.Windows.Forms.Form
    $d.Text = $Title
    $d.Size = New-Object System.Drawing.Size(380, 155)
    $d.StartPosition = "CenterParent"
    $d.FormBorderStyle = "FixedDialog"
    $d.MaximizeBox = $false
    $d.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Prompt
    $lbl.Location = New-Object System.Drawing.Point(14, 14)
    $lbl.Size = New-Object System.Drawing.Size(340, 22)
    $d.Controls.Add($lbl)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Text = $DefaultValue
    $tb.Location = New-Object System.Drawing.Point(14, 42)
    $tb.Size = New-Object System.Drawing.Size(336, 25)
    $d.Controls.Add($tb)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "OK"
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Location = New-Object System.Drawing.Point(188, 78)
    $ok.Size = New-Object System.Drawing.Size(76, 28)
    $d.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "キャンセル"
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = New-Object System.Drawing.Point(272, 78)
    $cancel.Size = New-Object System.Drawing.Size(78, 28)
    $d.Controls.Add($cancel)
    $d.AcceptButton = $ok
    $d.CancelButton = $cancel

    if ($d.ShowDialog($Form) -eq [System.Windows.Forms.DialogResult]::OK) {
        return $tb.Text.Trim()
    }
    return $null
}

function Open-PhotoInfoEditorForPath {
    param([string]$TargetSubFolder)
    if ([string]::IsNullOrWhiteSpace($TargetSubFolder)) { return }
    $rel = Get-RelativeSubPathFromActiveRoots -FolderPath $TargetSubFolder
    $resolvedTarget = Resolve-PreferredSubFolderPath -RelSubPath $rel
    if ([string]::IsNullOrWhiteSpace($resolvedTarget) -or -not (Test-Path -LiteralPath $resolvedTarget -PathType Container)) {
        Show-MsgBox -Text "対象フォルダが見つかりません:`n$resolvedTarget`n`n先にフォルダを作成するか、Step1を実行してください。" -Title "フォルダ未作成" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
        return
    }
    $editorScript = Join-Path $RootDir "editor\PhotoInfoEditor.ps1"
    if (-not (Test-Path -LiteralPath $editorScript)) {
        Show-MsgBox -Text "PhotoInfoEditor.ps1 が見つかりません:`n$editorScript" -Title "エラー" -Buttons "OK" -Icon "Error" -Owner $Form | Out-Null
        return
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$editorScript`" -TargetPath `"$resolvedTarget`" -ForceEditor"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $proc = [System.Diagnostics.Process]::Start($psi)
    if ($null -ne $proc) {
        [void]$script:LaunchedEditorProcs.Add($proc)
        if (-not $EditorWatchTimer.Enabled) { $EditorWatchTimer.Start() }
    }
}

$EditorWatchTimer.Add_Tick({
    $changed = $false
    for ($i = $script:LaunchedEditorProcs.Count - 1; $i -ge 0; $i--) {
        $p = $script:LaunchedEditorProcs[$i]
        if ($null -eq $p -or $p.HasExited) {
            if ($null -ne $p) { $p.Dispose() }
            $script:LaunchedEditorProcs.RemoveAt($i)
            $changed = $true
        }
    }
    if ($changed) {
        Update-FolderTree
    }
    if ($script:LaunchedEditorProcs.Count -eq 0) {
        $EditorWatchTimer.Stop()
    }
})

$TreeFolders.Add_AfterSelect({
    param($sender, $e)
    if ($null -eq $e.Node -or $null -eq $e.Node.Tag) { return }
    $topChild = [string]$e.Node.Tag.ChildSceneRoot
    if (-not [string]::IsNullOrWhiteSpace($topChild)) {
        $script:SelectedChildSceneRoot = $topChild
        if ($RdoPatternB.Checked) {
            Update-SceneModeUI -ReloadContent
        }
    }
})

$TreeFolders.Add_NodeMouseDoubleClick({
    param($sender, $e)
    if ($null -eq $e.Node -or $null -eq $e.Node.Tag) { return }
    $targetDir = [string]$e.Node.Tag.FolderPath
    if (-not [string]::IsNullOrWhiteSpace($targetDir)) {
        Open-PhotoInfoEditorForPath -TargetSubFolder $targetDir
    }
})


# Browse buttons removed as requested.

function Get-DirFileStemSet {
    param([string]$DirPath)
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ([string]::IsNullOrWhiteSpace($DirPath) -or -not (Test-Path -LiteralPath $DirPath -PathType Container)) {
        return $set
    }
    foreach ($f in @(Get-ChildItem -LiteralPath $DirPath -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -ieq "写真情報.txt" -or $f.Name -ieq "scene.txt") { continue }
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        if (-not [string]::IsNullOrWhiteSpace($stem)) { [void]$set.Add($stem) }
    }
    return $set
}

function Invoke-SubFolderRenameThreeRoots {
    param(
        [Parameter(Mandatory=$true)][string]$OldRelSubPath,
        [Parameter(Mandatory=$true)][string]$NewLeafName
    )
    $parentRel = [System.IO.Path]::GetDirectoryName($OldRelSubPath)
    $newRel = if ([string]::IsNullOrWhiteSpace($parentRel)) { $NewLeafName } else { Join-Path $parentRel $NewLeafName }
    if ($OldRelSubPath -ieq $newRel) { return $false }

    $rootsInfo = @(
        @{ Label = "現像後"; Base = $script:ActiveDevDateFolder },
        @{ Label = "取込元"; Base = $script:ActiveImportDateFolder },
        @{ Label = "RAW";    Base = $script:ActiveRawDateFolder }
    )

    foreach ($ri in $rootsInfo) {
        if (-not [string]::IsNullOrWhiteSpace($ri.Base) -and (Test-Path -LiteralPath $ri.Base -PathType Container)) {
            $srcP = Join-Path $ri.Base $OldRelSubPath
            $dstP = Join-Path $ri.Base $newRel
            if ((Test-Path -LiteralPath $srcP -PathType Container) -and (Test-Path -LiteralPath $dstP -PathType Container) -and ($srcP -ine $dstP)) {
                Show-MsgBox -Text "$($ri.Label) ルート側に同名フォルダが既に存在するため変更できません:`n$dstP" -Title "重複エラー" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
                return $false
            }
        }
    }

    $oldImp = if (-not [string]::IsNullOrWhiteSpace($script:ActiveImportDateFolder)) { Join-Path $script:ActiveImportDateFolder $OldRelSubPath } else { "" }
    $newImp = if (-not [string]::IsNullOrWhiteSpace($script:ActiveImportDateFolder)) { Join-Path $script:ActiveImportDateFolder $newRel } else { "" }
    $oldDev = if (-not [string]::IsNullOrWhiteSpace($script:ActiveDevDateFolder))    { Join-Path $script:ActiveDevDateFolder $OldRelSubPath } else { "" }
    $newDev = if (-not [string]::IsNullOrWhiteSpace($script:ActiveDevDateFolder))    { Join-Path $script:ActiveDevDateFolder $newRel } else { "" }
    $oldRaw = if (-not [string]::IsNullOrWhiteSpace($script:ActiveRawDateFolder))    { Join-Path $script:ActiveRawDateFolder $OldRelSubPath } else { "" }
    $newRaw = if (-not [string]::IsNullOrWhiteSpace($script:ActiveRawDateFolder))    { Join-Path $script:ActiveRawDateFolder $newRel } else { "" }

    $renamedList = New-Object System.Collections.Generic.List[string]
    foreach ($ri in $rootsInfo) {
        if (-not [string]::IsNullOrWhiteSpace($ri.Base) -and (Test-Path -LiteralPath $ri.Base -PathType Container)) {
            $srcP = Join-Path $ri.Base $OldRelSubPath
            if (Test-Path -LiteralPath $srcP -PathType Container) {
                Rename-Item -LiteralPath $srcP -NewName $NewLeafName -Force -ErrorAction Stop
                [void]$renamedList.Add("$($ri.Label): $OldRelSubPath -> $newRel")
            }
        }
    }

    $ledgerUpdated = 0
    if (Get-Command Update-PhotoLedgerAfterSubFolderRename -ErrorAction SilentlyContinue) {
        $ledgerUpdated = Update-PhotoLedgerAfterSubFolderRename `
            -DateName $script:ActiveDateName `
            -OldRelSubPath $OldRelSubPath `
            -NewRelSubPath $newRel `
            -OldImportPath $oldImp `
            -NewImportPath $newImp `
            -OldDevPath $oldDev `
            -NewDevPath $newDev `
            -Config $Config
    }
    if (-not [string]::IsNullOrWhiteSpace($oldRaw) -and (Get-Command Update-PhotoLedgerPathsAfterMove -ErrorAction SilentlyContinue)) {
        [void](Update-PhotoLedgerPathsAfterMove -OldBasePath $oldRaw -NewBasePath $newRaw -ColumnType "RAW" -Config $Config)
    }

    $topChild = ($newRel -split '[\\/]')[0]
    $script:SelectedChildSceneRoot = Resolve-PreferredSubFolderPath -RelSubPath $topChild
    Update-FolderTree -PreferredSelectRel $newRel
    if ($RdoPatternB.Checked) { Update-SceneModeUI -ReloadContent }
    Append-WfLog "3ルート子フォルダ名同期完了 ($($renamedList -join ' / ')) [台帳更新: ${ledgerUpdated}行]"
    return $true
}

function Sync-ExternalRenamedSubFolders {
    # 取込後・現像後のいずれかでエクスプローラー上から子フォルダ名が変更された場合、ファイル名ステム一致により他ルート（RAW含む）と台帳を自動追従同期
    $activeRoots = @()
    if (-not [string]::IsNullOrWhiteSpace($script:ActiveDevDateFolder) -and (Test-Path -LiteralPath $script:ActiveDevDateFolder -PathType Container)) {
        $activeRoots += @{ Name = "Dev"; Path = $script:ActiveDevDateFolder }
    }
    if (-not [string]::IsNullOrWhiteSpace($script:ActiveImportDateFolder) -and (Test-Path -LiteralPath $script:ActiveImportDateFolder -PathType Container)) {
        $activeRoots += @{ Name = "Imp"; Path = $script:ActiveImportDateFolder }
    }
    if (-not [string]::IsNullOrWhiteSpace($script:ActiveRawDateFolder) -and (Test-Path -LiteralPath $script:ActiveRawDateFolder -PathType Container)) {
        $activeRoots += @{ Name = "Raw"; Path = $script:ActiveRawDateFolder }
    }
    if ($activeRoots.Count -lt 2) { return }

    # 番号プレフィックス (例: 01 -> 01_モデル名) またはファイルステム一致によるリネーム検出
    $dirsByRoot = @{}
    foreach ($rt in $activeRoots) {
        $dirsByRoot[$rt.Name] = @(Get-ChildItem -LiteralPath $rt.Path -Directory -ErrorAction SilentlyContinue)
    }

    foreach ($srcRoot in @("Dev", "Imp")) {
        if (-not $dirsByRoot.ContainsKey($srcRoot)) { continue }
        foreach ($candDir in $dirsByRoot[$srcRoot]) {
            $newName = $candDir.Name
            # 全ルートに既に同名が存在する場合は同期不要
            $missingInOther = $false
            foreach ($rt in $activeRoots) {
                if (-not (Test-Path -LiteralPath (Join-Path $rt.Path $newName) -PathType Container)) {
                    $missingInOther = $true
                    break
                }
            }
            if (-not $missingInOther) { continue }

            $candStems = Get-DirFileStemSet -DirPath $candDir.FullName
            $prefixNum = if ($newName -match '^(\d{2})[_\-\s].+') { $Matches[1] } else { "" }

            foreach ($otherRt in $activeRoots) {
                if ($otherRt.Name -eq $srcRoot) { continue }
                if (Test-Path -LiteralPath (Join-Path $otherRt.Path $newName) -PathType Container) { continue }

                $matchedOldDir = $null
                foreach ($od in @(Get-ChildItem -LiteralPath $otherRt.Path -Directory -ErrorAction SilentlyContinue)) {
                    # 対応するフォルダがsrcRoot側にまだ残っている場合は別フォルダなので除外
                    if (Test-Path -LiteralPath (Join-Path ($activeRoots | Where-Object { $_.Name -eq $srcRoot } | Select-Object -First 1).Path $od.Name) -PathType Container) {
                        continue
                    }
                    if (-not [string]::IsNullOrWhiteSpace($prefixNum) -and ($od.Name -ieq $prefixNum)) {
                        $matchedOldDir = $od
                        break
                    }
                    if ($candStems.Count -gt 0) {
                        $otherStems = Get-DirFileStemSet -DirPath $od.FullName
                        $overlap = 0
                        foreach ($st in $candStems) {
                            if ($otherStems.Contains($st)) { $overlap++; break }
                        }
                        if ($overlap -gt 0) {
                            $matchedOldDir = $od
                            break
                        }
                    }
                }

                if ($null -ne $matchedOldDir) {
                    $oldLeaf = $matchedOldDir.Name
                    [void](Invoke-SubFolderRenameThreeRoots -OldRelSubPath $oldLeaf -NewLeafName $newName)
                    break
                }
            }
        }
    }
}

$BtnRefresh.Add_Click({
    Sync-ExternalRenamedSubFolders
    Set-ActiveLinkedFolders -BaseFolderPath (Get-ActiveAnchorFolder)
    Append-WfLog "フォルダ紐づけ・リネーム追従同期・構成一覧を更新しました。"
})

$PromptRenameSubFolderAction = {
    $sel = $TreeFolders.SelectedNode
    if ($null -eq $sel -or $null -eq $sel.Tag -or ($sel.Tag.IsDateRoot -eq $true)) {
        Show-MsgBox -Text "名前を変更する子フォルダまたは孫フォルダを一覧から選択してください。" -Title "未選択" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
        return
    }
    $oldRel = [string]$sel.Tag.RelSubPath
    if ([string]::IsNullOrWhiteSpace($oldRel)) { return }
    $oldLeaf = [System.IO.Path]::GetFileName($oldRel)
    $newLeaf = Show-SimpleInputDialog -Title "子フォルダ名変更（3ルート一括同期）" -Prompt "新しいフォルダ名（取込元・現像後・RAW・台帳を一括更新）:" -DefaultValue $oldLeaf
    if ([string]::IsNullOrWhiteSpace($newLeaf) -or ($newLeaf -ceq $oldLeaf)) { return }
    if ($newLeaf -match '[\\/:\*\?"<>\|]') {
        Show-MsgBox -Text "フォルダ名に使用できない文字が含まれています。" -Title "入力エラー" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
        return
    }
    try {
        [void](Invoke-SubFolderRenameThreeRoots -OldRelSubPath $oldRel -NewLeafName $newLeaf)
    } catch {
        Show-MsgBox -Text "フォルダ名変更エラー:`n$($_.Exception.Message)" -Title "エラー" -Buttons "OK" -Icon "Error" -Owner $Form | Out-Null
    }
}
$BtnRenameSubFolder.Add_Click($PromptRenameSubFolderAction)
$MnuCtxRename.Add_Click($PromptRenameSubFolderAction)
$MnuCtxEditor.Add_Click({ $BtnOpenEditor.PerformClick() })
$MnuCtxMessage.Add_Click({ $BtnCreateMessage.PerformClick() })

$BtnAddChildFolder.Add_Click({
    if ([string]::IsNullOrWhiteSpace($script:ActiveDateName)) { return }
    $newName = Show-SimpleInputDialog -Title "子フォルダ作成" -Prompt "作成する子フォルダ名（例: 01 / 前半_スタジオ）:" -DefaultValue ""
    if ([string]::IsNullOrWhiteSpace($newName)) { return }
    if ($newName -match '[\\/:\*\?"<>\|]') {
        Show-MsgBox -Text "フォルダ名に使用できない文字が含まれています。" -Title "入力エラー" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
        return
    }

    $createdPaths = New-Object System.Collections.Generic.List[string]
    foreach ($baseDir in @($script:ActiveDevDateFolder, $script:ActiveImportDateFolder, $script:ActiveRawDateFolder)) {
        if (-not [string]::IsNullOrWhiteSpace($baseDir) -and (Test-Path -LiteralPath $baseDir -PathType Container)) {
            $np = Join-Path $baseDir $newName
            if (-not (Test-Path -LiteralPath $np)) {
                New-Item -ItemType Directory -Path $np -Force | Out-Null
            }
            [void]$createdPaths.Add($np)
        }
    }
    if ($createdPaths.Count -eq 0) {
        $anchor = Get-ActiveAnchorFolder
        if (-not [string]::IsNullOrWhiteSpace($anchor)) {
            if (-not (Test-Path -LiteralPath $anchor)) { New-Item -ItemType Directory -Path $anchor -Force | Out-Null }
            $np = Join-Path $anchor $newName
            New-Item -ItemType Directory -Path $np -Force | Out-Null
            [void]$createdPaths.Add($np)
            Refresh-LinkedFoldersUIState
        }
    }

    if ($createdPaths.Count -gt 0) {
        $script:SelectedChildSceneRoot = Resolve-PreferredSubFolderPath -RelSubPath $newName
        Update-FolderTree -PreferredSelectRel $newName
        if ($RdoPatternB.Checked) { Update-SceneModeUI -ReloadContent }
        Append-WfLog "子フォルダを作成しました: $($createdPaths -join ', ')"
    }
})

$BtnSaveScene.Add_Click({
    $catVal = [string]$CmbSceneCat.SelectedItem
    $scnVal = $CmbSceneName.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($scnVal)) {
        Show-MsgBox -Text "イベント名・スタジオ名・併せ名・場所を入力してください。" -Title "入力確認" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
        return
    }

    $targetRel = if ($RdoPatternA.Checked) { "" } else { Get-PatternBTargetChildRel }
    if (-not $RdoPatternA.Checked -and [string]::IsNullOrWhiteSpace($targetRel)) {
        Show-MsgBox -Text "パターンB（子フォルダ直下）の保存先となる子フォルダを選択または作成してください。" -Title "確認" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
        return
    }

    $targetBaseDir = Resolve-PreferredSubFolderPath -RelSubPath $targetRel
    if ([string]::IsNullOrWhiteSpace($targetBaseDir)) {
        Show-MsgBox -Text "scene.txt の保存先フォルダを解決できませんでした。" -Title "エラー" -Buttons "OK" -Icon "Error" -Owner $Form | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $targetBaseDir)) {
        New-Item -ItemType Directory -Path $targetBaseDir -Force | Out-Null
    }

    if ($RdoPatternB.Checked) {
        $dateSceneDirs = @(Get-PairedDirsForActiveSubPath -RelSubPath "" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath (Join-Path $_ "scene.txt")) })
        if (@($dateSceneDirs).Count -gt 0) {
            $ans = Show-MsgBox -Text "日付フォルダ直下に既存の scene.txt があります。`n子フォルダ直下（1日2件以上）へ切り替えるため、日付直下の scene.txt を削除しますか？" -Title "scene.txt 配置切替確認" -Buttons "YesNo" -Icon "Question" -Owner $Form
            if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
                foreach ($dd in $dateSceneDirs) {
                    $oldSc = Join-Path $dd "scene.txt"
                    if (Test-Path -LiteralPath $oldSc) { Remove-Item -LiteralPath $oldSc -Force -ErrorAction SilentlyContinue }
                }
            }
        }
    }

    $savedTargets = New-Object System.Collections.Generic.List[string]
    foreach ($dir in @(Get-PairedDirsForActiveSubPath -RelSubPath $targetRel)) {
        if (-not [string]::IsNullOrWhiteSpace($dir) -and (Test-Path -LiteralPath $dir -PathType Container)) {
            Save-SceneFile -TargetDir $dir -Category $catVal -SceneName $scnVal
            [void]$savedTargets.Add($dir)
        }
    }
    if ($savedTargets.Count -eq 0) {
        Save-SceneFile -TargetDir $targetBaseDir -Category $catVal -SceneName $scnVal
        [void]$savedTargets.Add($targetBaseDir)
    }

    if (Get-Command Update-SceneHistoryData -ErrorAction SilentlyContinue) {
        Update-SceneHistoryData -HistoryPath ([string]$Config.SceneHistoryPath) -Category $catVal -SceneName $scnVal -DateStr $script:ActiveDateName -Config $Config
    }
    Load-SceneHistoryToCombo
    Update-FolderTree -PreferredSelectRel $targetRel
    Append-WfLog "scene.txt を保存しました ($catVal / $scnVal): $($savedTargets -join ', ')"
})

$BtnOpenEditor.Add_Click({
    $sel = $TreeFolders.SelectedNode
    if ($null -eq $sel -or $null -eq $sel.Tag) {
        Show-MsgBox -Text "編集する日付フォルダまたは子フォルダ・孫フォルダを一覧から選択してください。" -Title "未選択" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
        return
    }
    Open-PhotoInfoEditorForPath -TargetSubFolder ([string]$sel.Tag.FolderPath)
})

$BtnOpenExplorer.Add_Click({
    $targetToOpen = Get-ActiveAnchorFolder
    $sel = $TreeFolders.SelectedNode
    if ($null -ne $sel -and $null -ne $sel.Tag -and -not [string]::IsNullOrWhiteSpace([string]$sel.Tag.FolderPath)) {
        $targetToOpen = [string]$sel.Tag.FolderPath
    }
    if (-not [string]::IsNullOrWhiteSpace($targetToOpen) -and (Test-Path -LiteralPath $targetToOpen)) {
        Start-Process "explorer.exe" -ArgumentList "`"$targetToOpen`""
    }
})

$BtnGigaSend.Add_Click({
    $sel = $TreeFolders.SelectedNode
    if ($null -eq $sel -or $null -eq $sel.Tag) {
        Show-MsgBox -Text "送信するフォルダを一覧から選択してください。" -Title "未選択" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
        return
    }
    $relSub = [string]$sel.Tag.RelSubPath
    $targetFolder = Resolve-PreferredSubFolderPath -RelSubPath $relSub
    if ([string]::IsNullOrWhiteSpace($targetFolder) -or -not (Test-Path -LiteralPath $targetFolder)) {
        Show-MsgBox -Text "選択フォルダが存在しません: $targetFolder" -Title "エラー" -Buttons "OK" -Icon "Error" -Owner $Form | Out-Null
        return
    }

    Append-WfLog "ギガファイル便連携を起動します: $targetFolder"
    try {
        $res = Invoke-GigaFileUploadWithCallback -TargetPaths @($targetFolder) -RootDir $RootDir -Config $Config
        if ($null -ne $res -and -not [string]::IsNullOrWhiteSpace($res.Url)) {
            $expStr = if ($res.ContainsKey("ExpiryDate") -and -not [string]::IsNullOrWhiteSpace([string]$res.ExpiryDate)) {
                [string]$res.ExpiryDate
            } elseif ([int]$res.LifetimeDays -gt 0) {
                (Get-Date).AddDays([int]$res.LifetimeDays).ToString("yyyy/MM/dd") + "まで"
            } else { "" }
            Append-WfLog "共有URL取得成功: $($res.Url) (削除キー: $($res.DelKey) / 期限: $expStr)"
            $updatedInfos = @()
            $memo = "[ギガファイル便] URL=$($res.Url) / PW=$($res.Password) / 削除キー=$($res.DelKey) / 期限=$expStr"
            foreach ($pairDir in @(Get-PairedDirsForActiveSubPath -RelSubPath $relSub)) {
                if ([string]::IsNullOrWhiteSpace($pairDir) -or -not (Test-Path -LiteralPath $pairDir)) { continue }
                $info = Read-PhotoInfoTxt -FolderPath $pairDir -Config $Config
                $info.ShareUrl = $res.Url
                $info.GigaFileLink = $res.Url
                $info.DlPassword = [string]$res.Password
                $info.GigaFileExpiry = $expStr
                $info.SentStatus = "送付済み"
                $info.IsSent = $true
                if ([string]::IsNullOrWhiteSpace($info.Notes)) {
                    $info.Notes = $memo
                } elseif ($info.Notes -notmatch [regex]::Escape($res.Url)) {
                    $info.Notes = $info.Notes + "`r`n" + $memo
                }
                [void](Write-PhotoInfoTxt -FolderPath $pairDir -Info $info)
                if ($pairDir -ieq $targetFolder) {
                    $updatedInfos += $info
                }
                Append-WfLog "写真情報.txt へ送付済み反映: $pairDir"
            }
            if (@($updatedInfos).Count -gt 0) {
                Sync-RecordsToExcelLedger -Config $Config -Records $updatedInfos
                Append-WfLog "Excel台帳へ送付状況を反映しました。"
            }
            Update-FolderTree -PreferredSelectRel $relSub
        } else {
            Append-WfLog "ギガファイル便の送信はキャンセルされたか、URLが返却されませんでした。"
        }
    } catch {
        Write-LogError -ModuleName "DailyWorkflow" -Message $_.Exception.Message -ErrorRecord $_ | Out-Null
        Append-WfLog "[ERROR] $($_.Exception.Message)"
    }
})

$BtnCreateMessage.Add_Click({
    $sel = $TreeFolders.SelectedNode
    if ($null -eq $sel -or $null -eq $sel.Tag) {
        Show-MsgBox -Text "メッセージ作成の対象となるフォルダを一覧から選択してください。" -Title "未選択" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
        return
    }
    $relSub = [string]$sel.Tag.RelSubPath
    $targetFolder = Resolve-PreferredSubFolderPath -RelSubPath $relSub
    if ([string]::IsNullOrWhiteSpace($targetFolder) -or -not (Test-Path -LiteralPath $targetFolder)) {
        Show-MsgBox -Text "選択フォルダが存在しません: $targetFolder" -Title "エラー" -Buttons "OK" -Icon "Error" -Owner $Form | Out-Null
        return
    }
    $composerScript = Join-Path $RootDir "editor\MessageComposerDialog.ps1"
    if (-not (Test-Path -LiteralPath $composerScript)) {
        Show-MsgBox -Text "MessageComposerDialog.ps1 が見つかりません:`n$composerScript" -Title "エラー" -Buttons "OK" -Icon "Error" -Owner $Form | Out-Null
        return
    }
    try {
        . $composerScript
        $searchRoots = @($script:ActiveDevDateFolder, $script:ActiveImportDateFolder) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Container) }
        $msgRes = Show-MessageComposerDialog `
            -Mode "Combined" `
            -PrimaryFolder $targetFolder `
            -DateSearchRoots @($searchRoots) `
            -RootDir $RootDir `
            -Config $Config `
            -OwnerForm $Form
        if ($null -ne $msgRes) {
            if ($msgRes.UpdatedMega) { Append-WfLog "メッセージ作成画面からMEGAリンクを取得し写真情報・台帳へ反映しました。" }
            if ($msgRes.MarkedSent)  { Append-WfLog "メッセージコピー連動で対象フォルダを送付済みへ更新しました。" }
            if ($msgRes.UpdatedMega -or $msgRes.MarkedSent) {
                Update-FolderTree -PreferredSelectRel $relSub
            }
        }
    } catch {
        Write-LogError -ModuleName "DailyWorkflow" -Message $_.Exception.Message -ErrorRecord $_ | Out-Null
        Append-WfLog "[ERROR] メッセージ作成画面起動失敗: $($_.Exception.Message)"
        Show-MsgBox -Text "メッセージ作成画面エラー:`n$($_.Exception.Message)" -Title "エラー" -Buttons "OK" -Icon "Error" -Owner $Form | Out-Null
    }
})

$StepLabels = @("Step1 仕分け作成", "Step2 RAW複製移動", "Step3 現像後振分", "Step4 重複JPG削除", "Step5 アーカイブ移動")
for ($i = 0; $i -lt $StepLabels.Count; $i++) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $StepLabels[$i]
    $btn.Location = New-Object System.Drawing.Point((16 + ($i * 175)), 552)
    $btn.Size = New-Object System.Drawing.Size(168, 36)
    $stepIdx = $i + 1
    $btn.Tag = $stepIdx
    $script:StepButtons[$stepIdx] = $btn
    $btn.Add_Click({
        param($sender, $e)
        if ($script:IsStepBusy) {
            Show-MsgBox -Text "現在別のStep処理を実行中です。完了までお待ちください。" -Title "処理中" -Buttons "OK" -Icon "Information" -Owner $Form | Out-Null
            return
        }
        $num = [int]$sender.Tag
        $dateName = $script:ActiveDateName
        if ([string]::IsNullOrWhiteSpace($dateName) -or $dateName -eq '.' -or $dateName -eq '..') {
            Show-MsgBox -Text "対象日付が選択されていません。" -Title "確認" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
            return
        }

        Sync-ExternalRenamedSubFolders
        $impDir = $script:ActiveImportDateFolder
        $devDir = $script:ActiveDevDateFolder
        $rawDir = $script:ActiveRawDateFolder

        $script:IsStepBusy = $true
        try {
            switch ($num) {
                1 {
                    if ([string]::IsNullOrWhiteSpace($impDir) -or -not (Test-Path -LiteralPath $impDir -PathType Container)) {
                        $baseImp = if (-not [string]::IsNullOrWhiteSpace([string]$Config.ImportRoot1)) { [string]$Config.ImportRoot1 } else { [string]$Config.ImportRoot2 }
                        if ([string]::IsNullOrWhiteSpace($baseImp)) {
                            Show-MsgBox -Text "Step1 はカメラ取り込み元フォルダが設定・選択されている場合のみ実行できます。" -Title "実行不可" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
                            return
                        }
                        $candImp = Join-Path ($baseImp.TrimEnd('\')) $dateName
                        $ansCreate = Show-MsgBox -Text "カメラ取り込み元に対象日付フォルダが存在しません。`n新規作成して Step1（連番仕分けフォルダ作成）を実行しますか？`n`n作成先: $candImp" -Title "取り込み元フォルダ新規作成確認" -Buttons "YesNo" -Icon "Question" -Owner $Form
                        if ($ansCreate -ne [System.Windows.Forms.DialogResult]::Yes) { return }
                        New-Item -ItemType Directory -Path $candImp -Force | Out-Null
                        $impDir = $candImp
                        $script:ActiveImportDateFolder = $candImp
                        Refresh-LinkedFoldersUIState
                    }
                    if (-not (Test-IsAllowedImportPath -Path $impDir)) {
                        Show-MsgBox -Text "Step1 は「カメラ取り込み元 1」または「カメラ取り込み元 2」配下のフォルダでのみ実行できます。" -Title "実行不可" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
                        return
                    }
                    $cntStr = Show-SimpleInputDialog -Title "Step1 仕分けフォルダ作成" -Prompt "作成する連番フォルダ数 (01～NN):" -DefaultValue "5"
                    if ($null -eq $cntStr) { Append-WfLog "Step1 がキャンセルされました。"; return }
                    $cnt = 0
                    if (-not [int]::TryParse($cntStr, [ref]$cnt) -or $cnt -le 0) {
                        throw "作成数は 1 以上の整数を指定してください。"
                    }
                    Append-WfLog "Step1 を実行します (対象: $impDir)..."
                    $r = Invoke-WorkflowStep1 -DateFolder $impDir -Count $cnt -Config $Config
                    Append-WfLog "Step1 完了: $($r.CreatedCount) 個のフォルダを作成しました ($impDir)。"
                }
                2 {
                    if ([string]::IsNullOrWhiteSpace($impDir) -or -not (Test-Path -LiteralPath $impDir -PathType Container)) {
                        Show-MsgBox -Text "カメラ取り込み元に対象日付フォルダが存在しないため（データ削減済等）、Step2 は実行できません。" -Title "実行不可" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
                        return
                    }
                    if (-not (Test-IsAllowedImportPath -Path $impDir)) {
                        Show-MsgBox -Text "Step2 は「カメラ取り込み元 1」または「カメラ取り込み元 2」配下のフォルダでのみ実行できます。" -Title "実行不可" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
                        return
                    }
                    Append-WfLog "Step2 を別プロセス非同期で実行します (対象: $impDir)..."
                    $outJsonFile = Join-Path ([System.IO.Path]::GetTempPath()) ("wf_step2_" + [Guid]::NewGuid().ToString("N") + ".json")
                    $runnerCode = "& { . '$CommonDir\LogHelper.ps1'; . '$CommonDir\ConfigHelper.ps1'; . '$ScriptDir\WorkflowStep2Helper.ps1'; `$cfg = Get-PhotoToolsConfig -RootDir '$RootDir'; `$res = Invoke-WorkflowStep2 -ImportDateFolder '$impDir' -Config `$cfg; `$res | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath '$outJsonFile' -Encoding UTF8 }"
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = "powershell.exe"
                    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$runnerCode`""
                    $psi.UseShellExecute = $false
                    $psi.CreateNoWindow = $true
                    $proc = [System.Diagnostics.Process]::Start($psi)
                    $script:RunningHelperProc = $proc
                    while ($null -ne $proc -and -not $proc.HasExited) {
                        [System.Windows.Forms.Application]::DoEvents()
                        Start-Sleep -Milliseconds 100
                    }
                    $script:RunningHelperProc = $null
                    if (Test-Path -LiteralPath $outJsonFile) {
                        $r = Get-Content -LiteralPath $outJsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
                        Remove-Item -LiteralPath $outJsonFile -Force -ErrorAction SilentlyContinue
                        Append-WfLog "Step2 完了: RAW $($r.MovedRawCount) 件を移動しました ($impDir)。"
                    } else {
                        Append-WfLog "Step2 プロセスが中断または終了しました。"
                    }
                    Set-ActiveLinkedFolders -BaseFolderPath $impDir -ExplicitImportDateDir $impDir
                    return
                }
                3 {
                    if ([string]::IsNullOrWhiteSpace($devDir) -and [string]::IsNullOrWhiteSpace($dateName)) {
                        Show-MsgBox -Text "現像後フォルダに対象日付フォルダが見つかりません。" -Title "実行不可" -Buttons "OK" -Icon "Warning" -Owner $Form | Out-Null
                        return
                    }
                    $targetDateName = if (-not [string]::IsNullOrWhiteSpace($dateName)) { $dateName } else { [System.IO.Path]::GetFileName($devDir) }
                    Append-WfLog "Step3 振分GUI・監視モードを起動します (日付: $targetDateName)..."
                    $r = Show-WorkflowStep3Dialog -DateFolderName $targetDateName -Config $Config -RawDateFolder $rawDir -ImportDateFolder $impDir -DevelopedDateFolder $devDir
                    Append-WfLog "Step3 GUIセッション終了"
                    Set-ActiveLinkedFolders -BaseFolderPath (Get-ActiveAnchorFolder)
                    return
                }
                4 {
                    if ([string]::IsNullOrWhiteSpace($impDir) -or -not (Test-Path -LiteralPath $impDir -PathType Container)) {
                        Show-MsgBox -Text "取り込み元に対象日付フォルダが存在しないため（データ削減済等）、重複JPG削除はスキップしました。" -Title "Step4 確認" -Buttons "OK" -Icon "Information" -Owner $Form | Out-Null
                        return
                    }
                    Append-WfLog "Step4 を実行します (対象: $impDir)..."
                    $r = Show-WorkflowStep4Dialog -ImportDateFolder $impDir -Config $Config
                    if ($r.Skipped -eq $true) {
                        Append-WfLog "Step4 スキップ: $($r.Message)"
                        Show-MsgBox -Text ([string]$r.Message) -Title "Step4 確認" -Buttons "OK" -Icon "Information" -Owner $Form | Out-Null
                    } else {
                        Append-WfLog "Step4 完了: 重複JPG $($r.DeletedCount) 件を削除しました。"
                    }
                }
                5 {
                    $hasDevTarget = (-not [string]::IsNullOrWhiteSpace($devDir)) -and (Test-Path -LiteralPath $devDir)
                    $hasRawTarget = (-not [string]::IsNullOrWhiteSpace($rawDir)) -and (Test-Path -LiteralPath $rawDir)
                    $hasImpTarget = (-not [string]::IsNullOrWhiteSpace($impDir)) -and (Test-Path -LiteralPath $impDir)
                    if ((-not $hasDevTarget) -and (-not $hasRawTarget) -and (-not $hasImpTarget)) {
                        Show-MsgBox -Text "アーカイブ対象のフォルダ（現像後・RAW・取込元）が見つかりません。" -Title "Step5 確認" -Buttons "OK" -Icon "Information" -Owner $Form | Out-Null
                        return
                    }
                    $ans = Show-MsgBox -Text "[$dateName] の現像後・RAW・取込元フォルダを写真アーカイブ先（ImportArchiveRoot等）へ移動し、台帳パスを更新しますか？" -Title "Step5 アーカイブ移動確認" -Buttons "YesNo" -Icon "Question" -Owner $Form
                    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { Append-WfLog "Step5 がキャンセルされました。"; return }
                    Append-WfLog "Step5 を別プロセス非同期で実行します (日付: $dateName)..."
                    $outJsonFile = Join-Path ([System.IO.Path]::GetTempPath()) ("wf_step5_" + [Guid]::NewGuid().ToString("N") + ".json")
                    $runnerCode = "& { . '$CommonDir\LogHelper.ps1'; . '$CommonDir\ConfigHelper.ps1'; . '$CommonDir\ExcelHelper.ps1'; . '$ScriptDir\WorkflowStep5Helper.ps1'; `$cfg = Get-PhotoToolsConfig -RootDir '$RootDir'; `$res = Invoke-WorkflowStep5 -DateFolderName '$dateName' -Config `$cfg -DevelopedDateFolder '$devDir' -RawDateFolder '$rawDir' -ImportDateFolder '$impDir'; `$res | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath '$outJsonFile' -Encoding UTF8 }"
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = "powershell.exe"
                    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$runnerCode`""
                    $psi.UseShellExecute = $false
                    $psi.CreateNoWindow = $true
                    $proc = [System.Diagnostics.Process]::Start($psi)
                    $script:RunningHelperProc = $proc
                    while ($null -ne $proc -and -not $proc.HasExited) {
                        [System.Windows.Forms.Application]::DoEvents()
                        Start-Sleep -Milliseconds 100
                    }
                    $script:RunningHelperProc = $null
                    if (Test-Path -LiteralPath $outJsonFile) {
                        $r = Get-Content -LiteralPath $outJsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
                        Remove-Item -LiteralPath $outJsonFile -Force -ErrorAction SilentlyContinue
                        Append-WfLog "Step5 完了: 現像後移動=$($r.MovedDeveloped) / RAW移動=$($r.MovedRaw) / 取込元移動=$($r.MovedImport)"
                    } else {
                        Append-WfLog "Step5 プロセスが中断または終了しました。"
                    }
                    Set-ActiveLinkedFolders -BaseFolderPath (Get-ActiveAnchorFolder)
                    return
                }
            }
            Refresh-LinkedFoldersUIState
            Update-FolderTree
        } catch {
            Write-LogError -ModuleName "DailyWorkflow" -Message $_.Exception.Message -ErrorRecord $_ | Out-Null
            Append-WfLog "[ERROR] Step$num 失敗: $($_.Exception.Message)"
            Show-MsgBox -Text "Step$num 実行エラー:`n$($_.Exception.Message)" -Title "エラー" -Buttons "OK" -Icon "Error" -Owner $Form | Out-Null
        } finally {
            $script:RunningHelperProc = $null
            $script:IsStepBusy = $false
        }
    })
    $Form.Controls.Add($btn)
}

$Form.Add_FormClosing({
    param($sender, $e)
    if ($script:IsStepBusy -or ($null -ne $script:RunningHelperProc -and -not $script:RunningHelperProc.HasExited)) {
        $ans = [System.Windows.Forms.MessageBox]::Show(
            $Form,
            "現在バックグラウンドでワークフロー処理を実行中です。`n実行中の処理を強制終了して画面を閉じますか？",
            "処理中クローズ警告",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
            $e.Cancel = $true
            return
        }
        try {
            if ($null -ne $script:RunningHelperProc -and -not $script:RunningHelperProc.HasExited) {
                $script:RunningHelperProc.Kill()
            }
        } catch {}
    }
    $EditorWatchTimer.Stop()
    $EditorWatchTimer.Dispose()
})

$initial = Resolve-DateFolderFromTarget -InputPath $TargetPath
Set-ActiveLinkedFolders -BaseFolderPath $initial.DateFolder -SelectChildRel ([string]$initial.SelectedSubRel) -SelectChildPath ([string]$initial.SelectedSubPath)
Sync-ExternalRenamedSubFolders

[void]$Form.ShowDialog()
}
catch {
    $errMsg = "DailyWorkflow 起動エラー:`n$($_.Exception.Message)`n行番号: $($_.InvocationInfo.ScriptLineNumber)`nスクリプト: $($_.InvocationInfo.ScriptName)`nスタックトレース:`n$($_.ScriptStackTrace)"
    try {
        Show-MsgBox -Text $errMsg -Title "致命的エラー (DailyWorkflow)" -Buttons "OK" -Icon "Error" | Out-Null
    } catch {}
    try {
        Write-LogError -ModuleName "DailyWorkflow" -Message $_.Exception.Message -ErrorRecord $_ | Out-Null
    } catch {}
    exit 1
}
