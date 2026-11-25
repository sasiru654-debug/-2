#requires -Version 5.1

function Invoke-GigaFileUploadForFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetFolder,
        [hashtable]$Config = @{}
    )

    if ([string]::IsNullOrWhiteSpace($TargetFolder) -or -not (Test-Path -LiteralPath $TargetFolder)) {
        throw "対象フォルダが見つかりません: $TargetFolder"
    }

    $commonDir = $PSScriptRoot
    $rootDir = Split-Path -Parent $commonDir
    $gigaScript = Join-Path $rootDir "gigafile\send_to_gigafile.ps1"

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
            "-CallbackResultFile", "`"$callbackFile`"",
            "`"$TargetFolder`""
        )

        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Wait -PassThru

        if (Test-Path -LiteralPath $callbackFile) {
            $jsonRaw = [System.IO.File]::ReadAllText($callbackFile, [System.Text.Encoding]::UTF8)
            if (-not [string]::IsNullOrWhiteSpace($jsonRaw)) {
                $obj = $jsonRaw | ConvertFrom-Json
                return @{
                    Success      = $true
                    Url          = [string]$obj.Url
                    DelKey       = [string]$obj.DelKey
                    Password     = [string]$obj.Password
                    LifetimeDays = [int]$obj.LifetimeDays
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
