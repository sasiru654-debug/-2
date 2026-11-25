#requires -Version 5.1
# ==============================================================================
# LogHelper.ps1 - PhotoTools 共通ログ・エラーデバッグファイル出力モジュール (UTF-8 BOM / CRLF)
# ==============================================================================

$script:PhotoLogDir = $null
$script:PhotoLogFile = $null
$script:PhotoErrorFile = $null
$script:LastPhotoDebugErrorFile = ""
$script:LastPhotoDebugErrorSummary = ""

function Initialize-PhotoLogger {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [Alias("RootDir", "LogDir", "BaseDir", "Path")]
        [string]$Directory = ""
    )

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        $scriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $PSScriptRoot } else { "D:\PhotoTools" }
        if ([string]::IsNullOrWhiteSpace($scriptRoot)) { $scriptRoot = "D:\PhotoTools" }
        $Directory = Join-Path $scriptRoot "data\logs"
    }
    else {
        $normDir = $Directory.TrimEnd('\')
        $leaf = Split-Path -Leaf $normDir
        if ($leaf -eq "logs") {
            $Directory = $normDir
        } elseif ($leaf -eq "data") {
            $Directory = Join-Path $normDir "logs"
        } else {
            $Directory = Join-Path $normDir "data\logs"
        }
    }

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $script:PhotoLogDir = $Directory
    $dateStr = Get-Date -Format "yyyyMMdd"
    $script:PhotoLogFile = Join-Path $Directory "process_$dateStr.log"
    $script:PhotoErrorFile = Join-Path $Directory "error_$dateStr.log"
    return $script:PhotoLogDir
}

function Initialize-PhotoLog {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [Alias("RootDir", "LogDir", "BaseDir", "Path")]
        [string]$Directory = ""
    )
    return Initialize-PhotoLogger -Directory $Directory
}

function Get-PhotoLogDirectory {
    if ([string]::IsNullOrWhiteSpace($script:PhotoLogDir)) {
        Initialize-PhotoLogger | Out-Null
    }
    return $script:PhotoLogDir
}

function Get-LastPhotoDebugLogPath {
    return $script:LastPhotoDebugErrorFile
}

function Get-LastPhotoDebugSummary {
    return $script:LastPhotoDebugErrorSummary
}

function Write-PhotoLogLineInternal {
    param(
        [string]$FilePath,
        [string]$Line
    )
    $parentDir = Split-Path -Parent $FilePath
    if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    $isNew = -not (Test-Path -LiteralPath $FilePath)
    $enc = New-Object System.Text.UTF8Encoding($isNew)
    $sw = New-Object System.IO.StreamWriter($FilePath, $true, $enc)
    try {
        $sw.WriteLine($Line)
    } finally {
        $sw.Dispose()
    }
}

