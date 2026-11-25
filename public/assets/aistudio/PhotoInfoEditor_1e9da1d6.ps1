#requires -Version 5.1
param(
    [Parameter(Position = 0)]
    [Alias("TargetPath", "FolderPath", "Path", "TargetDir")]
    [string]$TargetFolder = "",
    [string]$ModuleName = "",
    [hashtable]$Config = @{},
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

$logicPath = Join-Path $RootDir "common\PhotoEditorLogic.ps1"
if (-not (Test-Path -LiteralPath $logicPath)) {
    [System.Windows.Forms.MessageBox]::Show("ロジックファイルが見つかりません:`n$logicPath", "起動エラー", "OK", "Error") | Out-Null
    exit 1
}
. $logicPath

if ([string]::IsNullOrWhiteSpace($TargetFolder) -and $null -ne $RemainingArgs -and $RemainingArgs.Count -gt 0) {
    foreach ($arg in $RemainingArgs) {
        $s = [string]$arg
        if (-not [string]::IsNullOrWhiteSpace($s) -and -not $s.StartsWith("-")) {
            $TargetFolder = $s
            break
        }
    }
}
$TargetFolder = $TargetFolder.Trim().Trim('"').TrimEnd('\')

$EffectiveConfig = Initialize-PhotoEditorEnvironment -ScriptDir $ScriptDir -ExternalConfig $Config
$script:Paired = Resolve-PairedPhotoFolders -Folder $TargetFolder -EffectiveConfig $EffectiveConfig
$script:PersonsList = New-Object System.Collections.Generic.List[hashtable]
$script:CurrentPersonIndex = 0
$script:IsUpdatingUI = $false
$script:RelatedFolders = @()

$form = New-Object System.Windows.Forms.Form
$form.Text = "写真情報登録・編集 - " + $script:Paired.FolderName
$form.Size = New-Object System.Drawing.Size(680, 665)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5)

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Location = New-Object System.Drawing.Point(15, 12)
$lblPath.Size = New-Object System.Drawing.Size(635, 22)
$lblPath.ForeColor = [System.Drawing.Color]::DimGray
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

$cmbEvent = New-Object System.Windows.Forms.ComboBox
$cmbEvent.Location = New-Object System.Drawing.Point(105, 75)
$cmbEvent.Size = New-Object System.Drawing.Size(545, 25)
$cmbEvent.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
$form.Controls.Add($cmbEvent)

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

$grpPerson = New-Object System.Windows.Forms.GroupBox
$grpPerson.Text = "被写体・参加者情報（複数人登録・枠連動対応）"
$grpPerson.Location = New-Object System.Drawing.Point(15, 182)
$grpPerson.Size = New-Object System.Drawing.Size(635, 382)
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
$txtComment.Size = New-Object System.Drawing.Size(525, 165)
$txtComment.Multiline = $true
$txtComment.ScrollBars = "Vertical"
$grpPerson.Controls.Add($txtComment)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "保存してExcel台帳を更新"
$btnSave.Location = New-Object System.Drawing.Point(365, 576)
$btnSave.Size = New-Object System.Drawing.Size(185, 36)
$btnSave.BackColor = [System.Drawing.Color]::SteelBlue
$btnSave.ForeColor = [System.Drawing.Color]::White
$btnSave.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnSave)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "閉じる"
$btnCancel.Location = New-Object System.Drawing.Point(560, 576)
$btnCancel.Size = New-Object System.Drawing.Size(90, 36)
$form.Controls.Add($btnCancel)

