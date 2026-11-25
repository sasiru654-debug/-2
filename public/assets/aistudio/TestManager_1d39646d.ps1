#requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

$TestsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $TestsDir
$DataDir = Join-Path $RootDir "data"
$LogsDir = Join-Path $DataDir "logs"

foreach ($dir in @($DataDir, $LogsDir)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

$StateFile = Join-Path $DataDir "test_passed_state.json"
$LogHelperPath = Join-Path $RootDir "common\LogHelper.ps1"
$TestCasesPath = Join-Path $TestsDir "ModuleTestCases.ps1"

if (Test-Path -LiteralPath $LogHelperPath) {
    . $LogHelperPath
    if (Get-Command Initialize-PhotoLogger -ErrorAction SilentlyContinue) {
        Initialize-PhotoLogger -RootDir $RootDir
    }
}

. $TestCasesPath

$passedMap = @{}
if (Test-Path -LiteralPath $StateFile) {
    try {
        $rawJson = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($rawJson)) {
            $parsed = $rawJson | ConvertFrom-Json
            foreach ($prop in $parsed.PSObject.Properties) {
                if (-not [string]::IsNullOrWhiteSpace($prop.Name)) {
                    $passedMap[$prop.Name] = [bool]$prop.Value
                }
            }
        }
    } catch {
        $passedMap = @{}
    }
}

$definitions = @(Get-PhotoModuleTestDefinitions)

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "PhotoTools モジュール単位隔離テストマネージャー"
$Form.Size = New-Object System.Drawing.Size(780, 620)
$Form.StartPosition = "CenterScreen"
$Form.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5)

$ChkList = New-Object System.Windows.Forms.CheckedListBox
$ChkList.Location = New-Object System.Drawing.Point(16, 16)
$ChkList.Size = New-Object System.Drawing.Size(732, 210)
$ChkList.CheckOnClick = $true
$Form.Controls.Add($ChkList)

$idx = 0
foreach ($d in $definitions) {
    $modKey = if (-not [string]::IsNullOrWhiteSpace($d.Id)) { [string]$d.Id } else { [string]$d.ModuleId }
    $label = "$($d.Name) - $($d.Description)"
    [void]$ChkList.Items.Add($label)
    if (-not [string]::IsNullOrWhiteSpace($modKey) -and $passedMap.ContainsKey($modKey) -and $passedMap[$modKey]) {
        $ChkList.SetItemChecked($idx, $true)
    }
    $idx++
}

$BtnRunUnchecked = New-Object System.Windows.Forms.Button
$BtnRunUnchecked.Text = "未合格（未チェック）のみ順番にテスト実行"
$BtnRunUnchecked.Location = New-Object System.Drawing.Point(16, 236)
$BtnRunUnchecked.Size = New-Object System.Drawing.Size(270, 34)
$BtnRunUnchecked.BackColor = [System.Drawing.Color]::FromArgb(26, 115, 232)
$BtnRunUnchecked.ForeColor = [System.Drawing.Color]::White
$BtnRunUnchecked.FlatStyle = "Flat"
$Form.Controls.Add($BtnRunUnchecked)

$BtnRunAll = New-Object System.Windows.Forms.Button
$BtnRunAll.Text = "全モジュール再テスト"
$BtnRunAll.Location = New-Object System.Drawing.Point(296, 236)
$BtnRunAll.Size = New-Object System.Drawing.Size(160, 34)
$Form.Controls.Add($BtnRunAll)

$BtnSaveState = New-Object System.Windows.Forms.Button
$BtnSaveState.Text = "チェック状態を保存"
$BtnSaveState.Location = New-Object System.Drawing.Point(588, 236)
$BtnSaveState.Size = New-Object System.Drawing.Size(160, 34)
$Form.Controls.Add($BtnSaveState)

$TxtLog = New-Object System.Windows.Forms.TextBox
$TxtLog.Location = New-Object System.Drawing.Point(16, 282)
$TxtLog.Size = New-Object System.Drawing.Size(732, 282)
$TxtLog.Multiline = $true
$TxtLog.ReadOnly = $true
$TxtLog.ScrollBars = "Vertical"
$TxtLog.Font = New-Object System.Drawing.Font("Consolas", 9.5)
$TxtLog.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($TxtLog)

function Append-TestLog {
    param([string]$Text)
    $TxtLog.AppendText($Text + "`r`n")
    [System.Windows.Forms.Application]::DoEvents()
}

function Save-PassedState {
    $outObj = @{}
    for ($i = 0; $i -lt $definitions.Count; $i++) {
        $d = $definitions[$i]
        $modKey = if (-not [string]::IsNullOrWhiteSpace($d.Id)) { [string]$d.Id } else { [string]$d.ModuleId }
        if (-not [string]::IsNullOrWhiteSpace($modKey)) {
            $outObj[$modKey] = $ChkList.GetItemChecked($i)
        }
    }
    $json = $outObj | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($StateFile, $json, [System.Text.Encoding]::UTF8)
}

function Run-BatchTests {
    param([bool]$OnlyUnchecked)
    $BtnRunUnchecked.Enabled = $false
    $BtnRunAll.Enabled = $false
    try {
        Append-TestLog "============================================================"
        if ($OnlyUnchecked) {
            Append-TestLog "[BATCH] 未合格モジュールの順番テストを開始します..."
        } else {
            Append-TestLog "[BATCH] 全モジュールの順番テストを開始します..."
        }

        for ($i = 0; $i -lt $definitions.Count; $i++) {
            if ($OnlyUnchecked -and $ChkList.GetItemChecked($i)) {
                continue
            }
            $d = $definitions[$i]
            $modKey = if (-not [string]::IsNullOrWhiteSpace($d.Id)) { [string]$d.Id } else { [string]$d.ModuleId }
            Append-TestLog "[RUN ] $($d.Name) ..."
            try {
                $msg = Invoke-SingleModuleTest -ModuleId $modKey -RootDir $RootDir
                $ChkList.SetItemChecked($i, $true)
                Save-PassedState
                Append-TestLog "[PASS] $($d.Name) : $msg"
            } catch {
                $errRec = $_
                $lineNo = if ($errRec.InvocationInfo) { $errRec.InvocationInfo.ScriptLineNumber } else { "?" }
                Append-TestLog "[EXCP] $($d.Name) (Line:$lineNo) : $($errRec.Exception.Message)"
                Append-TestLog "[STOP] エラーが発生したためここで一時停止します。修正後に再実行してください。"
                return
            }
        }
        Append-TestLog "[DONE] 全モジュールの隔離テストが正常に完了しました！"
    } finally {
        $BtnRunUnchecked.Enabled = $true
        $BtnRunAll.Enabled = $true
    }
}

$BtnRunUnchecked.Add_Click({ Run-BatchTests -OnlyUnchecked $true })
$BtnRunAll.Add_Click({ Run-BatchTests -OnlyUnchecked $false })
$BtnSaveState.Add_Click({
    Save-PassedState
    Append-TestLog "[INFO] チェック状態を保存しました: $StateFile"
})

[void]$Form.ShowDialog()
