#requires -Version 5.1
# ==============================================================================
# OpenFromProtocol.ps1 - photoinfo://open?path=... プロトコル受信起動 (UTF-8 BOM / CRLF)
# ==============================================================================
param(
    [Parameter(Mandatory = $true)]
    [string]$Uri
)

Add-Type -AssemblyName System.Windows.Forms

$commonDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $commonDir
. (Join-Path $commonDir "LogHelper.ps1")
Initialize-PhotoLogger -RootDir $rootDir | Out-Null

Write-PhotoLog -Message "プロトコル起動受信: $Uri" -Level "INFO" -Module "OpenFromProtocol"

try {
    if ($Uri -match "path=([^&]+)") {
        $encodedPath = $Matches[1]
        $targetPath = [System.Uri]::UnescapeDataString($encodedPath).Trim().Trim('"')
        $editorScript = Join-Path $rootDir "editor\PhotoInfoEditor.ps1"

        if (Test-Path -LiteralPath $targetPath) {
            Write-PhotoLog -Message "編集画面を起動します: $targetPath" -Level "INFO" -Module "OpenFromProtocol"
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$editorScript`" -TargetPath `"$targetPath`" -ForceEditor"
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            [void][System.Diagnostics.Process]::Start($psi)
        }
        else {
            Show-MsgBox -Text "対象フォルダが見つかりません:`n$targetPath" -Title "PhotoTools エラー" -Buttons "OK" -Icon "Error" | Out-Null
            Write-PhotoLog -Message "対象フォルダ不在: $targetPath" -Level "ERROR" -Module "OpenFromProtocol"
        }
    }
}
catch {
    Write-PhotoError -ErrorRecord $_ -Module "OpenFromProtocol"
    Show-MsgBox -Text "起動エラー:`n$($_.Exception.Message)" -Title "PhotoTools エラー" -Buttons "OK" -Icon "Error" | Out-Null
}
