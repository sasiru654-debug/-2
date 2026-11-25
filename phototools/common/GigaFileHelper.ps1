#requires -Version 5.1
# ==============================================================================
# GigaFileHelper.ps1 - ギガファイル便ツール連携ブリッジ (UTF-8 BOM / CRLF)
# ==============================================================================

function Resolve-GigaFileScriptPath {
    param([hashtable]$Config = @{})
    if ($null -ne $Config) {
        foreach ($key in @("GigaScriptPath", "GigaFileScriptPath")) {
            if ($Config.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string]$Config[$key])) {
                $p = [string]$Config[$key]
                if (Test-Path -LiteralPath $p) { return $p }
            }
        }
        if ($Config.ContainsKey("RootDir") -and -not [string]::IsNullOrWhiteSpace([string]$Config["RootDir"])) {
            $p2 = Join-Path ([string]$Config["RootDir"]) "gigafile\send_to_gigafile.ps1"
            if (Test-Path -LiteralPath $p2) { return $p2 }
        }
    }
    $commonDir = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { "D:\PhotoTools\common" }
    $rootDir = Split-Path -Parent $commonDir
    return (Join-Path $rootDir "gigafile\send_to_gigafile.ps1")
}

function Invoke-GigaFileUploadWithCallback {
    param(
        [string[]]$TargetPaths = @(),
        [string]$TargetFolder = "",
        [string]$RootDir = "",
        [hashtable]$Config = @{}
    )

    $paths = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($TargetFolder) -and (Test-Path -LiteralPath $TargetFolder)) {
        $paths.Add($TargetFolder)
    }
    if ($null -ne $TargetPaths) {
        foreach ($tp in $TargetPaths) {
            if (-not [string]::IsNullOrWhiteSpace($tp) -and (Test-Path -LiteralPath $tp) -and -not $paths.Contains($tp)) {
                $paths.Add($tp)
            }
        }
    }
    if ($paths.Count -eq 0) {
        throw "アップロード対象のファイルまたはフォルダが見つかりません。"
    }

    $cfg = if ($null -ne $Config) { $Config.Clone() } else { @{} }
    if (-not [string]::IsNullOrWhiteSpace($RootDir) -and -not $cfg.ContainsKey("RootDir")) {
        $cfg["RootDir"] = $RootDir
    }
    $gigaScript = Resolve-GigaFileScriptPath -Config $cfg
    if (-not (Test-Path -LiteralPath $gigaScript)) {
        throw "ギガファイル便スクリプトが見つかりません: $gigaScript"
    }

    $callbackFile = Join-Path ([System.IO.Path]::GetTempPath()) ("GigaCallback_" + [Guid]::NewGuid().ToString("N") + ".json")

    try {
        $argList = @(
            "-NoProfile",
            "-STA",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$gigaScript`"",
            "-CallbackResultFile", "`"$callbackFile`""
        )
        foreach ($p in $paths) {
            $argList += "`"$p`""
        }

        [void](Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Wait -PassThru)

        if (Test-Path -LiteralPath $callbackFile) {
            $jsonRaw = [System.IO.File]::ReadAllText($callbackFile, [System.Text.Encoding]::UTF8)
            if (-not [string]::IsNullOrWhiteSpace($jsonRaw)) {
                $obj = $jsonRaw | ConvertFrom-Json
                $getField = {
                    param([object]$O, [string[]]$Names, [string]$Def = "")
                    foreach ($n in $Names) {
                        $prop = $O.PSObject.Properties[$n]
                        if ($null -ne $prop -and $null -ne $prop.Value) { return [string]$prop.Value }
                    }
                    return $Def
                }
                $u = & $getField $obj @("Url", "url")
                $d = & $getField $obj @("DelKey", "delkey")
                $pw = & $getField $obj @("Password", "password")
                $lt = & $getField $obj @("LifetimeDays", "lifetime") "0"
                return @{
                    Success      = (-not [string]::IsNullOrWhiteSpace($u))
                    Url          = $u
                    DelKey       = $d
                    Password     = $pw
                    LifetimeDays = [int]$lt
                }
            }
        }

        return @{
            Success      = $false
            Url          = ""
            DelKey       = ""
            Password     = ""
            LifetimeDays = 0
        }
    } finally {
        if (Test-Path -LiteralPath $callbackFile) {
            Remove-Item -LiteralPath $callbackFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-GigaFileUploadForFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetFolder,
        [hashtable]$Config = @{}
    )
    return Invoke-GigaFileUploadWithCallback -TargetFolder $TargetFolder -Config $Config
}