function Write-PhotoDebugDumpInternal {
    param(
        [string]$ModuleName = "System",
        [string]$Message = "",
        $ErrorRecord = $null,
        [hashtable]$Context = $null
    )

    try {
        $logDir = Get-PhotoLogDirectory
        if ([string]::IsNullOrWhiteSpace($logDir)) {
            $fallbackRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $PSScriptRoot } else { "D:\PhotoTools" }
            $logDir = Join-Path $fallbackRoot "data\logs"
        }
        if (-not (Test-Path -LiteralPath $logDir)) {
            [void][System.IO.Directory]::CreateDirectory($logDir)
        }
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
        $debugPath = Join-Path $logDir "debug_error_$stamp.log"
        $seq = 1
        while (Test-Path -LiteralPath $debugPath) {
            $debugPath = Join-Path $logDir ("debug_error_{0}_{1}.log" -f $stamp, $seq)
            $seq++
        }

        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("======================================================================")
        [void]$sb.AppendLine("PhotoTools Error Debug Report")
        [void]$sb.AppendLine("======================================================================")
        [void]$sb.AppendLine("Timestamp   : " + (Get-Date -Format "yyyy/MM/dd HH:mm:ss.fff"))
        [void]$sb.AppendLine("Module      : $ModuleName")
        [void]$sb.AppendLine("Message     : $Message")
        [void]$sb.AppendLine("PSVersion   : " + $PSVersionTable.PSVersion.ToString())
        [void]$sb.AppendLine("PID         : $PID")
        [void]$sb.AppendLine("LogDir      : $logDir")
        [void]$sb.AppendLine("")

        if ($null -ne $Context -and ($Context -is [System.Collections.IDictionary]) -and $Context.Count -gt 0) {
            [void]$sb.AppendLine("[Context]")
            foreach ($k in ($Context.Keys | Sort-Object)) {
                $val = if ($null -eq $Context[$k]) { "<null>" } else { [string]$Context[$k] }
                [void]$sb.AppendLine(("  {0} = {1}" -f $k, $val))
            }
            [void]$sb.AppendLine("")
        }

        $sumLines = New-Object System.Collections.Generic.List[string]
        if ($null -ne $ErrorRecord) {
            if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
                $inv = $ErrorRecord.InvocationInfo
                $ex = $ErrorRecord.Exception
                [void]$sb.AppendLine("[ErrorRecord]")
                if ($null -ne $ex) {
                    [void]$sb.AppendLine("  ExceptionType : " + $ex.GetType().FullName)
                    [void]$sb.AppendLine("  ExceptionMsg  : " + $ex.Message)
                    if ($null -ne $ex.PSObject.Properties["HResult"]) {
                        [void]$sb.AppendLine("  HResult       : " + ("0x{0:X8}" -f $ex.HResult))
                    }
                }
                if ($null -ne $inv) {
                    $sName = [string]$inv.ScriptName
                    $sLine = [string]$inv.ScriptLineNumber
                    $sCode = (([string]$inv.Line) -replace "`r|`n", " ").Trim()
                    [void]$sb.AppendLine("  ScriptName    : " + $sName)
                    [void]$sb.AppendLine("  LineNumber    : " + $sLine)
                    [void]$sb.AppendLine("  OffsetInLine  : " + [string]$inv.OffsetInLine)
                    [void]$sb.AppendLine("  Line          : " + $sCode)
                    if (-not [string]::IsNullOrWhiteSpace($sName) -or -not [string]::IsNullOrWhiteSpace($sLine)) {
                        $shortFile = if (-not [string]::IsNullOrWhiteSpace($sName)) { [System.IO.Path]::GetFileName($sName) } else { "(unknown)" }
                        $sumLines.Add("発生箇所: ${shortFile}:${sLine}")
                    }
                    if (-not [string]::IsNullOrWhiteSpace($sCode)) {
                        $sumLines.Add("コード: $sCode")
                    }
                    if (-not [string]::IsNullOrWhiteSpace([string]$inv.PositionMessage)) {
                        [void]$sb.AppendLine("  PositionMsg   :")
                        [void]$sb.AppendLine([string]$inv.PositionMessage)
                    }
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$ErrorRecord.ScriptStackTrace)) {
                    [void]$sb.AppendLine("")
                    [void]$sb.AppendLine("[ScriptStackTrace]")
                    [void]$sb.AppendLine([string]$ErrorRecord.ScriptStackTrace)
                    $sumLines.Add("スタック: " + (([string]$ErrorRecord.ScriptStackTrace).Trim() -replace "`r?`n", " <- "))
                }
                if ($null -ne $ex -and -not [string]::IsNullOrWhiteSpace([string]$ex.StackTrace)) {
                    [void]$sb.AppendLine("")
                    [void]$sb.AppendLine("[DotNetStackTrace]")
                    [void]$sb.AppendLine([string]$ex.StackTrace)
                }
                $inner = if ($null -ne $ex) { $ex.InnerException } else { $null }
                $depth = 1
                while ($null -ne $inner) {
                    [void]$sb.AppendLine("")
                    [void]$sb.AppendLine("[InnerException #$depth]")
                    [void]$sb.AppendLine("  Type    : " + $inner.GetType().FullName)
                    [void]$sb.AppendLine("  Message : " + $inner.Message)
                    if (-not [string]::IsNullOrWhiteSpace([string]$inner.StackTrace)) {
                        [void]$sb.AppendLine($inner.StackTrace)
                    }
                    $inner = $inner.InnerException
                    $depth++
                }
            }
            elseif ($ErrorRecord -is [System.Exception]) {
                [void]$sb.AppendLine("[Exception]")
                [void]$sb.AppendLine("  ExceptionType : " + $ErrorRecord.GetType().FullName)
                [void]$sb.AppendLine("  ExceptionMsg  : " + $ErrorRecord.Message)
                if (-not [string]::IsNullOrWhiteSpace([string]$ErrorRecord.StackTrace)) {
                    [void]$sb.AppendLine("[DotNetStackTrace]")
                    [void]$sb.AppendLine([string]$ErrorRecord.StackTrace)
                }
            }
            else {
                [void]$sb.AppendLine("[RawErrorObject]")
                [void]$sb.AppendLine($ErrorRecord.ToString())
            }
        }
        $script:LastPhotoDebugErrorSummary = ($sumLines -join "`r`n")

        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        $reportText = $sb.ToString()
        $writtenPath = ""
        try {
            [System.IO.File]::WriteAllText($debugPath, $reportText, $utf8Bom)
            if ([System.IO.File]::Exists($debugPath)) {
                $writtenPath = $debugPath
            }
        } catch {
            $writtenPath = ""
        }

        if ([string]::IsNullOrWhiteSpace($writtenPath)) {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "PhotoTools_logs"
            if (-not [System.IO.Directory]::Exists($tempDir)) {
                [void][System.IO.Directory]::CreateDirectory($tempDir)
            }
            $tempDebugPath = Join-Path $tempDir ("debug_error_{0}.log" -f $stamp)
            [System.IO.File]::WriteAllText($tempDebugPath, $reportText, $utf8Bom)
            if ([System.IO.File]::Exists($tempDebugPath)) {
                $writtenPath = $tempDebugPath
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($writtenPath)) {
            $script:LastPhotoDebugErrorFile = $writtenPath
            return $writtenPath
        }
        return ""
    } catch {
        return ""
    }
}