function Update-CategoryLabels {
    switch ([string]$cmbCategory.SelectedItem) {
        "イベント" { $lblEvent.Text = "イベント名:"; $lblCostume.Text = "衣装名ORキャラ名:" }
        "個撮"     { $lblEvent.Text = "スタジオ名:"; $lblCostume.Text = "衣装名ORキャラ名:" }
        "併せ"     { $lblEvent.Text = "併せ名:";     $lblCostume.Text = "衣装名ORキャラ名:" }
        "その他"   { $lblEvent.Text = "場所:";       $lblCostume.Text = "衣装:" }
        default    { $lblEvent.Text = "イベント名:"; $lblCostume.Text = "衣装名ORキャラ名:" }
    }
}
$cmbCategory.Add_SelectedIndexChanged({ Update-CategoryLabels })

function Load-HistoryCandidatesToUI {
    $cmbEvent.Items.Clear()
    $cmbCostume.Items.Clear()
    $cmbName.Items.Clear()
    if (Get-Command Get-SceneHistoryData -ErrorAction SilentlyContinue) {
        $hist = Get-SceneHistoryData -HistoryPath $EffectiveConfig.SceneHistoryPath
        if ($null -ne $hist) {
            foreach ($s in @($hist.Scenes))   { if (-not [string]::IsNullOrWhiteSpace([string]$s)) { [void]$cmbEvent.Items.Add([string]$s) } }
            foreach ($c in @($hist.Costumes)) { if (-not [string]::IsNullOrWhiteSpace([string]$c)) { [void]$cmbCostume.Items.Add([string]$c) } }
            foreach ($m in @($hist.Models))   { if (-not [string]::IsNullOrWhiteSpace([string]$m)) { [void]$cmbName.Items.Add([string]$m) } }
        }
    }
}

function Update-MultiFolderButton {
    $script:RelatedFolders = @()
    $btnMultiFolder.Visible = $false
    if ($script:PersonsList.Count -eq 0) { return }
    $curModel = ConvertTo-CleanModelName ([string]$script:PersonsList[$script:CurrentPersonIndex]["Name"])
    if ([string]::IsNullOrWhiteSpace($curModel)) { return }
    if (Get-Command Find-SameModelFoldersOnDate -ErrorAction SilentlyContinue) {
        $found = @(Find-SameModelFoldersOnDate -CurrentFolder $script:Paired.Target -ModelName $curModel -DateStr $txtDate.Text.Trim())
        if ($found.Count -gt 1) {
            $script:RelatedFolders = $found
            $btnMultiFolder.Text = "複数あり ($($found.Count)件)"
            $btnMultiFolder.Visible = $true
        }
    }
}

function Save-CurrentPersonToMemory {
    if ($script:IsUpdatingUI) { return }
    $idx = $script:CurrentPersonIndex
    if ($idx -ge 0 -and $idx -lt $script:PersonsList.Count) {
        $script:PersonsList[$idx]["Name"]          = $cmbName.Text.Trim()
        $script:PersonsList[$idx]["CostumeOrChar"] = $cmbCostume.Text.Trim()
        $script:PersonsList[$idx]["XAccount"]      = ConvertTo-NormalizedX $txtX.Text
        $script:PersonsList[$idx]["Comment"]       = $txtComment.Text.Trim()
    }
}

