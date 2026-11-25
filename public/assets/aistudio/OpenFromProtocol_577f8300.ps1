# OpenFromProtocol.ps1
# photoinfo://open?path=... プロトコル受信・PhotoInfoEditor直接起動

param(
    [Parameter(Mandatory = $true)]
    [string]$Uri
)

$commonDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $commonDir
. (Join-Path $commonDir "LogHelper.ps1")

Write-PhotoLog -Message "プロトコル起動受信: $Uri" -Level "INFO" -Module "OpenFromProtocol"

try {
    if ($Uri -match "path=([^&]+)") {
        $encodedPath = $Matches[1]
        $targetPath = [System.Uri]::UnescapeDataString($encodedPath)
        $editorScript = Join-Path $rootDir "editor\PhotoInfoEditor.ps1"

        if (Test-Path -LiteralPath $targetPath) {
            Write-PhotoLog -Message "編集画面を起動します: $targetPath" -Level "INFO" -Module "OpenFromProtocol"
            Start-Process powershell.exe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", "`"$editorScript`"", "-TargetPath", "`"$targetPath`"")
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("対象フォルダが見つかりません:`n$targetPath", "PhotoTools エラー") | Out-Null
            Write-PhotoLog -Message "対象フォルダ不在: $targetPath" -Level "ERROR" -Module "OpenFromProtocol"
        }
    }
}
catch {
    Write-PhotoError -ErrorRecord $_ -Module "OpenFromProtocol"
}
