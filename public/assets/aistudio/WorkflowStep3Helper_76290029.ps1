# UTF-8 with BOM
function Invoke-WorkflowStep3 {
    param(
        [Parameter(Mandatory=$true)][string]$DateFolderName,
        [Parameter(Mandatory=$true)][hashtable]$Config
    )
    $rawDateDir = Join-Path $Config.Paths.RawSaveRoot $DateFolderName
    $devDateDir = Join-Path $Config.Paths.DevelopedRoot $DateFolderName
    if (-not (Test-Path -LiteralPath $rawDateDir)) { throw "RAW保存先フォルダが見つかりません: $rawDateDir" }
    if (-not (Test-Path -LiteralPath $devDateDir)) { throw "現像後フォルダが見つかりません: $devDateDir" }

    $rawExts = $Config.Extensions.RawExtensions.Split(",") | ForEach-Object { $_.Trim().ToUpper() }
    $rawMap = @{}
    Get-ChildItem -LiteralPath $rawDateDir -File -Recurse | Where-Object { $rawExts -contains $_.Extension.ToUpper() } | ForEach-Object {
        $relDir = $_.DirectoryName.Substring($rawDateDir.Length).TrimStart("\")
        if (-not [string]::IsNullOrEmpty($relDir)) {
            $rawMap[$_.BaseName.ToUpper()] = $relDir
        }
    }

    $sorted = 0
    Get-ChildItem -LiteralPath $devDateDir -File | ForEach-Object {
        $key = $_.BaseName.ToUpper()
        if ($rawMap.ContainsKey($key)) {
            $destDir = Join-Path $devDateDir $rawMap[$key]
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Move-Item -LiteralPath $_.FullName -Destination (Join-Path $destDir $_.Name) -Force
            $sorted++
        }
    }
    Write-PhotoLog -Message "Step3完了: 現像データ自動振分($sorted 件) [$DateFolderName]" -Level "INFO"
    return @{ SortedCount = $sorted }
}

function Start-WorkflowStep3Watcher {
    param(
        [Parameter(Mandatory=$true)][string]$DateFolderName,
        [Parameter(Mandatory=$true)][hashtable]$Config
    )
    $devDateDir = Join-Path $Config.Paths.DevelopedRoot $DateFolderName
    if (-not (Test-Path -LiteralPath $devDateDir)) { throw "監視対象フォルダが存在しません: $devDateDir" }
    $fsw = New-Object System.IO.FileSystemWatcher
    $fsw.Path = $devDateDir
    $fsw.IncludeSubdirectories = $false
    $fsw.EnableRaisingEvents = $true
    Register-ObjectEvent -InputObject $fsw -EventName Created -Action {
        Start-Sleep -Milliseconds 500
        try { Invoke-WorkflowStep3 -DateFolderName $Event.MessageData.DateName -Config $Event.MessageData.Cfg | Out-Null } catch {}
    } -MessageData @{ DateName = $DateFolderName; Cfg = $Config } | Out-Null
    Write-PhotoLog -Message "Step3監視モード開始: $devDateDir" -Level "INFO"
    return $fsw
}