function Refresh-PersonCombo([int]$SelectIdx) {
    $script:IsUpdatingUI = $true
    try {
        $cmbPerson.Items.Clear()
        for ($i = 0; $i -lt $script:PersonsList.Count; $i++) {
            $p = $script:PersonsList[$i]
            $dName = if ([string]::IsNullOrWhiteSpace($p["Name"])) { "未入力" } else { $p["Name"] }
            $dCos  = if ([string]::IsNullOrWhiteSpace($p["CostumeOrChar"])) { "" } else { " [" + $p["CostumeOrChar"] + "]" }
            $dX    = if ([string]::IsNullOrWhiteSpace($p["XAccount"])) { "" } else { " (" + $p["XAccount"] + ")" }
            [void]$cmbPerson.Items.Add(("{0}人目: {1}{2}{3}" -f ($i + 1), $dName, $dCos, $dX))
        }
        if ($SelectIdx -lt 0) { $SelectIdx = 0 }
        if ($SelectIdx -ge $script:PersonsList.Count) { $SelectIdx = $script:PersonsList.Count - 1 }
        $script:CurrentPersonIndex = $SelectIdx
        $cmbPerson.SelectedIndex = $SelectIdx

        $cur = $script:PersonsList[$SelectIdx]
        $cmbName.Text    = [string]$cur["Name"]
        $cmbCostume.Text = [string]$cur["CostumeOrChar"]
        $txtX.Text       = [string]$cur["XAccount"]
        $txtComment.Text = [string]$cur["Comment"]
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
    $script:Paired = Resolve-PairedPhotoFolders -Folder $FolderToLoad -EffectiveConfig $EffectiveConfig
    $form.Text = "写真情報登録・編集 - " + $script:Paired.FolderName
    $lblPath.Text = "対象フォルダ: " + $script:Paired.Target

    $loadedPath = Sync-PhotoInfoFiles -PairedObj $script:Paired
    $parsed = Read-PhotoInfoData -FilePath $loadedPath -PairedObj $script:Paired
    $scRes = Resolve-SceneFromFolders -PairedObj $script:Paired

    if ([string]::IsNullOrWhiteSpace($parsed.EventName) -and -not [string]::IsNullOrWhiteSpace([string]$scRes.SceneName)) {
        $parsed.EventName = [string]$scRes.SceneName
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$scRes.Category) -and $parsed.Category -eq "イベント") {
        $parsed.Category = [string]$scRes.Category
    }
    if ([string]::IsNullOrWhiteSpace($parsed.MegaLink) -and -not [string]::IsNullOrWhiteSpace($script:Paired.DevFolder) -and (Test-Path -LiteralPath $script:Paired.DevFolder)) {
        $devInfo = Join-Path $script:Paired.DevFolder "写真情報.txt"
        if (Test-Path -LiteralPath $devInfo) {
            $devParsed = Read-PhotoInfoData -FilePath $devInfo -PairedObj $script:Paired
            if (-not [string]::IsNullOrWhiteSpace($devParsed.MegaLink)) { $parsed.MegaLink = $devParsed.MegaLink }
            if ([string]::IsNullOrWhiteSpace($parsed.GigaFileLink) -and -not [string]::IsNullOrWhiteSpace($devParsed.GigaFileLink)) {
                $parsed.GigaFileLink = $devParsed.GigaFileLink
            }
        }
    }

    if ($cmbCategory.Items.Contains($parsed.Category)) { $cmbCategory.SelectedItem = $parsed.Category }
    else { $cmbCategory.SelectedIndex = 0 }
    Update-CategoryLabels

    $txtDate.Text  = $parsed.DateStr
    $cmbEvent.Text = $parsed.EventName
    $txtMega.Text  = $parsed.MegaLink
    $txtGiga.Text  = $parsed.GigaFileLink

    $script:PersonsList = $parsed.Persons
    Refresh-PersonCombo 0
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
})