function Write-LogInfo {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [Alias("Msg", "Text")]
        [string]$Message,

        [Parameter(Position = 1)]
        [Alias("Module", "Source")]
        [string]$ModuleName = "System",

        [string]$Level = "INFO"
    )

    if ([string]::IsNullOrWhiteSpace($script:PhotoLogFile)) {
        Initialize-PhotoLogger | Out-Null
    }

    $lvl = if ([string]::IsNullOrWhiteSpace($Level)) { "INFO" } else { $Level.ToUpper() }
    $ts = Get-Date -Format "yyyy/MM/dd HH:mm:ss.fff"
    $line = "[$ts] [$lvl] [$ModuleName] $Message"
    Write-PhotoLogLineInternal -FilePath $script:PhotoLogFile -Line $line
    if ($lvl -eq "ERROR") {
        Write-PhotoLogLineInternal -FilePath $script:PhotoErrorFile -Line $line
    }
    return $line
}

function Write-PhotoLog {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [Alias("Msg", "Text")]
        [string]$Message,

        [Parameter(Position = 1)]
        [Alias("Module", "Source")]
        [string]$ModuleName = "System",

        [string]$Level = "INFO"
    )
    return Write-LogInfo -Message $Message -ModuleName $ModuleName -Level $Level
}

function Write-LogError {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [Alias("Msg", "Text")]
        [string]$Message = "",

        [Parameter(Position = 1)]
        [Alias("Record", "Exception")]
        $ErrorRecord = $null,

        [Parameter(Position = 2)]
        [Alias("Module", "Source")]
        [string]$ModuleName = "System",

        [Parameter(Position = 3)]
        [hashtable]$Context = $null
    )

    $script:LastPhotoDebugErrorFile = ""
    $script:LastPhotoDebugErrorSummary = ""

    if ([string]::IsNullOrWhiteSpace($script:PhotoLogFile)) {
        Initialize-PhotoLogger | Out-Null
    }

    $ts = Get-Date -Format "yyyy/MM/dd HH:mm:ss.fff"
    $errDetail = ""
    if ($null -ne $ErrorRecord) {
        if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
            $errMsg = if ($null -ne $ErrorRecord.Exception) { $ErrorRecord.Exception.Message } else { $ErrorRecord.ToString() }
            $scriptFile = if ($null -ne $ErrorRecord.InvocationInfo -and -not [string]::IsNullOrWhiteSpace([string]$ErrorRecord.InvocationInfo.ScriptName)) { [System.IO.Path]::GetFileName($ErrorRecord.InvocationInfo.ScriptName) } else { "" }
            $lineNo = if ($null -ne $ErrorRecord.InvocationInfo) { $ErrorRecord.InvocationInfo.ScriptLineNumber } else { "?" }
            $codeLine = if ($null -ne $ErrorRecord.InvocationInfo -and $ErrorRecord.InvocationInfo.Line) { ($ErrorRecord.InvocationInfo.Line -replace "`r|`n", "").Trim() } else { "" }
            $stack = $ErrorRecord.ScriptStackTrace
            if ([string]::IsNullOrWhiteSpace($Message)) { $Message = $errMsg }
            $locTag = if (-not [string]::IsNullOrWhiteSpace($scriptFile)) { "${scriptFile}:$lineNo" } else { "Line: $lineNo" }
            $errDetail = "`r`n  詳細: $errMsg ($locTag)`r`n  コード: $codeLine`r`n  スタック: $stack"
        }
        else {
            $errDetail = "`r`n  詳細: $($ErrorRecord.ToString())"
        }
    }
    if ([string]::IsNullOrWhiteSpace($Message)) { $Message = "不明なエラーが発生しました。" }

    $debugPath = Write-PhotoDebugDumpInternal -ModuleName $ModuleName -Message $Message -ErrorRecord $ErrorRecord -Context $Context
    $debugNote = if (-not [string]::IsNullOrWhiteSpace($debugPath)) { "`r`n  デバッグファイル: $debugPath" } else { "" }

    $line = "[$ts] [ERROR] [$ModuleName] $Message$errDetail$debugNote"
    Write-PhotoLogLineInternal -FilePath $script:PhotoLogFile -Line $line
    Write-PhotoLogLineInternal -FilePath $script:PhotoErrorFile -Line $line
    return $line
}

