# UTF-8 with BOM
function Invoke-WorkflowStep2 {
    param(
        [Parameter(Mandatory=$true)][string]$ImportDateFolder,
        [Parameter(Mandatory=$true)][hashtable]$Config
    )
    if (-not (Test-Path -LiteralPath $ImportDateFolder)) { throw "取込先フォルダが存在しません: $ImportDateFolder" }
    $dateName = Split-Path $ImportDateFolder -Leaf
    $rawDateDir = Join-Path $Config.Paths.RawSaveRoot $dateName
    $devDateDir = Join-Path $Config.Paths.DevelopedRoot $dateName
    New-Item -ItemType Directory -Path $rawDateDir -Force | Out-Null
    New-Item -ItemType Directory -Path $devDateDir -Force | Out-Null

    $rawExts = $Config.Extensions.RawExtensions.Split(",") | ForEach-Object { $_.Trim().ToUpper() }
    $movedRaw = 0

    $allDirs = Get-ChildItem -LiteralPath $ImportDateFolder -Directory -Recurse
    foreach ($dir in $allDirs) {
        $relPath = $dir.FullName.Substring($ImportDateFolder.Length).TrimStart("\")
        $targetRawSub = Join-Path $rawDateDir $relPath
        $targetDevSub = Join-Path $devDateDir $relPath
        New-Item -ItemType Directory -Path $targetRawSub -Force | Out-Null
        New-Item -ItemType Directory -Path $targetDevSub -Force | Out-Null

        $infoSrc = Join-Path $dir.FullName "写真情報.txt"
        if (Test-Path -LiteralPath $infoSrc) {
            Copy-Item -LiteralPath $infoSrc -Destination (Join-Path $targetDevSub "写真情報.txt") -Force
        }

        $files = Get-ChildItem -LiteralPath $dir.FullName -File
        foreach ($f in $files) {
            if ($rawExts -contains $f.Extension.ToUpper()) {
                Move-Item -LiteralPath $f.FullName -Destination (Join-Path $targetRawSub $f.Name) -Force
                $movedRaw++
            }
        }
    }
    Write-PhotoLog -Message "Step2完了: 構成複製およびRAW移動($movedRaw 件)完了 [$dateName]" -Level "INFO"
    return @{ MovedRawCount = $movedRaw; RawDateDir = $rawDateDir; DevDateDir = $devDateDir }
}
