#requires -Version 5.1
# ==============================================================================
# WorkflowStep5Helper.ps1 - Step5: 四半期アーカイブ移動＆台帳パス追従 (UTF-8 BOM / CRLF)
# ==============================================================================

function Find-Step5DateDir {
    param(
        [string]$BaseRoot,
        [string]$DateFolderName
    )
    if ([string]::IsNullOrWhiteSpace($BaseRoot) -or [string]::IsNullOrWhiteSpace($DateFolderName)) { return "" }
    $normBase = $BaseRoot.Trim().TrimEnd('\')
    $exact = Join-Path $normBase $DateFolderName
    if (Test-Path -LiteralPath $exact) { return $exact }

    if ((Test-Path -LiteralPath $normBase) -and (Get-Command Resolve-DateFromFolderName -ErrorAction SilentlyContinue)) {
        $targetDt = Resolve-DateFromFolderName -FolderName $DateFolderName
        if ($null -ne $targetDt) {
            foreach ($sd in @(Get-ChildItem -LiteralPath $normBase -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
                $candDt = Resolve-DateFromFolderName -FolderName $sd.Name
                if ($null -ne $candDt -and $candDt.Date -eq $targetDt.Date) {
                    return $sd.FullName
                }
            }
        }
    }
    return ""
}

function Invoke-WorkflowStep5 {
    param(
        [Parameter(Mandatory=$true)][string]$DateFolderName,
        [Parameter(Mandatory=$true)][hashtable]$Config,
        [string]$DevelopedDateFolder = "",
        [string]$RawDateFolder = "",
        [string]$ImportDateFolder = ""
    )
    $periodInfo = Get-ArchivePeriodSubPath -DateFolderName $DateFolderName -Config $Config

    $devRoot = if ($Config.ContainsKey("Paths") -and $Config.Paths -is [System.Collections.IDictionary] -and $Config.Paths.ContainsKey("DevelopedRoot")) {
        [string]$Config.Paths["DevelopedRoot"]
    } elseif ($Config.ContainsKey("DevelopedRoot")) {
        [string]$Config["DevelopedRoot"]
    } else { "G:\写真\現像後" }

    $rawRoot = if ($Config.ContainsKey("Paths") -and $Config.Paths -is [System.Collections.IDictionary] -and $Config.Paths.ContainsKey("RawSaveRoot")) {
        [string]$Config.Paths["RawSaveRoot"]
    } elseif ($Config.ContainsKey("RawSaveRoot")) {
        [string]$Config["RawSaveRoot"]
    } else { "G:\写真raw" }

    $impArchRoot = if ($Config.ContainsKey("Paths") -and $Config.Paths -is [System.Collections.IDictionary] -and $Config.Paths.ContainsKey("ImportArchiveRoot")) {
        [string]$Config.Paths["ImportArchiveRoot"]
    } elseif ($Config.ContainsKey("ImportArchiveRoot")) {
        [string]$Config["ImportArchiveRoot"]
    } else { "J:\写真2\eos" }

    $devArchRoot = if ($Config.ContainsKey("Paths") -and $Config.Paths -is [System.Collections.IDictionary] -and $Config.Paths.ContainsKey("DevelopedArchiveRoot")) { [string]$Config.Paths["DevelopedArchiveRoot"] } else { "J:\写真2\現像後" }
    $rawArchRoot = if ($Config.ContainsKey("Paths") -and $Config.Paths -is [System.Collections.IDictionary] -and $Config.Paths.ContainsKey("RawArchiveRoot")) { [string]$Config.Paths["RawArchiveRoot"] } else { "L:\" }

    $devSrc = if (-not [string]::IsNullOrWhiteSpace($DevelopedDateFolder) -and (Test-Path -LiteralPath $DevelopedDateFolder)) {
        $DevelopedDateFolder.Trim().TrimEnd('\')
    } else {
        Find-Step5DateDir -BaseRoot $devRoot -DateFolderName $DateFolderName
    }
    $rawSrc = if (-not [string]::IsNullOrWhiteSpace($RawDateFolder) -and (Test-Path -LiteralPath $RawDateFolder)) {
        $RawDateFolder.Trim().TrimEnd('\')
    } else {
        Find-Step5DateDir -BaseRoot $rawRoot -DateFolderName $DateFolderName
    }

    # 取込フォルダ（カメラ取り込み元 2 / 作業用等）のソース検出
    $impSrc = ""
    if (-not [string]::IsNullOrWhiteSpace($ImportDateFolder) -and (Test-Path -LiteralPath $ImportDateFolder)) {
        $impSrc = $ImportDateFolder.Trim().TrimEnd('\')
    } else {
        $impRoots = New-Object System.Collections.Generic.List[string]
        foreach ($src in @($Config, $(if($Config.ContainsKey("Paths")){ $Config.Paths }))) {
            if ($null -ne $src -and $src -is [System.Collections.IDictionary]) {
                foreach ($k in @("ImportRoot2", "ImportRoot1", "ImportRoot")) {
                    if ($src.ContainsKey($k)) {
                        $val = [string]$src[$k]
                        if (-not [string]::IsNullOrWhiteSpace($val)) { [void]$impRoots.Add($val) }
                    }
                }
            }
        }
        foreach ($ir in $impRoots) {
            if ([string]::IsNullOrWhiteSpace($ir)) { continue }
            $candImp = Find-Step5DateDir -BaseRoot $ir -DateFolderName $DateFolderName
            if (-not [string]::IsNullOrWhiteSpace($candImp) -and (Test-Path -LiteralPath $candImp)) {
                $impSrc = $candImp
                break
            }
        }
    }

    $devDestParent = Join-Path $devArchRoot $periodInfo.RelativePeriodPath
    $rawDestParent = Join-Path $rawArchRoot $periodInfo.RelativePeriodPath
    $impDestParent = Join-Path $impArchRoot $periodInfo.RelativePeriodPath

    $devLeafName = if (-not [string]::IsNullOrWhiteSpace($devSrc)) { Split-Path -Leaf $devSrc } else { $DateFolderName }
    $rawLeafName = if (-not [string]::IsNullOrWhiteSpace($rawSrc)) { Split-Path -Leaf $rawSrc } else { $DateFolderName }
    $impLeafName = if (-not [string]::IsNullOrWhiteSpace($impSrc)) { Split-Path -Leaf $impSrc } else { $DateFolderName }

    $devDest = Join-Path $devDestParent $devLeafName
    $rawDest = Join-Path $rawDestParent $rawLeafName
    $impDest = Join-Path $impDestParent $impLeafName

    $movedDev = $false
    $movedRaw = $false
    $movedImp = $false

    if (-not [string]::IsNullOrWhiteSpace($devSrc) -and (Test-Path -LiteralPath $devSrc)) {
        if (Test-Path -LiteralPath $devDest) { throw "移動先に既に存在します: $devDest" }
        New-Item -ItemType Directory -Path $devDestParent -Force | Out-Null
        Move-Item -LiteralPath $devSrc -Destination $devDest -Force
        $movedDev = $true
        if (Get-Command Update-PhotoLedgerPathsAfterMove -ErrorAction SilentlyContinue) {
            [void](Update-PhotoLedgerPathsAfterMove -OldBasePath $devSrc -NewBasePath $devDest -ColumnType "Developed" -Config $Config)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($rawSrc) -and (Test-Path -LiteralPath $rawSrc)) {
        if (Test-Path -LiteralPath $rawDest) { throw "移動先に既に存在します: $rawDest" }
        New-Item -ItemType Directory -Path $rawDestParent -Force | Out-Null
        Move-Item -LiteralPath $rawSrc -Destination $rawDest -Force
        $movedRaw = $true
        if (Get-Command Update-PhotoLedgerPathsAfterMove -ErrorAction SilentlyContinue) {
            [void](Update-PhotoLedgerPathsAfterMove -OldBasePath $rawSrc -NewBasePath $rawDest -ColumnType "RAW" -Config $Config)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($impSrc) -and (Test-Path -LiteralPath $impSrc)) {
        if (Test-Path -LiteralPath $impDest) { throw "移動先に既に存在します: $impDest" }
        New-Item -ItemType Directory -Path $impDestParent -Force | Out-Null
        Move-Item -LiteralPath $impSrc -Destination $impDest -Force
        $movedImp = $true
        if (Get-Command Update-PhotoLedgerPathsAfterMove -ErrorAction SilentlyContinue) {
            [void](Update-PhotoLedgerPathsAfterMove -OldBasePath $impSrc -NewBasePath $impDest -ColumnType "Import" -Config $Config)
        }
    }

    if (Get-Command Write-PhotoLog -ErrorAction SilentlyContinue) {
        Write-PhotoLog -Message "Step5完了: アーカイブ移動(Dev=$movedDev, Raw=$movedRaw, Import=$movedImp / $($periodInfo.RelativePeriodPath)\$DateFolderName)および台帳追従完了" -ModuleName "WorkflowStep5" -Level "INFO" | Out-Null
    }
    return @{
        ArchiveDevelopedPath = if ($movedDev) { $devDest } else { "" }
        ArchiveRawPath       = if ($movedRaw) { $rawDest } else { "" }
        ArchiveImportPath    = if ($movedImp) { $impDest } else { "" }
        MovedDeveloped       = $movedDev
        MovedRaw             = $movedRaw
        MovedImport          = $movedImp
        MovedAny             = ($movedDev -or $movedRaw -or $movedImp)
    }
}
