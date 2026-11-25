# ==============================================================================
# LogHelper.ps1 - PhotoTools 共通ログ出力モジュール (UTF-8 BOM)
# ==============================================================================

$script:PhotoLogDir = $null
$script:PhotoLogFile = $null
$script:PhotoErrorFile = $null

function Initialize-PhotoLogger {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [Alias("RootDir", "LogDir", "BaseDir", "Path")]
        [string]$Directory = ""
    )

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        $scriptRoot = Split-Path -Parent $PSScriptRoot
        if ([string]::IsNullOrWhiteSpace($scriptRoot)) { $scriptRoot = "D:\PhotoTools" }
        $Directory = Join-Path $scriptRoot "data\logs"
    }
    else {
        $leaf = Split-Path -Leaf $Directory
        if ($leaf -ne "logs") {
            $Directory = Join-Path $Directory "logs"
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

function Write-LogInfo {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [Alias("Msg", "Text")]
        [string]$Message,

        [Parameter(Position = 1)]
        [Alias("Module", "Source")]
        [string]$ModuleName = "System"
    )

    if ([string]::IsNullOrWhiteSpace($script:PhotoLogFile)) {
        Initialize-PhotoLogger | Out-Null
    }

    $ts = Get-Date -Format "yyyy/MM/dd HH:mm:ss.fff"
    $line = "[$ts] [INFO] [$ModuleName] $Message"
    Add-Content -LiteralPath $script:PhotoLogFile -Value $line -Encoding UTF8
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
        [string]$ModuleName = "System"
    )
    return Write-LogInfo -Message $Message -ModuleName $ModuleName
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
        [string]$ModuleName = "System"
    )

    if ([string]::IsNullOrWhiteSpace($script:PhotoLogFile)) {
        Initialize-PhotoLogger | Out-Null
    }

    $ts = Get-Date -Format "yyyy/MM/dd HH:mm:ss.fff"
    $errDetail = ""
    if ($null -ne $ErrorRecord) {
        if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
            $errMsg = $ErrorRecord.Exception.Message
            $lineNo = $ErrorRecord.InvocationInfo.ScriptLineNumber
            $codeLine = ($ErrorRecord.InvocationInfo.Line -replace "`r|`n", "").Trim()
            $stack = $ErrorRecord.ScriptStackTrace
            if ([string]::IsNullOrWhiteSpace($Message)) { $Message = $errMsg }
            $errDetail = "`r`n  詳細: $errMsg (Line: $lineNo)`r`n  コード: $codeLine`r`n  スタック: $stack"
        }
        else {
            $errDetail = "`r`n  詳細: $($ErrorRecord.ToString())"
        }
    }
    if ([string]::IsNullOrWhiteSpace($Message)) { $Message = "不明なエラーが発生しました。" }

    $line = "[$ts] [ERROR] [$ModuleName] $Message$errDetail"
    Add-Content -LiteralPath $script:PhotoLogFile -Value $line -Encoding UTF8
    Add-Content -LiteralPath $script:PhotoErrorFile -Value $line -Encoding UTF8
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
        [string]$ModuleName = "System"
    )
    return Write-LogError -Message $Message -ErrorRecord $ErrorRecord -ModuleName $ModuleName
}
