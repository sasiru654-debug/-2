# MegaHelper.ps1
# MEGA同期フォルダからの共有リンク取得・クリップボードコピー

function Get-MegaShareLink {
    param(
        [string]$FolderPath,
        [hashtable]$Config
    )
    Write-PhotoLog -Message "MEGA共有リンク取得開始: $FolderPath" -Level "INFO" -Module "MegaHelper"
    try {
        if (-not (Test-Path -LiteralPath $FolderPath)) {
            throw "対象フォルダが存在しません: $FolderPath"
        }

        $megaCmd = if ($Config.ContainsKey("MegaCmdPath") -and $Config["MegaCmdPath"]) {
            $Config["MegaCmdPath"]
        } else {
            Join-Path $env:LOCALAPPDATA "MEGAcmd\mega-export.bat"
        }

        if (-not (Test-Path -LiteralPath $megaCmd)) {
            $cmdFound = Get-Command "mega-export" -ErrorAction SilentlyContinue
            if ($cmdFound) { $megaCmd = $cmdFound.Source }
        }

        if (-not (Test-Path -LiteralPath $megaCmd)) {
            throw "MEGAcmd (mega-export) が見つかりません。settings.ini の MegaCmdPath を確認してください。"
        }

        $output = & $megaCmd -a $FolderPath 2>&1 | Out-String
        if ($output -match "(https://mega\.nz/[^\s\r\n]+)") {
            $url = $Matches[1]
            Set-Clipboard -Value $url
            Write-PhotoLog -Message "MEGAリンク取得成功・コピー完了: $url" -Level "INFO" -Module "MegaHelper"
            return $url
        }

        $listOut = & $megaCmd $FolderPath 2>&1 | Out-String
        if ($listOut -match "(https://mega\.nz/[^\s\r\n]+)") {
            $url = $Matches[1]
            Set-Clipboard -Value $url
            Write-PhotoLog -Message "既存MEGAリンク取得・コピー完了: $url" -Level "INFO" -Module "MegaHelper"
            return $url
        }

        throw "MEGAリンクを取得できませんでした（同期対象外フォルダの可能性があります）: $output"
    }
    catch {
        Write-PhotoError -ErrorRecord $_ -Module "MegaHelper"
        throw
    }
}
