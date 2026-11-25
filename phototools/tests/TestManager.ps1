#requires -Version 5.1
# ==============================================================================
# TestManager.ps1 - Test Manager
# ==============================================================================
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
        Initialize-PhotoLogger -RootDir $RootDir | Out-Null
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
$Form.Text = "PhotoTools Test Manager"
$Form.Size = New-Object System.Drawing.Size(800, 640)
$Form.StartPosition = "CenterScreen"
$Form.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5)

$ChkList = New-Object System.Windows.Forms.CheckedListBox
$ChkList.Location = New-Object System.Drawing.Point(16, 16)
$ChkList.Size = New-Object System.Drawing.Size(752, 220)
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
$BtnRunUnchecked.Text = "Run Unchecked Tests"
$BtnRunUnchecked.Location = New-Object System.Drawing.Point(16, 248)
$BtnRunUnchecked.Size = New-Object System.Drawing.Size(260, 34)
$BtnRunUnchecked.BackColor = [System.Drawing.Color]::FromArgb(26, 115, 232)
$BtnRunUnchecked.ForeColor = [System.Drawing.Color]::White
$BtnRunUnchecked.FlatStyle = "Flat"
$Form.Controls.Add($BtnRunUnchecked)

$BtnRunAll = New-Object System.Windows.Forms.Button
$BtnRunAll.Text = "Run All Tests"
$BtnRunAll.Location = New-Object System.Drawing.Point(286, 248)
$BtnRunAll.Size = New-Object System.Drawing.Size(160, 34)
$Form.Controls.Add($BtnRunAll)

$BtnSaveState = New-Object System.Windows.Forms.Button
$BtnSaveState.Text = "Save State"
$BtnSaveState.Location = New-Object System.Drawing.Point(608, 248)
$BtnSaveState.Size = New-Object System.Drawing.Size(160, 34)
$Form.Controls.Add($BtnSaveState)

$TxtLog = New-Object System.Windows.Forms.TextBox
$TxtLog.Location = New-Object System.Drawing.Point(16, 294)
$TxtLog.Size = New-Object System.Drawing.Size(752, 292)
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
    $outObj = [ordered]@{}
    for ($i = 0; $i -lt $definitions.Count; $i++) {
        $d = $definitions[$i]
        $modKey = if (-not [string]::IsNullOrWhiteSpace($d.Id)) { [string]$d.Id } else { [string]$d.ModuleId }
        if (-not [string]::IsNullOrWhiteSpace($modKey)) {
            $outObj[$modKey] = $ChkList.GetItemChecked($i)
        }
    }
    $json = $outObj | ConvertTo-Json -Depth 3
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($StateFile, $json, $utf8Bom)
}

function Save-TestLogFile {
    param([string]$Prefix = "test_run")
    try {
        if (-not (Test-Path -LiteralPath $LogsDir)) {
            New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
        }
        $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $logPath = Join-Path $LogsDir "${Prefix}_${ts}.log"
        $content = $TxtLog.Text
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($logPath, $content, $utf8Bom)
    } catch {
        # ignore
    }
}

function Run-BatchTests {
    param([bool]$OnlyUnchecked)
    $BtnRunUnchecked.Enabled = $false
    $BtnRunAll.Enabled = $false
    try {
        Append-TestLog "============================================================"
        if ($OnlyUnchecked) {
            Append-TestLog "[BATCH] Running unchecked module tests..."
        } else {
            Append-TestLog "[BATCH] Running all module tests..."
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
                $fileName = if ($errRec.InvocationInfo -and -not [string]::IsNullOrWhiteSpace($errRec.InvocationInfo.ScriptName)) { Split-Path -Leaf $errRec.InvocationInfo.ScriptName } else { "?" }
                $lineNo = if ($errRec.InvocationInfo) { $errRec.InvocationInfo.ScriptLineNumber } else { "?" }
                $stackInfo = if (-not [string]::IsNullOrWhiteSpace($errRec.ScriptStackTrace)) { ($errRec.ScriptStackTrace -replace "`r?`n", " | ") } else { "" }
                Append-TestLog "[EXCP] $($d.Name) ($fileName Line:$lineNo) : $($errRec.Exception.Message)"
                if (-not [string]::IsNullOrWhiteSpace($stackInfo)) {
                    Append-TestLog "[TRCE] $stackInfo"
                }
                Append-TestLog "[STOP] Test stopped due to error. Please fix and re-run."
                try {
                    if (Get-Command Initialize-PhotoLogger -ErrorAction SilentlyContinue) {
                        Initialize-PhotoLogger -RootDir $RootDir | Out-Null
                    }
                    if (Get-Command Write-PhotoError -ErrorAction SilentlyContinue) {
                        Write-PhotoError -Message "TestManager Exception [$($d.Name)]" -ErrorRecord $errRec -ModuleName "TestManager" | Out-Null
                    }
                } catch {
                    Append-TestLog "[WARN] Failed to write error log: $($_.Exception.Message)"
                }
                Save-TestLogFile -Prefix "test_error"
                return
            }
        }
        Append-TestLog "[DONE] All module tests completed successfully!"
        Save-TestLogFile -Prefix "test_run"
    } finally {
        $BtnRunUnchecked.Enabled = $true
        $BtnRunAll.Enabled = $true
    }
}

$BtnRunUnchecked.Add_Click({ Run-BatchTests -OnlyUnchecked $true })
$BtnRunAll.Add_Click({ Run-BatchTests -OnlyUnchecked $false })
$BtnSaveState.Add_Click({
    Save-PassedState
    Append-TestLog "[INFO] Saved test state: $StateFile"
})

[void]$Form.ShowDialog()
