#requires -Version 5.1
# ==============================================================================
# PhotoInfoEditor.ps1 - 被写体プロパティ・写真情報登録/編集GUI (UTF-8 BOM / CRLF)
# ==============================================================================
param(
    [Parameter(Position = 0)]
    [Alias("TargetPath", "FolderPath", "Path", "TargetDir")]
    [string]$TargetFolder = "",
    [string]$ModuleName = "",
    [hashtable]$Config = @{},
    [switch]$ForceEditor,
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$RemainingArgs
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ScriptDir)) { $ScriptDir = "D:\PhotoTools\editor" }
$RootDir = Split-Path -Parent $ScriptDir
if (-not (Test-Path -LiteralPath (Join-Path $RootDir "settings.ini"))) {
    if (Test-Path -LiteralPath "D:\PhotoTools\settings.ini") { $RootDir = "D:\PhotoTools" }
}

if ([string]::IsNullOrWhiteSpace($TargetFolder) -and $null -ne $RemainingArgs -and @($RemainingArgs).Count -gt 0) {
    foreach ($arg in $RemainingArgs) {
        $s = [string]$arg
        if (-not [string]::IsNullOrWhiteSpace($s) -and -not $s.StartsWith("-")) {
            $TargetFolder = $s
            break
        }
    }
}
$TargetFolder = $TargetFolder.Trim().Trim('"').TrimEnd('\')

if ((-not $ForceEditor) -and (-not [string]::IsNullOrWhiteSpace($TargetFolder)) -and (Test-Path -LiteralPath $TargetFolder -PathType Container)) {
    $leafName = [System.IO.Path]::GetFileName($TargetFolder)
    $parentDir = [System.IO.Path]::GetDirectoryName($TargetFolder)
    $parentLeaf = if ([string]::IsNullOrWhiteSpace($parentDir)) { "" } else { [System.IO.Path]::GetFileName($parentDir) }
    $dateFolderRegex = '^\d{4}(?:[-_.]\d{2}[-_.]\d{2}|\d{4})(?:$|[_\-\s].*)'
    $hasDirectPhotoInfo = Test-Path -LiteralPath (Join-Path $TargetFolder "写真情報.txt")
    if (($leafName -match $dateFolderRegex) -and (-not ($parentLeaf -match $dateFolderRegex)) -and (-not $hasDirectPhotoInfo)) {
        $dailyScript = Join-Path $RootDir "workflow\DailyWorkflow.ps1"
        if (Test-Path -LiteralPath $dailyScript) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$dailyScript`" -TargetPath `"$TargetFolder`""
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            [void][System.Diagnostics.Process]::Start($psi)
            exit 0
        }
    }
}

$logicPath = Join-Path $RootDir "common\PhotoEditorLogic.ps1"
if (-not (Test-Path -LiteralPath $logicPath)) {
    [System.Windows.Forms.MessageBox]::Show("ロジックファイルが見つかりません:`n$logicPath", "起動エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}
. $logicPath

$EffectiveConfig = Initialize-PhotoEditorEnvironment -ScriptDir $ScriptDir -ExternalConfig $Config
if (Get-Command Ensure-XHistoryFile -ErrorAction SilentlyContinue) {
    Ensure-XHistoryFile -HistoryPath ([string]$EffectiveConfig.XHistoryPath)
}

function Write-EditorLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    try {
        if (Get-Command Write-LogInfo -ErrorAction SilentlyContinue) {
            Write-LogInfo -Message $Message -ModuleName "PhotoInfoEditor" -Level $Level | Out-Null
        }
    } catch {}
}

function Write-EditorError {
    param(
        [string]$Message,
        $ErrorRecord = $null,
        [hashtable]$Context = $null
    )
    try {
        if (Get-Command Write-LogError -ErrorAction SilentlyContinue) {
            Write-LogError -Message $Message -ErrorRecord $ErrorRecord -ModuleName "PhotoInfoEditor" -Context $Context | Out-Null
            if (Get-Command Get-LastPhotoDebugLogPath -ErrorAction SilentlyContinue) {
                $p = [string](Get-LastPhotoDebugLogPath)
                if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p)) {
                    return $p
                }
            }
        }
    } catch {}
    return ""
}

function Show-EditorErrorDialog {
    param(
        [string]$TitlePrefix,
        $ErrorRecord,
        [hashtable]$Context = $null,
        [string]$DialogTitle = "エラー"
    )
    $dbgPath = Write-EditorError -Message $TitlePrefix -ErrorRecord $ErrorRecord -Context $Context
    $dbgSum = ""
    if (Get-Command Get-LastPhotoDebugSummary -ErrorAction SilentlyContinue) {
        $dbgSum = [string](Get-LastPhotoDebugSummary)
    }
    $errMsg = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord] -and $null -ne $ErrorRecord.Exception) {
        [string]$ErrorRecord.Exception.Message
    } elseif ($ErrorRecord -is [System.Exception]) {
        [string]$ErrorRecord.Message
    } else {
        [string]$ErrorRecord
    }
    $detailPart = if (-not [string]::IsNullOrWhiteSpace($dbgSum)) { "`n`n$dbgSum" } else { "" }
    $filePart = if (-not [string]::IsNullOrWhiteSpace($dbgPath) -and (Test-Path -LiteralPath $dbgPath)) { "`n`nデバッグファイル:`n$dbgPath" } else { "" }
    Show-MsgBox -Text "${TitlePrefix}: ${errMsg}${detailPart}${filePart}" -Title $DialogTitle -Buttons "OK" -Icon "Error" | Out-Null
}

Write-EditorLog "PhotoInfoEditor 起動 (TargetFolder=$TargetFolder, ForceEditor=$ForceEditor, XHistoryPath=$($EffectiveConfig.XHistoryPath))"

$script:Paired = Resolve-PairedPhotoFolders -Folder $TargetFolder -EffectiveConfig $EffectiveConfig
$script:PersonsList = New-Object System.Collections.Generic.List[hashtable]
$script:CurrentPersonIndex = 0
$script:IsUpdatingUI = $false
$script:IsDirty = $false
$script:RelatedFolders = @()

