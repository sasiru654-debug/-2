#requires -Version 5.1
# ==============================================================================
# WorkflowStep2Helper.ps1 - Step2: フォルダ構成複製およびRAWデータ移動 (UTF-8 BOM / CRLF)
# ==============================================================================

function Test-IsAllowedImportFolderForStep2 {
    param(
        [string]$TargetFolder,
        [hashtable]$Config
    )
    if ($null -eq $Config -or [string]::IsNullOrWhiteSpace($TargetFolder)) { return $false }
    $normTarget = $TargetFolder.Trim().TrimEnd('\')
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($src in @($Config, $Config.Paths)) {
        if ($src -is [hashtable]) {
            foreach ($k in @("ImportRoot1", "ImportRoot2")) {
                $val = [string]$src[$k]
                if (-not [string]::IsNullOrWhiteSpace($val)) { [void]$candidates.Add($val.Trim().TrimEnd('\')) }
            }
        }
    }
    if ($candidates.Count -eq 0) {
        foreach ($src in @($Config, $Config.Paths)) {
            if ($src -is [hashtable]) {
                $val = [string]$src["ImportRoot"]
                if (-not [string]::IsNullOrWhiteSpace($val)) { [void]$candidates.Add($val.Trim().TrimEnd('\')) }
            }
        }
    }
    foreach ($root in $candidates) {
        if (($normTarget -ieq $root) -or $normTarget.StartsWith(($root + "\"), [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Invoke-WorkflowStep2 {
    param(
        [Parameter(Mandatory=$true)][string]$ImportDateFolder,
        [Parameter(Mandatory=$true)][hashtable]$Config
    )
    if (-not (Test-IsAllowedImportFolderForStep2 -TargetFolder $ImportDateFolder -Config $Config)) {
        throw "Step2はカメラ取り込み元 1 またはカメラ取り込み元 2 配下のフォルダでのみ実行できます: $ImportDateFolder"
    }
    if (-not (Test-Path -LiteralPath $ImportDateFolder)) {
        throw "取込先フォルダが存在しません: $ImportDateFolder"
    }
    $dateName = Split-Path $ImportDateFolder -Leaf
    $isRoot2 = $false
    if ($null -ne $Config) {
        $imp2 = if ($Config.ContainsKey("ImportRoot2")) { $Config["ImportRoot2"] } elseif ($Config.ContainsKey("Paths") -and $Config.Paths -is [hashtable] -and $Config.Paths.ContainsKey("ImportRoot2")) { $Config.Paths["ImportRoot2"] } else { "" }
        if (-not [string]::IsNullOrWhiteSpace([string]$imp2)) {
            $impRoot2Norm = ([string]$imp2).Trim().TrimEnd('\')
            if ($ImportDateFolder.Trim().TrimEnd('\').StartsWith($impRoot2Norm, [System.StringComparison]::OrdinalIgnoreCase)) {
                $isRoot2 = $true
            }
        }
    }
    $rawSaveBase = if ($isRoot2) {
        $r2 = if ($Config.ContainsKey("RawSaveRoot2")) { $Config["RawSaveRoot2"] } elseif ($Config.ContainsKey("Paths") -and $Config.Paths -is [hashtable] -and $Config.Paths.ContainsKey("RawSaveRoot2")) { $Config.Paths["RawSaveRoot2"] } else { "" }
        if (-not [string]::IsNullOrWhiteSpace([string]$r2)) { [string]$r2 } else {
            $cfgRaw = if ($Config.ContainsKey("Paths") -and $Config.Paths -is [System.Collections.IDictionary] -and $Config.Paths.ContainsKey("RawSaveRoot")) {
                [string]$Config.Paths.RawSaveRoot
            } elseif ($Config.ContainsKey("RawSaveRoot")) {
                [string]$Config.RawSaveRoot
            } else { "G:\写真raw" }
            if ([string]::IsNullOrWhiteSpace($cfgRaw)) { "G:\写真raw" } else { $cfgRaw }
        }
    } else {
        $cfgRaw = if ($Config.ContainsKey("Paths") -and $Config.Paths -is [System.Collections.IDictionary] -and $Config.Paths.ContainsKey("RawSaveRoot")) {
            [string]$Config.Paths.RawSaveRoot
        } elseif ($Config.ContainsKey("RawSaveRoot")) {
            [string]$Config.RawSaveRoot
        } else { "G:\写真raw" }
        if ([string]::IsNullOrWhiteSpace($cfgRaw)) { "G:\写真raw" } else { $cfgRaw }
    }
    $rawDateDir = Join-Path $rawSaveBase $dateName
    $devRootVal = if ($Config.ContainsKey("DevelopedRoot")) { [string]$Config["DevelopedRoot"] } elseif ($Config.ContainsKey("Paths") -and $Config.Paths -is [hashtable] -and $Config.Paths.ContainsKey("DevelopedRoot")) { [string]$Config.Paths["DevelopedRoot"] } else { "G:\写真\現像後" }
    $devDateDir = Join-Path $devRootVal $dateName
    New-Item -ItemType Directory -Path $rawDateDir -Force | Out-Null
    New-Item -ItemType Directory -Path $devDateDir -Force | Out-Null

    $rawExts = if ($null -ne $Config -and $Config.ContainsKey("Extensions") -and $Config.Extensions -is [hashtable] -and $Config.Extensions.ContainsKey("RawExtensions")) {
        if (Get-Command ConvertTo-PhotoExtensionArray -ErrorAction SilentlyContinue) {
            ConvertTo-PhotoExtensionArray $Config.Extensions.RawExtensions
        } else {
            @($Config.Extensions.RawExtensions | ForEach-Object { ([string]$_).Trim().ToUpper() })
        }
    } else {
        @(".ARW", ".CR2", ".CR3", ".NEF", ".RAF", ".ORF", ".RW2", ".DNG")
    }

    $movedRaw = 0

    $parentScene = Join-Path $ImportDateFolder "scene.txt"
    if (Test-Path -LiteralPath $parentScene) {
        Copy-Item -LiteralPath $parentScene -Destination (Join-Path $rawDateDir "scene.txt") -Force
        Copy-Item -LiteralPath $parentScene -Destination (Join-Path $devDateDir "scene.txt") -Force
    }

    $allDirs = Get-ChildItem -LiteralPath $ImportDateFolder -Directory -Recurse
    foreach ($dir in $allDirs) {
        $relPath = $dir.FullName.Substring($ImportDateFolder.Length).TrimStart("\")
        $targetRawSub = Join-Path $rawDateDir $relPath
        $targetDevSub = Join-Path $devDateDir $relPath
        New-Item -ItemType Directory -Path $targetRawSub -Force | Out-Null
        New-Item -ItemType Directory -Path $targetDevSub -Force | Out-Null

        $sceneSrc = Join-Path $dir.FullName "scene.txt"
        if (Test-Path -LiteralPath $sceneSrc) {
            Copy-Item -LiteralPath $sceneSrc -Destination (Join-Path $targetRawSub "scene.txt") -Force
            Copy-Item -LiteralPath $sceneSrc -Destination (Join-Path $targetDevSub "scene.txt") -Force
        }

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
    if (Get-Command Write-PhotoLog -ErrorAction SilentlyContinue) {
        Write-PhotoLog -Message "Step2完了: 構成複製およびRAW移動($movedRaw 件)完了 [$dateName]" -ModuleName "WorkflowStep2" -Level "INFO" | Out-Null
    }
    return @{ MovedRawCount = $movedRaw; RawDateDir = $rawDateDir; DevDateDir = $devDateDir }
}