$btnDelPerson.Add_Click({
    if ($script:PersonsList.Count -le 1) {
        $script:PersonsList[0] = @{ Name = ""; CostumeOrChar = ""; XAccount = ""; Comment = "" }
        Refresh-PersonCombo 0
        return
    }
    $script:PersonsList.RemoveAt($script:CurrentPersonIndex)
    Refresh-PersonCombo ([Math]::Max(0, $script:CurrentPersonIndex - 1))
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

$btnMultiFolder.Add_Click({
    if ($script:RelatedFolders.Count -le 1) { return }
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
        $st = if ($fp.Equals($script:Paired.Target, [System.StringComparison]::OrdinalIgnoreCase)) { "編集中" } else { "関連" }
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
    try {
        $normX = ConvertTo-NormalizedX $txtX.Text
        if ([string]::IsNullOrWhiteSpace($normX)) {
            [System.Windows.Forms.MessageBox]::Show("Xアカウントを入力してください。", "入力確認", "OK", "Warning") | Out-Null
            return
        }
        $txtX.Text = $normX
        $btnFetchX.Enabled = $false
        $btnFetchX.Text = "取得中..."
        $form.Refresh()

        $fetched = ""
        if (Get-Command Get-XDisplayName -ErrorAction SilentlyContinue) {
            $rawRes = Get-XDisplayName $normX $EffectiveConfig
            if ($rawRes -is [hashtable] -and $rawRes.ContainsKey("Name")) { $fetched = [string]$rawRes["Name"] }
            elseif ($rawRes -is [array]) { $fetched = ($rawRes -join " ").Trim() }
            else { $fetched = [string]$rawRes }
        }

        $cleanName = ConvertTo-CleanModelName $fetched
        if (-not [string]::IsNullOrWhiteSpace($cleanName)) {
            $cmbName.Text = $cleanName
            Try-AutoFillSameDayCostume
            Save-CurrentPersonToMemory
            Refresh-PersonCombo $script:CurrentPersonIndex
            if (Get-Command Save-XHistory -ErrorAction SilentlyContinue) {
                Save-XHistory $normX $cleanName $EffectiveConfig $txtDate.Text.Trim()
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show("Xから表示名を取得できませんでした。", "取得結果", "OK", "Information") | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("X表示名取得エラー: " + $_.Exception.Message, "エラー", "OK", "Error") | Out-Null
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
                $selAcc  = if ($sel -is [hashtable]) { [string]$sel["account"] } else { [string]$sel.account }
                $selName = if ($sel -is [hashtable]) { [string]$sel["name"] }    else { [string]$sel.name }
                if (-not [string]::IsNullOrWhiteSpace($selAcc))  { $txtX.Text = ConvertTo-NormalizedX $selAcc }
                if (-not [string]::IsNullOrWhiteSpace($selName)) { $cmbName.Text = ConvertTo-CleanModelName $selName }
                Try-AutoFillSameDayCostume
                Save-CurrentPersonToMemory
                Refresh-PersonCombo $script:CurrentPersonIndex
            }
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("履歴検索エラー: " + $_.Exception.Message, "エラー", "OK", "Error") | Out-Null
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
        $megaUrl = ""
        $diagMsg = ""
        if (Get-Command Get-MegaFolderLink -ErrorAction SilentlyContinue) {
            $res = Get-MegaFolderLink $script:Paired.Target $EffectiveConfig
            $allText = ""
            if ($res -is [hashtable]) {
                if ($res.ContainsKey("Url"))     { $megaUrl = [string]$res["Url"] }
                if ($res.ContainsKey("Message")) { $diagMsg = [string]$res["Message"] }
                $allText = ($res.Values -join "`n")
            } elseif ($res -is [array]) { $allText = ($res -join "`n"); $diagMsg = $allText }
            else { $allText = [string]$res; $diagMsg = $allText }
            if ([string]::IsNullOrWhiteSpace($megaUrl) -and $allText -match '(https?://mega\.nz/[^\s\)\]]+)') { $megaUrl = $Matches[1] }
        }
        if (-not [string]::IsNullOrWhiteSpace($megaUrl)) {
            $txtMega.Text = $megaUrl
            [System.Windows.Forms.Clipboard]::SetText($megaUrl)
            [System.Windows.Forms.MessageBox]::Show("MEGAリンクを取得し、コピーしました。`n`n$megaUrl", "MEGAリンク取得完了", "OK", "Information") | Out-Null
        } else {
            if ([string]::IsNullOrWhiteSpace($diagMsg)) { $diagMsg = "リンクを取得できませんでした。ログ: " + $EffectiveConfig.MegaLogPath }
            [System.Windows.Forms.MessageBox]::Show($diagMsg, "MEGAリンク診断結果", "OK", "Warning") | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("MEGA取得エラー:`n" + $_.Exception.Message, "エラー", "OK", "Error") | Out-Null
    } finally {
        $btnGetMega.Enabled = $true
        $btnGetMega.Text = "リンク取得/診断"
    }
})

$btnCopyMega.Add_Click({
    $u = $txtMega.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($u)) {
        [System.Windows.Forms.Clipboard]::SetText($u)
        [System.Windows.Forms.MessageBox]::Show("MEGAリンクをコピーしました。", "コピー完了", "OK", "Information") | Out-Null
    }
})

$btnSendGiga.Add_Click({
    try {
        $targetForUpload = if (-not [string]::IsNullOrWhiteSpace($script:Paired.DevFolder) -and (Test-Path -LiteralPath $script:Paired.DevFolder)) { $script:Paired.DevFolder } else { $script:Paired.Target }
        if ([string]::IsNullOrWhiteSpace($targetForUpload) -or -not (Test-Path -LiteralPath $targetForUpload)) {
            [System.Windows.Forms.MessageBox]::Show("アップロード対象フォルダが見つかりません。", "確認", "OK", "Warning") | Out-Null
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
            [System.Windows.Forms.Clipboard]::SetText([string]$gigaRes.Url)
            $passNote = if (-not [string]::IsNullOrWhiteSpace([string]$gigaRes.Password))     { " / PW: $($gigaRes.Password)" } else { "" }
            $daysNote = if (-not [string]::IsNullOrWhiteSpace([string]$gigaRes.LifetimeDays)) { " / 期限: $($gigaRes.LifetimeDays)日" } else { "" }
            $delNote  = if (-not [string]::IsNullOrWhiteSpace([string]$gigaRes.DelKey))       { " / 削除キー: $($gigaRes.DelKey)" } else { "" }
            $memoLine = "【ギガファイル便】$($gigaRes.Url)${passNote}${daysNote}${delNote}"
            $curCom = $txtComment.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($curCom)) { $txtComment.Text = $memoLine }
            elseif ($curCom -notmatch [regex]::Escape([string]$gigaRes.Url)) { $txtComment.Text = $curCom + "`r`n" + $memoLine }
            Save-CurrentPersonToMemory
            [System.Windows.Forms.MessageBox]::Show("ギガファイル便のURLを取得し、プロパティ画面へ反映しました。`n`n$($gigaRes.Url)", "ギガファイル便連携完了", "OK", "Information") | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("ギガファイル便連携エラー:`n" + $_.Exception.Message, "エラー", "OK", "Error") | Out-Null
    } finally {
        $btnSendGiga.Enabled = $true
        $btnSendGiga.Text = "ギガファイル便で送る"
    }
})

$btnCopyGiga.Add_Click({
    $u = $txtGiga.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($u)) {
        [System.Windows.Forms.Clipboard]::SetText($u)
        [System.Windows.Forms.MessageBox]::Show("ギガファイル便URLをコピーしました。", "コピー完了", "OK", "Information") | Out-Null
    }
})

$btnSave.Add_Click({
    try {
        Save-CurrentPersonToMemory
        Update-MultiFolderButton
        $formData = @{
            Category     = [string]$cmbCategory.SelectedItem
            DateStr      = $txtDate.Text.Trim()
            EventName    = $cmbEvent.Text.Trim()
            MegaLink     = $txtMega.Text.Trim()
            GigaFileLink = $txtGiga.Text.Trim()
        }
        Save-AllPhotoInfoAndLedger `
            -FormData $formData `
            -PersonsList $script:PersonsList `
            -PairedObj $script:Paired `
            -EffectiveConfig $EffectiveConfig `
            -RelatedFolders $script:RelatedFolders
        $form.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("保存中にエラーが発生しました:`n" + $_.Exception.Message, "保存エラー", "OK", "Error") | Out-Null
    }
})

$btnCancel.Add_Click({ $form.Close() })

Load-HistoryCandidatesToUI
Load-FolderIntoEditor $TargetFolder
[void]$form.ShowDialog()