function Find-DateFolderAncestor {
    param([string]$StartFolder)
    if ([string]::IsNullOrWhiteSpace($StartFolder)) { return "" }
    $curr = $StartFolder.Trim().TrimEnd('\')
    if (Test-Path -LiteralPath $curr -PathType Leaf) {
        $curr = [System.IO.Path]::GetDirectoryName($curr)
    }
    $dateRegex = '^\d{4}(?:[-_.]\d{2}[-_.]\d{2}|\d{4})(?:$|[_\-\s].*)'
    for ($i = 0; $i -lt 10; $i++) {
        if ([string]::IsNullOrWhiteSpace($curr)) { break }
        $leaf = [System.IO.Path]::GetFileName($curr)
        if ($leaf -match $dateRegex) {
            return $curr
        }
        $curr = [System.IO.Path]::GetDirectoryName($curr)
    }
    $parent = [System.IO.Path]::GetDirectoryName($StartFolder.Trim().TrimEnd('\'))
    if (-not [string]::IsNullOrWhiteSpace($parent)) { return $parent }
    return $StartFolder.Trim().TrimEnd('\')
}

function Start-DailyWorkflowForScene {
    param([string]$TargetPathForDaily)
    $dailyScript = Join-Path $RootDir "workflow\DailyWorkflow.ps1"
    if (-not (Test-Path -LiteralPath $dailyScript)) {
        Show-MsgBox -Text "DailyWorkflow.ps1 が見つかりません:`n$dailyScript" -Title "起動エラー" -Buttons "OK" -Icon "Error" | Out-Null
        return $false
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$dailyScript`" -TargetPath `"$TargetPathForDaily`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    [void][System.Diagnostics.Process]::Start($psi)
    return $true
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "被写体プロパティ - 写真情報エディタ - " + $script:Paired.FolderName
$form.Size = New-Object System.Drawing.Size(680, 720)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5)

$toolTip = New-Object System.Windows.Forms.ToolTip

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Location = New-Object System.Drawing.Point(15, 12)
$lblPath.Size = New-Object System.Drawing.Size(635, 22)
$lblPath.ForeColor = [System.Drawing.Color]::DimGray
$lblPath.AutoEllipsis = $true
$form.Controls.Add($lblPath)

$lblCategory = New-Object System.Windows.Forms.Label
$lblCategory.Text = "撮影区分:"
$lblCategory.Location = New-Object System.Drawing.Point(15, 44)
$lblCategory.Size = New-Object System.Drawing.Size(85, 23)
$form.Controls.Add($lblCategory)

$cmbCategory = New-Object System.Windows.Forms.ComboBox
$cmbCategory.Location = New-Object System.Drawing.Point(105, 41)
$cmbCategory.Size = New-Object System.Drawing.Size(130, 25)
$cmbCategory.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$cmbCategory.Items.AddRange(@("イベント", "個撮", "併せ", "その他"))
$cmbCategory.SelectedIndex = 0
$form.Controls.Add($cmbCategory)

$lblDate = New-Object System.Windows.Forms.Label
$lblDate.Text = "撮影日:"
$lblDate.Location = New-Object System.Drawing.Point(255, 44)
$lblDate.Size = New-Object System.Drawing.Size(60, 23)
$form.Controls.Add($lblDate)

$txtDate = New-Object System.Windows.Forms.TextBox
$txtDate.Location = New-Object System.Drawing.Point(320, 41)
$txtDate.Size = New-Object System.Drawing.Size(145, 25)
$form.Controls.Add($txtDate)

$btnMultiFolder = New-Object System.Windows.Forms.Button
$btnMultiFolder.Text = "複数あり (確認)"
$btnMultiFolder.Location = New-Object System.Drawing.Point(480, 40)
$btnMultiFolder.Size = New-Object System.Drawing.Size(170, 27)
$btnMultiFolder.BackColor = [System.Drawing.Color]::LemonChiffon
$btnMultiFolder.ForeColor = [System.Drawing.Color]::DarkRed
$btnMultiFolder.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9, [System.Drawing.FontStyle]::Bold)
$btnMultiFolder.Visible = $false
$form.Controls.Add($btnMultiFolder)

$lblEvent = New-Object System.Windows.Forms.Label
$lblEvent.Text = "イベント名:"
$lblEvent.Location = New-Object System.Drawing.Point(15, 78)
$lblEvent.Size = New-Object System.Drawing.Size(88, 23)
$form.Controls.Add($lblEvent)

$txtEvent = New-Object System.Windows.Forms.TextBox
$txtEvent.Location = New-Object System.Drawing.Point(105, 75)
$txtEvent.Size = New-Object System.Drawing.Size(390, 25)
$txtEvent.ReadOnly = $true
$txtEvent.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$txtEvent.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$toolTip.SetToolTip($txtEvent, "scene.txt から自動読込されます（文字選択・Ctrl+C コピー可／手入力不可）")
$form.Controls.Add($txtEvent)

$btnOpenDailyScene = New-Object System.Windows.Forms.Button
$btnOpenDailyScene.Text = "DailyWorkflowで変更"
$btnOpenDailyScene.Location = New-Object System.Drawing.Point(500, 74)
$btnOpenDailyScene.Size = New-Object System.Drawing.Size(150, 27)
$toolTip.SetToolTip($btnOpenDailyScene, "イベント・併せ・スタジオ・場所（scene.txt）の設定・変更は DailyWorkflow から行います")
$form.Controls.Add($btnOpenDailyScene)

$lblMega = New-Object System.Windows.Forms.Label
$lblMega.Text = "MEGAリンク:"
$lblMega.Location = New-Object System.Drawing.Point(15, 112)
$lblMega.Size = New-Object System.Drawing.Size(88, 23)
$form.Controls.Add($lblMega)

$txtMega = New-Object System.Windows.Forms.TextBox
$txtMega.Location = New-Object System.Drawing.Point(105, 109)
$txtMega.Size = New-Object System.Drawing.Size(365, 25)
$form.Controls.Add($txtMega)

$btnGetMega = New-Object System.Windows.Forms.Button
$btnGetMega.Text = "リンク取得/診断"
$btnGetMega.Location = New-Object System.Drawing.Point(476, 108)
$btnGetMega.Size = New-Object System.Drawing.Size(105, 27)
$form.Controls.Add($btnGetMega)

$btnCopyMega = New-Object System.Windows.Forms.Button
$btnCopyMega.Text = "コピー"
$btnCopyMega.Location = New-Object System.Drawing.Point(586, 108)
$btnCopyMega.Size = New-Object System.Drawing.Size(64, 27)
$form.Controls.Add($btnCopyMega)

$lblGiga = New-Object System.Windows.Forms.Label
$lblGiga.Text = "ギガファイル便:"
$lblGiga.Location = New-Object System.Drawing.Point(15, 146)
$lblGiga.Size = New-Object System.Drawing.Size(88, 23)
$form.Controls.Add($lblGiga)

$txtGiga = New-Object System.Windows.Forms.TextBox
$txtGiga.Location = New-Object System.Drawing.Point(105, 143)
$txtGiga.Size = New-Object System.Drawing.Size(335, 25)
$form.Controls.Add($txtGiga)

$btnSendGiga = New-Object System.Windows.Forms.Button
$btnSendGiga.Text = "ギガファイル便で送る"
$btnSendGiga.Location = New-Object System.Drawing.Point(446, 142)
$btnSendGiga.Size = New-Object System.Drawing.Size(135, 27)
$btnSendGiga.BackColor = [System.Drawing.Color]::AliceBlue
$form.Controls.Add($btnSendGiga)

$btnCopyGiga = New-Object System.Windows.Forms.Button
$btnCopyGiga.Text = "コピー"
$btnCopyGiga.Location = New-Object System.Drawing.Point(586, 142)
$btnCopyGiga.Size = New-Object System.Drawing.Size(64, 27)
$form.Controls.Add($btnCopyGiga)

$lblMemo = New-Object System.Windows.Forms.Label
$lblMemo.Text = "フォルダメモ:"
$lblMemo.Location = New-Object System.Drawing.Point(15, 180)
$lblMemo.Size = New-Object System.Drawing.Size(88, 23)
$form.Controls.Add($lblMemo)

$txtMemo = New-Object System.Windows.Forms.TextBox
$txtMemo.Location = New-Object System.Drawing.Point(105, 177)
$txtMemo.Size = New-Object System.Drawing.Size(545, 44)
$txtMemo.Multiline = $true
$txtMemo.ScrollBars = "Vertical"
$toolTip.SetToolTip($txtMemo, "フォルダ全体の備考・ギガファイル便のパスワードや削除キー控え等")
$form.Controls.Add($txtMemo)

$grpPerson = New-Object System.Windows.Forms.GroupBox
$grpPerson.Text = "被写体・参加者情報（複数人登録・枠連動対応）"
$grpPerson.Location = New-Object System.Drawing.Point(15, 230)
$grpPerson.Size = New-Object System.Drawing.Size(635, 390)
$form.Controls.Add($grpPerson)

$lblPersonSel = New-Object System.Windows.Forms.Label
$lblPersonSel.Text = "登録枠:"
$lblPersonSel.Location = New-Object System.Drawing.Point(15, 28)
$lblPersonSel.Size = New-Object System.Drawing.Size(65, 23)
$grpPerson.Controls.Add($lblPersonSel)

$cmbPerson = New-Object System.Windows.Forms.ComboBox
$cmbPerson.Location = New-Object System.Drawing.Point(85, 25)
$cmbPerson.Size = New-Object System.Drawing.Size(330, 25)
$cmbPerson.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$grpPerson.Controls.Add($cmbPerson)

$btnAddPerson = New-Object System.Windows.Forms.Button
$btnAddPerson.Text = "＋ 人物を追加"
$btnAddPerson.Location = New-Object System.Drawing.Point(425, 24)
$btnAddPerson.Size = New-Object System.Drawing.Size(105, 27)
$grpPerson.Controls.Add($btnAddPerson)

$btnDelPerson = New-Object System.Windows.Forms.Button
$btnDelPerson.Text = "枠を削除"
$btnDelPerson.Location = New-Object System.Drawing.Point(536, 24)
$btnDelPerson.Size = New-Object System.Drawing.Size(84, 27)
$grpPerson.Controls.Add($btnDelPerson)

$lblName = New-Object System.Windows.Forms.Label
$lblName.Text = "名前:"
$lblName.Location = New-Object System.Drawing.Point(15, 68)
$lblName.Size = New-Object System.Drawing.Size(75, 23)
$grpPerson.Controls.Add($lblName)

$cmbName = New-Object System.Windows.Forms.ComboBox
$cmbName.Location = New-Object System.Drawing.Point(95, 65)
$cmbName.Size = New-Object System.Drawing.Size(525, 25)
$cmbName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
$grpPerson.Controls.Add($cmbName)

$lblCostume = New-Object System.Windows.Forms.Label
$lblCostume.Text = "衣装名ORキャラ名:"
$lblCostume.Location = New-Object System.Drawing.Point(15, 106)
$lblCostume.Size = New-Object System.Drawing.Size(120, 23)
$grpPerson.Controls.Add($lblCostume)

$cmbCostume = New-Object System.Windows.Forms.ComboBox
$cmbCostume.Location = New-Object System.Drawing.Point(140, 103)
$cmbCostume.Size = New-Object System.Drawing.Size(480, 25)
$cmbCostume.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
$grpPerson.Controls.Add($cmbCostume)

$lblX = New-Object System.Windows.Forms.Label
$lblX.Text = "Xアカウント:"
$lblX.Location = New-Object System.Drawing.Point(15, 144)
$lblX.Size = New-Object System.Drawing.Size(78, 23)
$grpPerson.Controls.Add($lblX)

$txtX = New-Object System.Windows.Forms.TextBox
$txtX.Location = New-Object System.Drawing.Point(95, 141)
$txtX.Size = New-Object System.Drawing.Size(245, 25)
$grpPerson.Controls.Add($txtX)

$btnFetchX = New-Object System.Windows.Forms.Button
$btnFetchX.Text = "名前取得"
$btnFetchX.Location = New-Object System.Drawing.Point(346, 140)
$btnFetchX.Size = New-Object System.Drawing.Size(88, 27)
$btnFetchX.BackColor = [System.Drawing.Color]::AliceBlue
$grpPerson.Controls.Add($btnFetchX)

$btnHistoryX = New-Object System.Windows.Forms.Button
$btnHistoryX.Text = "履歴検索..."
$btnHistoryX.Location = New-Object System.Drawing.Point(440, 140)
$btnHistoryX.Size = New-Object System.Drawing.Size(92, 27)
$grpPerson.Controls.Add($btnHistoryX)

$btnOpenX = New-Object System.Windows.Forms.Button
$btnOpenX.Text = "Xを開く"
$btnOpenX.Location = New-Object System.Drawing.Point(538, 140)
$btnOpenX.Size = New-Object System.Drawing.Size(82, 27)
$grpPerson.Controls.Add($btnOpenX)

$lblXHint = New-Object System.Windows.Forms.Label
$lblXHint.Text = "※XアカウントはURLを貼り付けても自動で @アカウント名 に変換されます。"
$lblXHint.Location = New-Object System.Drawing.Point(95, 170)
$lblXHint.Size = New-Object System.Drawing.Size(525, 18)
$lblXHint.ForeColor = [System.Drawing.Color]::Gray
$lblXHint.Font = New-Object System.Drawing.Font("Yu Gothic UI", 8.5)
$grpPerson.Controls.Add($lblXHint)

$lblComment = New-Object System.Windows.Forms.Label
$lblComment.Text = "コメント:"
$lblComment.Location = New-Object System.Drawing.Point(15, 200)
$lblComment.Size = New-Object System.Drawing.Size(75, 23)
$grpPerson.Controls.Add($lblComment)

$txtComment = New-Object System.Windows.Forms.TextBox
$txtComment.Location = New-Object System.Drawing.Point(95, 197)
$txtComment.Size = New-Object System.Drawing.Size(525, 175)
$txtComment.Multiline = $true
$txtComment.ScrollBars = "Vertical"
$grpPerson.Controls.Add($txtComment)

$btnOpenDevFolder = New-Object System.Windows.Forms.Button
$btnOpenDevFolder.Text = "現像後フォルダを開く"
$btnOpenDevFolder.Location = New-Object System.Drawing.Point(15, 632)
$btnOpenDevFolder.Size = New-Object System.Drawing.Size(170, 36)
$form.Controls.Add($btnOpenDevFolder)

$chkSent = New-Object System.Windows.Forms.CheckBox
$chkSent.Text = "データ送付済み"
$chkSent.Location = New-Object System.Drawing.Point(200, 639)
$chkSent.AutoSize = $true
$chkSent.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
$toolTip.SetToolTip($chkSent, "チェックを入れると「送付済」として写真情報.txtおよびExcel台帳の送付状況欄に記録されます")
$form.Controls.Add($chkSent)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "保存してExcel台帳を更新"
$btnSave.Location = New-Object System.Drawing.Point(365, 632)
$btnSave.Size = New-Object System.Drawing.Size(185, 36)
$btnSave.BackColor = [System.Drawing.Color]::SteelBlue
$btnSave.ForeColor = [System.Drawing.Color]::White
$btnSave.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnSave)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "閉じる"
$btnCancel.Location = New-Object System.Drawing.Point(560, 632)
$btnCancel.Size = New-Object System.Drawing.Size(90, 36)
$form.Controls.Add($btnCancel)

function Mark-Dirty {
    if (-not $script:IsUpdatingUI) { $script:IsDirty = $true }
}

foreach ($ctrl in @($txtDate, $txtMega, $txtGiga, $txtMemo, $cmbName, $cmbCostume, $txtX, $txtComment)) {
    $ctrl.Add_TextChanged({ Mark-Dirty })
}
$chkSent.Add_CheckedChanged({ Mark-Dirty })

function Update-CategoryLabels {
    switch ([string]$cmbCategory.SelectedItem) {
        "イベント" { $lblEvent.Text = "イベント名:"; $lblCostume.Text = "衣装名ORキャラ名:" }
        "個撮"     { $lblEvent.Text = "スタジオ名:"; $lblCostume.Text = "衣装名ORキャラ名:" }
        "併せ"     { $lblEvent.Text = "併せ名:";     $lblCostume.Text = "衣装名ORキャラ名:" }
        "その他"   { $lblEvent.Text = "場所:";       $lblCostume.Text = "衣装:" }
        default    { $lblEvent.Text = "イベント名:"; $lblCostume.Text = "衣装名ORキャラ名:" }
    }
}
$cmbCategory.Add_SelectedIndexChanged({
    Update-CategoryLabels
    Mark-Dirty
})

function Load-HistoryCandidatesToUI {
    $cmbCostume.Items.Clear()
    $cmbName.Items.Clear()
    if (Get-Command Get-SceneHistoryData -ErrorAction SilentlyContinue) {
        $hist = Get-SceneHistoryData -HistoryPath $EffectiveConfig.SceneHistoryPath -Config $EffectiveConfig
        if ($null -ne $hist) {
            foreach ($c in @($hist.Costumes)) { if (-not [string]::IsNullOrWhiteSpace([string]$c)) { [void]$cmbCostume.Items.Add([string]$c) } }
            foreach ($m in @($hist.Models))   { if (-not [string]::IsNullOrWhiteSpace([string]$m)) { [void]$cmbName.Items.Add([string]$m) } }
        }
    }
}

function Get-PersonDictVal {
    param([object]$PersonObj, [string]$Key)
    if ($null -eq $PersonObj -or [string]::IsNullOrWhiteSpace($Key)) { return "" }
    if ($PersonObj -is [System.Collections.IDictionary]) {
        if ($PersonObj.Contains($Key) -and $null -ne $PersonObj[$Key]) { return [string]$PersonObj[$Key] }
        return ""
    }
    $prop = $PersonObj.PSObject.Properties[$Key]
    if ($null -ne $prop -and $null -ne $prop.Value) { return [string]$prop.Value }
    return ""
}

function Ensure-PersonsList {
    if ($script:PersonsList -is [System.Collections.Generic.List[hashtable]]) {
        return
    }
    $newList = New-Object System.Collections.Generic.List[hashtable]
    if ($null -ne $script:PersonsList) {
        if ($script:PersonsList -is [System.Collections.IDictionary]) {
            $newList.Add(@{
                Name          = Get-PersonDictVal -PersonObj $script:PersonsList -Key "Name"
                CostumeOrChar = Get-PersonDictVal -PersonObj $script:PersonsList -Key "CostumeOrChar"
                XAccount      = Get-PersonDictVal -PersonObj $script:PersonsList -Key "XAccount"
                Comment       = Get-PersonDictVal -PersonObj $script:PersonsList -Key "Comment"
            })
        } elseif ($script:PersonsList -is [System.Collections.IEnumerable] -and -not ($script:PersonsList -is [string])) {
            foreach ($item in $script:PersonsList) {
                if ($null -eq $item) { continue }
                $newList.Add(@{
                    Name          = Get-PersonDictVal -PersonObj $item -Key "Name"
                    CostumeOrChar = Get-PersonDictVal -PersonObj $item -Key "CostumeOrChar"
                    XAccount      = Get-PersonDictVal -PersonObj $item -Key "XAccount"
                    Comment       = Get-PersonDictVal -PersonObj $item -Key "Comment"
                })
            }
        }
    }
    $script:PersonsList = $newList
}

function Update-MultiFolderButton {
    Ensure-PersonsList
    $script:RelatedFolders = @()
    $btnMultiFolder.Visible = $false
    if ($null -eq $script:PersonsList -or $script:PersonsList.Count -eq 0) { return }
    if ($script:CurrentPersonIndex -lt 0 -or $script:CurrentPersonIndex -ge $script:PersonsList.Count) { return }
    $curP = $script:PersonsList[$script:CurrentPersonIndex]
    if ($null -eq $curP) { return }
    $curModel = ConvertTo-CleanModelName (Get-PersonDictVal -PersonObj $curP -Key "Name")
    if ([string]::IsNullOrWhiteSpace($curModel)) { return }
    if (Get-Command Find-SameModelFoldersOnDate -ErrorAction SilentlyContinue) {
        $found = @(Find-SameModelFoldersOnDate `
            -CurrentFolder $script:Paired.Target `
            -DateStr $txtDate.Text.Trim() `
            -ModelName $curModel `
            -AdditionalRoots @($script:Paired.ImportFolder, $script:Paired.DevFolder) | Where-Object { $null -ne $_ })
        if (@($found).Count -gt 1) {
            $script:RelatedFolders = @($found)
            $btnMultiFolder.Text = "複数あり ($(@($found).Count)件)"
            $btnMultiFolder.Visible = $true
        }
    }
}

function Save-CurrentPersonToMemory {
    if ($script:IsUpdatingUI) { return }
    Ensure-PersonsList
    if ($null -eq $script:PersonsList -or $script:PersonsList.Count -eq 0) { return }
    $idx = $script:CurrentPersonIndex
    if ($idx -ge 0 -and $idx -lt $script:PersonsList.Count) {
        if ($null -eq $script:PersonsList[$idx] -or -not ($script:PersonsList[$idx] -is [System.Collections.IDictionary])) {
            $script:PersonsList[$idx] = @{ Name = ""; CostumeOrChar = ""; XAccount = ""; Comment = "" }
        }
        $script:PersonsList[$idx]["Name"]          = $cmbName.Text.Trim()
        $script:PersonsList[$idx]["CostumeOrChar"] = $cmbCostume.Text.Trim()
        $script:PersonsList[$idx]["XAccount"]      = ConvertTo-NormalizedX $txtX.Text
        $script:PersonsList[$idx]["Comment"]       = $txtComment.Text.Trim()
    }
}

function Refresh-PersonCombo([int]$SelectIdx) {
    $script:IsUpdatingUI = $true
    try {
        Ensure-PersonsList
        if ($script:PersonsList.Count -eq 0) {
            $script:PersonsList.Add(@{ Name = ""; CostumeOrChar = ""; XAccount = ""; Comment = "" })
        }
        $cmbPerson.Items.Clear()
        for ($i = 0; $i -lt $script:PersonsList.Count; $i++) {
            $p = $script:PersonsList[$i]
            if ($null -eq $p -or -not ($p -is [System.Collections.IDictionary])) {
                $p = @{
                    Name          = Get-PersonDictVal -PersonObj $p -Key "Name"
                    CostumeOrChar = Get-PersonDictVal -PersonObj $p -Key "CostumeOrChar"
                    XAccount      = Get-PersonDictVal -PersonObj $p -Key "XAccount"
                    Comment       = Get-PersonDictVal -PersonObj $p -Key "Comment"
                }
                $script:PersonsList[$i] = $p
            }
            $pNameVal = Get-PersonDictVal -PersonObj $p -Key "Name"
            $pCosVal  = Get-PersonDictVal -PersonObj $p -Key "CostumeOrChar"
            $pXVal    = Get-PersonDictVal -PersonObj $p -Key "XAccount"
            $dName = if ([string]::IsNullOrWhiteSpace($pNameVal)) { "未入力" } else { $pNameVal }
            $dCos  = if ([string]::IsNullOrWhiteSpace($pCosVal))  { "" } else { " [" + $pCosVal + "]" }
            $dX    = if ([string]::IsNullOrWhiteSpace($pXVal))    { "" } else { " (" + $pXVal + ")" }
            [void]$cmbPerson.Items.Add(("{0}人目: {1}{2}{3}" -f ($i + 1), $dName, $dCos, $dX))
        }
        if ($SelectIdx -lt 0) { $SelectIdx = 0 }
        if ($SelectIdx -ge $script:PersonsList.Count) { $SelectIdx = $script:PersonsList.Count - 1 }
        $script:CurrentPersonIndex = $SelectIdx
        $cmbPerson.SelectedIndex = $SelectIdx

        $cur = $script:PersonsList[$SelectIdx]
        $cmbName.Text    = Get-PersonDictVal -PersonObj $cur -Key "Name"
        $cmbCostume.Text = Get-PersonDictVal -PersonObj $cur -Key "CostumeOrChar"
        $txtX.Text       = Get-PersonDictVal -PersonObj $cur -Key "XAccount"
        $txtComment.Text = Get-PersonDictVal -PersonObj $cur -Key "Comment"
    } finally {
        $script:IsUpdatingUI = $false
    }
    Update-MultiFolderButton
}

function Try-AutoFillSameDayCostume {
    if ($script:IsUpdatingUI) { return }
    $modelName = ConvertTo-CleanModelName $cmbName.Text
    if ([string]::IsNullOrWhiteSpace($modelName)) { return }
    if (-not [string]::IsNullOrWhiteSpace($cmbCostume.Text)) { return }

    $autoCos = Find-SameDayCostumeForModel `
        -ModelName $modelName `
        -DateStr $txtDate.Text.Trim() `
        -PairedObj $script:Paired `
        -CurrentPersons $script:PersonsList `
        -ExcludeIndex $script:CurrentPersonIndex

    if (-not [string]::IsNullOrWhiteSpace($autoCos)) {
        $cmbCostume.Text = $autoCos
    }
}

function Load-FolderIntoEditor([string]$FolderToLoad) {
    $script:IsUpdatingUI = $true
    try {
        $script:Paired = Resolve-PairedPhotoFolders -Folder $FolderToLoad -EffectiveConfig $EffectiveConfig
        $form.Text = "被写体プロパティ - 写真情報エディタ - " + $script:Paired.FolderName
        $lblPath.Text = "対象フォルダ: " + $script:Paired.Target
        $tipMsg = "対象: $($script:Paired.Target)`r`n取込: $($script:Paired.ImportFolder)`r`n現像後: $($script:Paired.DevFolder)"
        $toolTip.SetToolTip($lblPath, $tipMsg)

        $loadedPath = Sync-PhotoInfoFiles -PairedObj $script:Paired
        $parsed = Read-PhotoInfoData -FilePath $loadedPath -PairedObj $script:Paired
        $scRes = Resolve-SceneFromFolders -PairedObj $script:Paired

        if (-not [string]::IsNullOrWhiteSpace([string]$scRes.SceneName)) {
            $parsed.EventName = [string]$scRes.SceneName
            if (-not [string]::IsNullOrWhiteSpace([string]$scRes.Category)) {
                $parsed.Category = [string]$scRes.Category
            }
            $cmbCategory.Enabled = $false
        } else {
            $cmbCategory.Enabled = $true
        }
        if ([string]::IsNullOrWhiteSpace($parsed.MegaLink) -and -not [string]::IsNullOrWhiteSpace($script:Paired.DevFolder) -and (Test-Path -LiteralPath $script:Paired.DevFolder)) {
            $devInfo = Join-Path $script:Paired.DevFolder "写真情報.txt"
            if (Test-Path -LiteralPath $devInfo) {
                $devParsed = Read-PhotoInfoData -FilePath $devInfo -PairedObj $script:Paired
                if (-not [string]::IsNullOrWhiteSpace($devParsed.MegaLink)) { $parsed.MegaLink = $devParsed.MegaLink }
                if ([string]::IsNullOrWhiteSpace($parsed.GigaFileLink) -and -not [string]::IsNullOrWhiteSpace($devParsed.GigaFileLink)) {
                    $parsed.GigaFileLink = $devParsed.GigaFileLink
                }
                if ([string]::IsNullOrWhiteSpace($loadedPath) -and ($parsed.SentStatus -ne "送付済み") -and ($devParsed.SentStatus -eq "送付済み" -or $devParsed.SentStatus -eq "送付済")) {
                    $parsed.SentStatus = "送付済み"
                }
            }
        }

        if ($cmbCategory.Items.Contains($parsed.Category)) { $cmbCategory.SelectedItem = $parsed.Category }
        else { $cmbCategory.SelectedIndex = 0 }
        Update-CategoryLabels

        $txtDate.Text  = $parsed.DateStr
        $txtEvent.Text = $parsed.EventName
        $txtMega.Text  = $parsed.MegaLink
        $txtGiga.Text  = $parsed.GigaFileLink
        $txtMemo.Text  = $parsed.Memo
        $chkSent.Checked = ($parsed.SentStatus -eq "送付済み" -or $parsed.SentStatus -eq "送付済" -or $parsed.SentStatus -eq "True" -or $parsed.SentStatus -eq "1" -or $parsed.SentStatus -eq "●")

        $safePersons = New-Object System.Collections.Generic.List[hashtable]
        if ($null -ne $parsed -and $null -ne $parsed.Persons) {
            foreach ($pp in @($parsed.Persons)) {
                if ($null -eq $pp) { continue }
                $safePersons.Add(@{
                    Name          = Get-PersonDictVal -PersonObj $pp -Key "Name"
                    CostumeOrChar = Get-PersonDictVal -PersonObj $pp -Key "CostumeOrChar"
                    XAccount      = Get-PersonDictVal -PersonObj $pp -Key "XAccount"
                    Comment       = Get-PersonDictVal -PersonObj $pp -Key "Comment"
                })
            }
        }
        if ($safePersons.Count -eq 0) {
            $safePersons.Add(@{ Name = ""; CostumeOrChar = ""; XAccount = ""; Comment = "" })
        }
        $script:PersonsList = $safePersons
        Write-EditorLog "フォルダ読込完了: Target=$($script:Paired.Target), Scene=$($parsed.EventName), Persons=$($script:PersonsList.Count)"
    } finally {
        $script:IsUpdatingUI = $false
    }
    Refresh-PersonCombo 0
    $script:IsDirty = $false
}

$cmbPerson.Add_SelectedIndexChanged({
    if ($script:IsUpdatingUI) { return }
    $newIdx = $cmbPerson.SelectedIndex
    if ($newIdx -ge 0 -and $newIdx -ne $script:CurrentPersonIndex) {
        Save-CurrentPersonToMemory
        Refresh-PersonCombo $newIdx
    }
})

$btnAddPerson.Add_Click({
    Save-CurrentPersonToMemory
    $script:PersonsList.Add(@{ Name = ""; CostumeOrChar = ""; XAccount = ""; Comment = "" })
    Refresh-PersonCombo ($script:PersonsList.Count - 1)
    Mark-Dirty
})

$btnDelPerson.Add_Click({
    if ($script:PersonsList.Count -le 1) {
        $script:PersonsList[0] = @{ Name = ""; CostumeOrChar = ""; XAccount = ""; Comment = "" }
        Refresh-PersonCombo 0
        Mark-Dirty
        return
    }
    $script:PersonsList.RemoveAt($script:CurrentPersonIndex)
    Refresh-PersonCombo ([Math]::Max(0, $script:CurrentPersonIndex - 1))
    Mark-Dirty
})

$cmbName.Add_SelectedIndexChanged({
    if ($script:IsUpdatingUI) { return }
    Try-AutoFillSameDayCostume
    Save-CurrentPersonToMemory
    Refresh-PersonCombo $script:CurrentPersonIndex
})

$cmbName.Add_Leave({
    if ($script:IsUpdatingUI) { return }
    Try-AutoFillSameDayCostume
    Save-CurrentPersonToMemory
    Refresh-PersonCombo $script:CurrentPersonIndex
})

$cmbCostume.Add_Leave({
    if ($script:IsUpdatingUI) { return }
    Save-CurrentPersonToMemory
    Refresh-PersonCombo $script:CurrentPersonIndex
})

$txtX.Add_Leave({
    if ($script:IsUpdatingUI) { return }
    $norm = ConvertTo-NormalizedX $txtX.Text
    if (-not [string]::IsNullOrWhiteSpace($norm)) { $txtX.Text = $norm }
    Save-CurrentPersonToMemory
    Refresh-PersonCombo $script:CurrentPersonIndex
})

$btnOpenDailyScene.Add_Click({
    $dateAnchor = Find-DateFolderAncestor -StartFolder $script:Paired.Target
    if ([string]::IsNullOrWhiteSpace($dateAnchor)) { $dateAnchor = $script:Paired.Target }
    [void](Start-DailyWorkflowForScene -TargetPathForDaily $dateAnchor)
})

$btnMultiFolder.Add_Click({
    if ($null -eq $script:RelatedFolders -or @($script:RelatedFolders).Count -le 1) { return }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "同一モデルの関連フォルダ一覧（選択して切り替え）"
    $dlg.Size = New-Object System.Drawing.Size(640, 320)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Location = New-Object System.Drawing.Point(12, 12)
    $lv.Size = New-Object System.Drawing.Size(600, 215)
    $lv.View = [System.Windows.Forms.View]::Details
    $lv.FullRowSelect = $true
    $lv.GridLines = $true
    [void]$lv.Columns.Add("状態", 70)
    [void]$lv.Columns.Add("衣装・キャラ名", 180)
    [void]$lv.Columns.Add("フォルダパス", 340)

    foreach ($rf in $script:RelatedFolders) {
        $fp = [string]$rf.FolderPath
        $st = if ($fp -ieq $script:Paired.Target) { "編集中" } else { "関連" }
        $item = New-Object System.Windows.Forms.ListViewItem($st)
        [void]$item.SubItems.Add([string]$rf.CostumeOrChar)
        [void]$item.SubItems.Add($fp)
        $item.Tag = $fp
        [void]$lv.Items.Add($item)
    }
    $dlg.Controls.Add($lv)

    $btnSwitch = New-Object System.Windows.Forms.Button
    $btnSwitch.Text = "選択したフォルダに切り替える"
    $btnSwitch.Location = New-Object System.Drawing.Point(345, 238)
    $btnSwitch.Size = New-Object System.Drawing.Size(180, 32)
    $btnSwitch.BackColor = [System.Drawing.Color]::SteelBlue
    $btnSwitch.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnSwitch)

    $btnCloseDlg = New-Object System.Windows.Forms.Button
    $btnCloseDlg.Text = "閉じる"
    $btnCloseDlg.Location = New-Object System.Drawing.Point(532, 238)
    $btnCloseDlg.Size = New-Object System.Drawing.Size(80, 32)
    $dlg.Controls.Add($btnCloseDlg)

    $switchAction = {
        if ($lv.SelectedItems.Count -gt 0) {
            $nextPath = [string]$lv.SelectedItems[0].Tag
            $dlg.Close()
            if (-not [string]::IsNullOrWhiteSpace($nextPath) -and (Test-Path -LiteralPath $nextPath)) {
                Load-FolderIntoEditor $nextPath
            }
        }
    }
    $btnSwitch.Add_Click($switchAction)
    $lv.Add_DoubleClick($switchAction)
    $btnCloseDlg.Add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog($form)
})

$btnFetchX.Add_Click({
    $normX = ""
    try {
        $normX = ConvertTo-NormalizedX $txtX.Text
        if ([string]::IsNullOrWhiteSpace($normX)) {
            Show-MsgBox -Text "Xアカウントを入力してください。" -Title "入力確認" -Buttons "OK" -Icon "Warning" -Owner $form | Out-Null
            return
        }
        Write-EditorLog "X名前取得開始: $normX (Target=$($script:Paired.Target))"
        $txtX.Text = $normX
        $btnFetchX.Enabled = $false
        $btnFetchX.Text = "取得中..."
        $form.Refresh()

        $fetched = ""
        if (Get-Command Get-XDisplayName -ErrorAction SilentlyContinue) {
            $rawRes = Get-XDisplayName $normX $EffectiveConfig
            if ($rawRes -is [System.Collections.IDictionary] -and $rawRes.Contains("Name")) { $fetched = [string]$rawRes["Name"] }
            elseif ($rawRes -is [array]) { $fetched = ($rawRes -join " ").Trim() }
            elseif ($null -ne $rawRes) { $fetched = [string]$rawRes }
        }

        $cleanName = ConvertTo-CleanModelName $fetched
        if (-not [string]::IsNullOrWhiteSpace($cleanName)) {
            $cmbName.Text = $cleanName
            Try-AutoFillSameDayCostume
            Save-CurrentPersonToMemory
            Refresh-PersonCombo $script:CurrentPersonIndex
            Mark-Dirty
            if (Get-Command Save-XHistory -ErrorAction SilentlyContinue) {
                Save-XHistory $normX $cleanName $EffectiveConfig $txtDate.Text.Trim()
            }
            Write-EditorLog "X名前取得完了: $normX -> $cleanName"
        } else {
            Write-EditorLog "X名前取得結果が空でした: $normX" "WARN"
            Show-MsgBox -Text "Xから表示名を取得できませんでした。" -Title "取得結果" -Buttons "OK" -Icon "Information" -Owner $form | Out-Null
        }
    } catch {
        Show-EditorErrorDialog -TitlePrefix "X表示名取得エラー" -ErrorRecord $_ -Context @{
            Action             = "FetchX"
            TargetFolder       = [string]$script:Paired.Target
            RawXInput          = [string]$txtX.Text
            NormalizedX        = [string]$normX
            DateStr            = [string]$txtDate.Text
            CurrentPersonIndex = $script:CurrentPersonIndex
            PersonsCount       = if ($null -ne $script:PersonsList) { @($script:PersonsList).Count } else { -1 }
            XHistoryPath       = [string]$EffectiveConfig.XHistoryPath
        }
    } finally {
        $btnFetchX.Enabled = $true
        $btnFetchX.Text = "名前取得"
    }
})

$btnHistoryX.Add_Click({
    try {
        if (Get-Command Show-XHistoryDialog -ErrorAction SilentlyContinue) {
            $sel = Show-XHistoryDialog -Config $EffectiveConfig -FilterDate $txtDate.Text.Trim()
            if ($null -ne $sel) {
                $selAcc  = if ($sel -is [System.Collections.IDictionary]) { if ($sel.Contains("account")) { [string]$sel["account"] } else { "" } } else { [string]$sel.account }
                $selName = if ($sel -is [System.Collections.IDictionary]) { if ($sel.Contains("name")) { [string]$sel["name"] } else { "" } } else { [string]$sel.name }
                if (-not [string]::IsNullOrWhiteSpace($selAcc))  { $txtX.Text = ConvertTo-NormalizedX $selAcc }
                if (-not [string]::IsNullOrWhiteSpace($selName)) { $cmbName.Text = ConvertTo-CleanModelName $selName }
                Try-AutoFillSameDayCostume
                Save-CurrentPersonToMemory
                Refresh-PersonCombo $script:CurrentPersonIndex
                Mark-Dirty
                Write-EditorLog "X履歴検索から反映: $selAcc / $selName"
            }
        }
    } catch {
        Show-EditorErrorDialog -TitlePrefix "履歴検索エラー" -ErrorRecord $_ -Context @{
            Action       = "HistorySearch"
            TargetFolder = [string]$script:Paired.Target
            DateStr      = [string]$txtDate.Text
            XHistoryPath = [string]$EffectiveConfig.XHistoryPath
        }
    }
})

$btnOpenX.Add_Click({
    $normX = ConvertTo-NormalizedX $txtX.Text
    if (-not [string]::IsNullOrWhiteSpace($normX)) {
        Start-Process ("https://x.com/" + $normX.TrimStart('@'))
    }
})

$btnGetMega.Add_Click({
    try {
        $btnGetMega.Enabled = $false
        $btnGetMega.Text = "取得中..."
        $form.Refresh()
        $megaTarget = if (-not [string]::IsNullOrWhiteSpace($script:Paired.DevFolder) -and (Test-Path -LiteralPath $script:Paired.DevFolder)) {
            $script:Paired.DevFolder
        } else {
            $script:Paired.Target
        }
        $megaUrl = ""
        $diagMsg = ""
        if (Get-Command Get-MegaFolderLink -ErrorAction SilentlyContinue) {
            $res = Get-MegaFolderLink -FolderPath $megaTarget -Config $EffectiveConfig
            if ($res -is [System.Collections.IDictionary]) {
                if ($res.Contains("Url"))     { $megaUrl = [string]$res["Url"] }
                if ($res.Contains("Message")) { $diagMsg = [string]$res["Message"] }
            } else {
                $diagMsg = [string]$res
                if ($diagMsg -match '(https?://mega\.nz/[^\s\)\]]+)') { $megaUrl = $Matches[1] }
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($megaUrl)) {
            $txtMega.Text = $megaUrl
            [System.Windows.Forms.Clipboard]::SetText($megaUrl)
            Mark-Dirty
            Write-EditorLog "MEGAリンク取得成功: $megaUrl"
            Show-MsgBox -Text "MEGAリンクを取得し、コピーしました。`n`n$megaUrl" -Title "MEGAリンク取得完了" -Buttons "OK" -Icon "Information" -Owner $form | Out-Null
        } else {
            if ([string]::IsNullOrWhiteSpace($diagMsg)) { $diagMsg = "リンクを取得できませんでした。ログ: " + $EffectiveConfig.MegaLogPath }
            Write-EditorLog "MEGAリンク診断結果: $diagMsg" "WARN"
            Show-MsgBox -Text $diagMsg -Title "MEGAリンク診断結果" -Buttons "OK" -Icon "Warning" -Owner $form | Out-Null
        }
    } catch {
        Show-EditorErrorDialog -TitlePrefix "MEGA取得エラー" -ErrorRecord $_ -Context @{
            Action       = "GetMega"
            TargetFolder = [string]$script:Paired.Target
            DevFolder    = [string]$script:Paired.DevFolder
        }
    } finally {
        $btnGetMega.Enabled = $true
        $btnGetMega.Text = "リンク取得/診断"
    }
})

$btnCopyMega.Add_Click({
    $u = $txtMega.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($u)) {
        [System.Windows.Forms.Clipboard]::SetText($u)
        Show-MsgBox -Text "MEGAリンクをコピーしました。" -Title "コピー完了" -Buttons "OK" -Icon "Information" -Owner $form | Out-Null
    }
})

$btnSendGiga.Add_Click({
    try {
        $targetForUpload = if (-not [string]::IsNullOrWhiteSpace($script:Paired.DevFolder) -and (Test-Path -LiteralPath $script:Paired.DevFolder)) { $script:Paired.DevFolder } else { $script:Paired.Target }
        if ([string]::IsNullOrWhiteSpace($targetForUpload) -or -not (Test-Path -LiteralPath $targetForUpload)) {
            Show-MsgBox -Text "アップロード対象フォルダが見つかりません。" -Title "確認" -Buttons "OK" -Icon "Warning" -Owner $form | Out-Null
            return
        }
        $btnSendGiga.Enabled = $false
        $btnSendGiga.Text = "送信待機中..."
        $form.Refresh()

        $gigaRes = $null
        if (Get-Command Invoke-GigaFileUploadForFolder -ErrorAction SilentlyContinue) {
            $gigaRes = Invoke-GigaFileUploadForFolder -TargetFolder $targetForUpload -Config $EffectiveConfig
        }
        if ($null -ne $gigaRes -and -not [string]::IsNullOrWhiteSpace([string]$gigaRes.Url)) {
            $txtGiga.Text = [string]$gigaRes.Url
            $chkSent.Checked = $true
            [System.Windows.Forms.Clipboard]::SetText([string]$gigaRes.Url)
            $passNote = if (-not [string]::IsNullOrWhiteSpace([string]$gigaRes.Password))     { " / PW: $($gigaRes.Password)" } else { "" }
            $daysNote = if ([int]$gigaRes.LifetimeDays -gt 0)                               { " / 期限: $($gigaRes.LifetimeDays)日" } else { "" }
            $delNote  = if (-not [string]::IsNullOrWhiteSpace([string]$gigaRes.DelKey))       { " / 削除キー: $($gigaRes.DelKey)" } else { "" }
            $memoLine = "【ギガファイル便】$($gigaRes.Url)${passNote}${daysNote}${delNote}"
            $curMemo = $txtMemo.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($curMemo)) { $txtMemo.Text = $memoLine }
            elseif ($curMemo -notmatch [regex]::Escape([string]$gigaRes.Url)) { $txtMemo.Text = $curMemo + "`r`n" + $memoLine }
            Mark-Dirty
            Write-EditorLog "ギガファイル便連携完了: $($gigaRes.Url)"
            Show-MsgBox -Text "ギガファイル便のURLを取得し、プロパティ画面へ反映しました。`n`n$($gigaRes.Url)" -Title "ギガファイル便連携完了" -Buttons "OK" -Icon "Information" -Owner $form | Out-Null
        }
    } catch {
        Show-EditorErrorDialog -TitlePrefix "ギガファイル便連携エラー" -ErrorRecord $_ -Context @{
            Action       = "SendGiga"
            TargetFolder = [string]$script:Paired.Target
            DevFolder    = [string]$script:Paired.DevFolder
        }
    } finally {
        $btnSendGiga.Enabled = $true
        $btnSendGiga.Text = "ギガファイル便で送る"
    }
})

$btnCopyGiga.Add_Click({
    $u = $txtGiga.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($u)) {
        [System.Windows.Forms.Clipboard]::SetText($u)
        Show-MsgBox -Text "ギガファイル便URLをコピーしました。" -Title "コピー完了" -Buttons "OK" -Icon "Information" -Owner $form | Out-Null
    }
})

$btnOpenDevFolder.Add_Click({
    $devDir = [string]$script:Paired.DevFolder
    if ([string]::IsNullOrWhiteSpace($devDir)) {
        Show-MsgBox -Text "現像後フォルダのパスが解決できませんでした。" -Title "確認" -Buttons "OK" -Icon "Warning" -Owner $form | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $devDir)) {
        $ans = Show-MsgBox -Text "現像後フォルダがまだ存在しません。新規作成して開きますか？`n`n$devDir" -Title "フォルダ作成確認" -Buttons "YesNo" -Icon "Question" -Owner $form
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        New-Item -ItemType Directory -Path $devDir -Force | Out-Null
    }
    Start-Process "explorer.exe" -ArgumentList "`"$devDir`""
})

$btnSave.Add_Click({
    try {
        Save-CurrentPersonToMemory
        Update-MultiFolderButton
        $formData = @{
            Category     = [string]$cmbCategory.SelectedItem
            DateStr      = $txtDate.Text.Trim()
            EventName    = $txtEvent.Text.Trim()
            MegaLink     = $txtMega.Text.Trim()
            GigaFileLink = $txtGiga.Text.Trim()
            SentStatus   = if ($chkSent.Checked) { "送付済み" } else { "未送付" }
            Memo         = $txtMemo.Text.Trim()
        }
        [void](Save-AllPhotoInfoAndLedger `
            -FormData $formData `
            -PersonsList $script:PersonsList `
            -PairedObj $script:Paired `
            -EffectiveConfig $EffectiveConfig `
            -RelatedFolders $script:RelatedFolders)
        Write-EditorLog "写真情報・Excel台帳保存完了: Target=$($script:Paired.Target), Sent=$($formData.SentStatus), Persons=$($script:PersonsList.Count)"
        $script:IsDirty = $false
        $form.Close()
    } catch {
        Show-EditorErrorDialog -TitlePrefix "保存エラー" -ErrorRecord $_ -Context @{
            Action       = "SavePhotoInfo"
            TargetFolder = [string]$script:Paired.Target
            DevFolder    = [string]$script:Paired.DevFolder
            ExcelPath    = [string]$EffectiveConfig.ExcelPath
            PersonsCount = if ($null -ne $script:PersonsList) { @($script:PersonsList).Count } else { -1 }
        } -DialogTitle "保存エラー"
    }
})

$form.Add_FormClosing({
    param($sender, $e)
    if ($script:IsDirty) {
        $ans = [System.Windows.Forms.MessageBox]::Show($form, "未保存の変更があります。保存せずに閉じますか？", "確認", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
            $e.Cancel = $true
        }
    }
})

$btnCancel.Add_Click({
    $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Close()
})

if (-not [string]::IsNullOrWhiteSpace($TargetFolder) -and (Test-Path -LiteralPath $TargetFolder -PathType Container)) {
    $initSceneRes = Resolve-SceneFromFolders -PairedObj $script:Paired
    if ([string]::IsNullOrWhiteSpace([string]$initSceneRes.SourceFile) -or [string]::IsNullOrWhiteSpace([string]$initSceneRes.SceneName)) {
        $dateAnchor = Find-DateFolderAncestor -StartFolder $script:Paired.Target
        if (-not $ForceEditor) {
            Show-MsgBox -Text "このフォルダに対応する scene.txt（イベント・併せ・スタジオ・場所）が登録されていません。`n`nDailyWorkflow から scene.txt を登録してください。DailyWorkflow を開きます。" -Title "scene.txt 未登録" -Buttons "OK" -Icon "Information" | Out-Null
            [void](Start-DailyWorkflowForScene -TargetPathForDaily $dateAnchor)
        } else {
            Show-MsgBox -Text "このフォルダに対応する scene.txt（イベント・併せ・スタジオ・場所）が登録されていません。`n`n開いている DailyWorkflow 上部の「scene.txt 配置・登録」から先に保存してください。" -Title "scene.txt 未登録" -Buttons "OK" -Icon "Warning" | Out-Null
        }
        exit 0
    }
}

Load-HistoryCandidatesToUI
Load-FolderIntoEditor $TargetFolder
[void]$form.ShowDialog()