function Write-PhotoError {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [Alias("Msg", "Text")]
        [string]$Message = "",

        [Parameter(Position = 1)]
        [Alias("Record", "Exception")]
        $ErrorRecord = $null,

        [Parameter(Position = 2)]
        [Alias("Module", "Source")]
        [string]$ModuleName = "System",

        [Parameter(Position = 3)]
        [hashtable]$Context = $null
    )
    return Write-LogError -Message $Message -ErrorRecord $ErrorRecord -ModuleName $ModuleName -Context $Context
}

function Show-MsgBox {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [Alias("Message")]
        [object]$Text = "",

        [Parameter(Position = 1)]
        [string]$Title = "PhotoTools",

        [Parameter(Position = 2)]
        [object]$Buttons = "OK",

        [Parameter(Position = 3)]
        [object]$Icon = "Information",

        [Parameter(Position = 4)]
        [System.Windows.Forms.IWin32Window]$Owner = $null,

        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$RemainingArgs
    )

    if ($Text -is [array]) {
        $flat = @($Text)
        $msgText    = if ($flat.Count -gt 0) { [string]$flat[0] } else { "" }
        $msgTitle   = if ($flat.Count -gt 1) { [string]$flat[1] } else { $Title }
        $buttonsArg = if ($flat.Count -gt 2) { $flat[2] } else { $Buttons }
        $iconArg    = if ($flat.Count -gt 3) { $flat[3] } else { $Icon }
    } else {
        $msgText    = [string]$Text
        $msgTitle   = [string]$Title
        $buttonsArg = $Buttons
        $iconArg    = $Icon
    }

    $btnEnum = if ($buttonsArg -is [System.Windows.Forms.MessageBoxButtons]) {
        $buttonsArg
    } else {
        switch ([string]$buttonsArg) {
            "YesNo"       { [System.Windows.Forms.MessageBoxButtons]::YesNo }
            "YesNoCancel" { [System.Windows.Forms.MessageBoxButtons]::YesNoCancel }
            "OKCancel"    { [System.Windows.Forms.MessageBoxButtons]::OKCancel }
            default       { [System.Windows.Forms.MessageBoxButtons]::OK }
        }
    }
    $iconEnum = if ($iconArg -is [System.Windows.Forms.MessageBoxIcon]) {
        $iconArg
    } else {
        switch ([string]$iconArg) {
            "Warning"     { [System.Windows.Forms.MessageBoxIcon]::Warning }
            "Error"       { [System.Windows.Forms.MessageBoxIcon]::Error }
            "Question"    { [System.Windows.Forms.MessageBoxIcon]::Question }
            "Information" { [System.Windows.Forms.MessageBoxIcon]::Information }
            default       { [System.Windows.Forms.MessageBoxIcon]::Information }
        }
    }
    if ($null -ne $Owner) {
        return [System.Windows.Forms.MessageBox]::Show($Owner, $msgText, $msgTitle, $btnEnum, $iconEnum)
    }
    return [System.Windows.Forms.MessageBox]::Show($msgText, $msgTitle, $btnEnum, $iconEnum)
}
