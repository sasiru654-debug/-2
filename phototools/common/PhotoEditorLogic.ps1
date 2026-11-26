#requires -Version 5.1
# ==============================================================================
# PhotoEditorLogic.ps1 - ペアフォルダ解決・双方向同期・補完・台帳保存 (UTF-8 BOM / CRLF)
# ==============================================================================

$script:LogicCommonDir = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { "D:\PhotoTools\common" }
$script:LogicRootDir = Split-Path -Parent $script:LogicCommonDir
foreach ($helper in @("LogHelper.ps1", "ConfigHelper.ps1", "MegaHelper.ps1", "XHelper.ps1", "ExcelHelper.ps1", "SceneHelper.ps1", "GigaFileHelper.ps1", "PhotoInfoHelper.ps1")) {
    $hp1 = Join-Path $script:LogicCommonDir $helper
    $hp2 = Join-Path $script:LogicRootDir $helper
    if (Test-Path -LiteralPath $hp1) {
        . $hp1
    } elseif (Test-Path -LiteralPath $hp2) {
        . $hp2
    }
}

function Initialize-PhotoEditorEnvironment {
    param(
        [string]$ScriptDir = "",
        [hashtable]$ExternalConfig = @{}
    )

    if ([string]::IsNullOrWhiteSpace($ScriptDir)) {
        $ScriptDir = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { "D:\PhotoTools\editor" }
    }
    $rootDir = Split-Path -Parent $ScriptDir
    if (-not (Test-Path -LiteralPath (Join-Path $rootDir "settings.ini"))) {
        if (Test-Path -LiteralPath "D:\PhotoTools\settings.ini") {
            $rootDir = "D:\PhotoTools"
        }
    }

    $commonDir = Join-Path $rootDir "common"
    if (-not ($commonDir -ieq $script:LogicCommonDir)) {
        foreach ($helper in @("LogHelper.ps1", "ConfigHelper.ps1", "MegaHelper.ps1", "XHelper.ps1", "ExcelHelper.ps1", "SceneHelper.ps1", "GigaFileHelper.ps1", "PhotoInfoHelper.ps1")) {
            $hp1 = Join-Path $commonDir $helper
            if (Test-Path -LiteralPath $hp1) {
                . $hp1
            }
        }
    }

    if (Get-Command Initialize-PhotoLogger -ErrorAction SilentlyContinue) {
        Initialize-PhotoLogger -RootDir $rootDir | Out-Null
    }

    $eff = if (Get-Command Get-PhotoToolsConfig -ErrorAction SilentlyContinue) {
        Get-PhotoToolsConfig -RootDir $rootDir
    } else {
        @{ RootDir = $rootDir }
    }

    # ExternalConfig が明示された場合は上書きマージ
    if ($null -ne $ExternalConfig -and ($ExternalConfig -is [System.Collections.IDictionary]) -and $ExternalConfig.Count -gt 0) {
        foreach ($k in $ExternalConfig.Keys) {
            $eff[$k] = $ExternalConfig[$k]
        }
        if ($ExternalConfig.ContainsKey("DevRoot") -and -not $ExternalConfig.ContainsKey("DevelopedRoot")) {
            $eff["DevelopedRoot"] = [string]$ExternalConfig["DevRoot"]
        }
        if ($ExternalConfig.ContainsKey("DevelopedRoot") -and -not $ExternalConfig.ContainsKey("DevRoot")) {
            $eff["DevRoot"] = [string]$ExternalConfig["DevelopedRoot"]
        }
        if ($ExternalConfig.ContainsKey("HistoryPath") -and -not $ExternalConfig.ContainsKey("XHistoryPath")) {
            $eff["XHistoryPath"] = [string]$ExternalConfig["HistoryPath"]
        }
        if ($ExternalConfig.ContainsKey("XHistoryPath") -and -not $ExternalConfig.ContainsKey("HistoryPath")) {
            $eff["HistoryPath"] = [string]$ExternalConfig["XHistoryPath"]
        }
    }

    return $eff
}

function ConvertTo-NormalizedX {
    param([string]$Raw)
    if (Get-Command Normalize-XAccount -ErrorAction SilentlyContinue) {
        return (Normalize-XAccount $Raw)
    }
    if ([string]::IsNullOrWhiteSpace($Raw)) { return "" }
    $s = $Raw.Trim() -replace '^[（\(\s]+', '' -replace '[）\)\s]+$', ''
    if ($s -match '(?:https?://)?(?:www\.)?(?:x\.com|twitter\.com)/([A-Za-z0-9_]+)') {
        return "@" + $Matches[1]
    }
    $s = $s.TrimStart('@', '＠')
    if ($s -match '^([A-Za-z0-9_]+)') {
        return "@" + $Matches[1]
    }
    return ""
}

function ConvertTo-CleanModelName {
    param([string]$RawName)
    if ([string]::IsNullOrWhiteSpace($RawName)) { return "" }
    $n = $RawName.Trim()
    $idxHalf = $n.IndexOf('@')
    $idxFull = $n.IndexOf('＠')
    $cut = -1
    if ($idxHalf -ge 0 -and $idxFull -ge 0) { $cut = [Math]::Min($idxHalf, $idxFull) }
    elseif ($idxHalf -ge 0) { $cut = $idxHalf }
    elseif ($idxFull -ge 0) { $cut = $idxFull }
    if ($cut -gt 0) {
        $n = $n.Substring(0, $cut).Trim()
    }
    return $n
}

function Find-MatchingDateDirByNameOrDateKey {
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
            $subDirs = @(Get-ChildItem -LiteralPath $normBase -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
            foreach ($sd in $subDirs) {
                $candDt = Resolve-DateFromFolderName -FolderName $sd.Name
                if ($null -ne $candDt -and $candDt.Date -eq $targetDt.Date) {
                    return $sd.FullName
                }
            }
        }
    }
    return ""
}

function Resolve-PairedPhotoFolders {
    param(
        [string]$Folder,
        [hashtable]$EffectiveConfig
    )
    $res = @{
        Target       = $Folder
        RelPath      = ""
        ImportFolder = ""
        RawFolder    = ""
        DevFolder    = ""
        DateStr      = ""
        FolderName   = if ([string]::IsNullOrWhiteSpace($Folder)) { "" } else { [System.IO.Path]::GetFileName($Folder) }
    }
    if ([string]::IsNullOrWhiteSpace($Folder)) { return $res }

    $normFolder = $Folder.TrimEnd('\')
    if (Test-Path -LiteralPath $normFolder -PathType Leaf) {
        $normFolder = Split-Path -Parent $normFolder
        $res.Target = $normFolder
        $res.FolderName = [System.IO.Path]::GetFileName($normFolder)
    }

    $importPrimary   = if (-not [string]::IsNullOrWhiteSpace([string]$EffectiveConfig.ImportRoot1)) { [string]$EffectiveConfig.ImportRoot1 } else { [string]$EffectiveConfig.ImportRoot }
    $importSecondary = [string]$EffectiveConfig.ImportRoot2
    $rawSaveRoot     = [string]$EffectiveConfig.RawSaveRoot
    $devRoot         = if (-not [string]::IsNullOrWhiteSpace([string]$EffectiveConfig.DevRoot)) { [string]$EffectiveConfig.DevRoot } else { [string]$EffectiveConfig.DevelopedRoot }
    $dateRegex       = '^\d{4}(?:[-_.]\d{2}[-_.]\d{2}|\d{4})(?:$|[_\-\s].*)'

    $roots = @(
        @{ Path = $importPrimary;   Type = "Import" },
        @{ Path = $importSecondary; Type = "Import" },
        @{ Path = $rawSaveRoot;     Type = "WorkRaw" },
        @{ Path = $devRoot;         Type = "Dev" }
    )

    foreach ($r in $roots) {
        $rp = ([string]$r.Path).TrimEnd('\')
        if (-not [string]::IsNullOrWhiteSpace($rp) -and (($normFolder -ieq $rp) -or $normFolder.StartsWith(($rp + "\"), [System.StringComparison]::OrdinalIgnoreCase))) {
            $rel = if ($normFolder.Length -gt $rp.Length) { $normFolder.Substring($rp.Length).TrimStart('\') } else { "" }
            $res.RelPath = $rel
            if (-not [string]::IsNullOrWhiteSpace($rel)) {
                $parts = @($rel -split '\\')
                $datePart = ""
                $subRel = ""
                if (@($parts).Count -ge 1 -and $parts[0] -match $dateRegex) {
                    $datePart = $parts[0]
                    $res.DateStr = $datePart
                    if (@($parts).Count -gt 1) {
                        $subRel = ($parts[1..(@($parts).Count - 1)] -join '\')
                    }
                }

                $cands = @()
                foreach ($impR in @($importPrimary, $importSecondary)) {
                    if ([string]::IsNullOrWhiteSpace($impR)) { continue }
                    if (-not [string]::IsNullOrWhiteSpace($datePart)) {
                        $matchedDateDir = Find-MatchingDateDirByNameOrDateKey -BaseRoot $impR -DateFolderName $datePart
                        if (-not [string]::IsNullOrWhiteSpace($matchedDateDir)) {
                            $cands += if ([string]::IsNullOrWhiteSpace($subRel)) { $matchedDateDir } else { Join-Path $matchedDateDir $subRel }
                        } else {
                            $cands += (Join-Path $impR $rel)
                        }
                    } else {
                        $cands += (Join-Path $impR $rel)
                    }
                }
                if (-not [string]::IsNullOrWhiteSpace($rawSaveRoot)) {
                    if (-not [string]::IsNullOrWhiteSpace($datePart)) {
                        $matchedRawDate = Find-MatchingDateDirByNameOrDateKey -BaseRoot $rawSaveRoot -DateFolderName $datePart
                        $rawCand = if (-not [string]::IsNullOrWhiteSpace($matchedRawDate)) {
                            if ([string]::IsNullOrWhiteSpace($subRel)) { $matchedRawDate } else { Join-Path $matchedRawDate $subRel }
                        } else {
                            Join-Path $rawSaveRoot $rel
                        }
                        $res.RawFolder = $rawCand
                        $cands += $rawCand
                    } else {
                        $rawCand = Join-Path $rawSaveRoot $rel
                        $res.RawFolder = $rawCand
                        $cands += $rawCand
                    }
                }

                $chosenImport = ""
                foreach ($c in $cands) {
                    if (Test-Path -LiteralPath $c) { $chosenImport = $c; break }
                }
                if ([string]::IsNullOrWhiteSpace($chosenImport) -and @($cands).Count -gt 0) {
                    $chosenImport = $cands[0]
                }
                $res.ImportFolder = $chosenImport

                if (-not [string]::IsNullOrWhiteSpace($devRoot)) {
                    if (-not [string]::IsNullOrWhiteSpace($datePart)) {
                        $matchedDevDate = Find-MatchingDateDirByNameOrDateKey -BaseRoot $devRoot -DateFolderName $datePart
                        if (-not [string]::IsNullOrWhiteSpace($matchedDevDate)) {
                            $res.DevFolder = if ([string]::IsNullOrWhiteSpace($subRel)) { $matchedDevDate } else { Join-Path $matchedDevDate $subRel }
                        } else {
                            $res.DevFolder = Join-Path $devRoot $rel
                        }
                    } else {
                        $res.DevFolder = Join-Path $devRoot $rel
                    }
                }
            }
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($res.DateStr)) {
        $curr = $normFolder
        for ($i = 0; $i -lt 5; $i++) {
            if ([string]::IsNullOrWhiteSpace($curr)) { break }
            $fn = [System.IO.Path]::GetFileName($curr)
            if ($fn -match $dateRegex) {
                $res.DateStr = $fn
                break
            }
            $curr = [System.IO.Path]::GetDirectoryName($curr)
        }
    }

    if ([string]::IsNullOrWhiteSpace($res.ImportFolder) -and [string]::IsNullOrWhiteSpace($res.DevFolder)) {
        $res.DevFolder = $normFolder
    }

    return $res
}

function Sync-PhotoInfoFiles {
    param([hashtable]$PairedObj)
    $candidates = @()
    foreach ($dir in @($PairedObj.Target, $PairedObj.ImportFolder, $PairedObj.DevFolder)) {
        if (-not [string]::IsNullOrWhiteSpace($dir) -and (Test-Path -LiteralPath $dir)) {
            $pNew = Join-Path $dir "写真情報.txt"
            $pOld = Join-Path $dir "info.txt"
            if ((Test-Path -LiteralPath $pOld) -and (-not (Test-Path -LiteralPath $pNew))) {
                Rename-Item -LiteralPath $pOld -NewName "写真情報.txt" -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $pNew) {
                $candidates += (Get-Item -LiteralPath $pNew)
            }
        }
    }

    if ($candidates.Count -gt 0) {
        $latest = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        foreach ($dir in @($PairedObj.Target, $PairedObj.ImportFolder, $PairedObj.DevFolder)) {
            if (-not [string]::IsNullOrWhiteSpace($dir) -and (Test-Path -LiteralPath $dir)) {
                $dest = Join-Path $dir "写真情報.txt"
                if (-not ($dest -ieq $latest.FullName)) {
                    Copy-Item -LiteralPath $latest.FullName -Destination $dest -Force -ErrorAction SilentlyContinue
                }
            }
        }
        return $latest.FullName
    }
    return ""
}

function Resolve-SceneFromFolders {
    param([hashtable]$PairedObj)
    if (Get-Command Resolve-SceneInfoFromHierarchy -ErrorAction SilentlyContinue) {
        $sInfo = Resolve-SceneInfoFromHierarchy -StartDir $PairedObj.Target -PairedObj $PairedObj
        if ($null -ne $sInfo -and (-not [string]::IsNullOrWhiteSpace([string]$sInfo.SourceFile) -or -not [string]::IsNullOrWhiteSpace([string]$sInfo.SceneName))) {
            return $sInfo
        }
    }
    return @{ Category = "イベント"; SceneName = ""; SourceFile = "" }
}

function Read-PhotoInfoData {
    param(
        [string]$FilePath,
        [hashtable]$PairedObj
    )
    if (Get-Command Read-PhotoInfoTxt -ErrorAction SilentlyContinue) {
        $folderForInit = if (-not [string]::IsNullOrWhiteSpace($FilePath)) { Split-Path -Parent $FilePath } else { [string]$PairedObj.Target }
        $parsed = Read-PhotoInfoTxt -FolderPath $folderForInit -FilePath $FilePath
        if ([string]::IsNullOrWhiteSpace($parsed.DateStr) -and -not [string]::IsNullOrWhiteSpace([string]$PairedObj.DateStr)) {
            $parsed.DateStr = [string]$PairedObj.DateStr
        }
        $pPersons = if ($parsed -is [System.Collections.IDictionary] -and $parsed.Contains("Persons")) { $parsed["Persons"] } else { $parsed.Persons }
        return @{
            Category       = [string]$parsed.Category
            DateStr        = [string]$parsed.DateStr
            EventName      = [string]$parsed.EventName
            MegaLink       = [string]$parsed.MegaLink
            GigaFileLink   = [string]$parsed.GigaFileLink
            DlPassword     = [string]$parsed.DlPassword
            GigaFileExpiry = [string]$parsed.GigaFileExpiry
            SentStatus     = [string]$parsed.SentStatus
            Memo           = [string]$parsed.Notes
            Persons        = $pPersons
        }
    }

    $persons = New-Object System.Collections.Generic.List[hashtable]
    $persons.Add(@{ Name = ""; CostumeOrChar = ""; XAccount = ""; Comment = "" })
    return @{
        Category       = "イベント"
        DateStr        = [string]$PairedObj.DateStr
        EventName      = ""
        MegaLink       = ""
        GigaFileLink   = ""
        DlPassword     = ""
        GigaFileExpiry = ""
        SentStatus     = "未送付"
        Memo           = ""
        Persons        = $persons
    }
}

function Find-SameDayCostumeForModel {
    param(
        [string]$ModelName,
        [string]$DateStr,
        [hashtable]$PairedObj,
        [object]$CurrentPersons = $null,
        [int]$ExcludeIndex = -1
    )
    $cleanTarget = ConvertTo-CleanModelName $ModelName
    if ([string]::IsNullOrWhiteSpace($cleanTarget)) { return "" }

    if ($null -ne $CurrentPersons) {
        $cpArr = @($CurrentPersons)
        for ($i = 0; $i -lt $cpArr.Count; $i++) {
            if ($i -eq $ExcludeIndex) { continue }
            $p = $cpArr[$i]
            if ($null -eq $p) { continue }
            $pNameRaw = if ($p -is [System.Collections.IDictionary]) {
                            if ($p.Contains("Name") -and $null -ne $p["Name"]) { [string]$p["Name"] } else { "" }
                        } elseif ($null -ne $p.PSObject.Properties["Name"] -and $null -ne $p.Name) { [string]$p.Name } else { "" }
            $pCos     = if ($p -is [System.Collections.IDictionary]) {
                            if ($p.Contains("CostumeOrChar") -and $null -ne $p["CostumeOrChar"]) { [string]$p["CostumeOrChar"] } else { "" }
                        } elseif ($null -ne $p.PSObject.Properties["CostumeOrChar"] -and $null -ne $p.CostumeOrChar) { [string]$p.CostumeOrChar } else { "" }
            $pName = ConvertTo-CleanModelName $pNameRaw
            if (($pName -ieq $cleanTarget) -and -not [string]::IsNullOrWhiteSpace($pCos)) {
                return $pCos.Trim()
            }
        }
    }

    $searchRoots = New-Object System.Collections.ArrayList
    foreach ($base in @($PairedObj.Target, $PairedObj.DevFolder, $PairedObj.ImportFolder)) {
        if ([string]::IsNullOrWhiteSpace($base) -or -not (Test-Path -LiteralPath $base)) { continue }
        $curr = $base
        $dateRoot = ""
        for ($d = 0; $d -lt 5; $d++) {
            if ([string]::IsNullOrWhiteSpace($curr)) { break }
            $fn = [System.IO.Path]::GetFileName($curr)
            if (-not [string]::IsNullOrWhiteSpace($DateStr) -and $fn -eq $DateStr) {
                $dateRoot = $curr
                break
            }
            if ($fn -match '\d{4}[_-]\d{2}[_-]\d{2}') {
                $dateRoot = $curr
                break
            }
            $curr = [System.IO.Path]::GetDirectoryName($curr)
        }
        if ([string]::IsNullOrWhiteSpace($dateRoot)) {
            $dateRoot = [System.IO.Path]::GetDirectoryName($base)
        }
        if (-not [string]::IsNullOrWhiteSpace($dateRoot) -and (Test-Path -LiteralPath $dateRoot) -and ($searchRoots -notcontains $dateRoot)) {
            [void]$searchRoots.Add($dateRoot)
        }
    }

    foreach ($root in $searchRoots) {
        $infoPaths = @()
        try {
            $infoPaths = @([System.IO.Directory]::GetFiles($root, "写真情報.txt", [System.IO.SearchOption]::AllDirectories))
        } catch {
            $infoPaths = @(Get-ChildItem -LiteralPath $root -Filter "写真情報.txt" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        }
        foreach ($infoPath in $infoPaths) {
            if ([string]::IsNullOrWhiteSpace($infoPath)) { continue }
            $parsed = Read-PhotoInfoData -FilePath $infoPath -PairedObj $PairedObj
            if ($null -eq $parsed) { continue }
            $rawParsedPersons = if ($parsed -is [System.Collections.IDictionary]) {
                                    if ($parsed.Contains("Persons")) { $parsed["Persons"] } else { $null }
                                } elseif ($null -ne $parsed.PSObject.Properties["Persons"]) { $parsed.Persons } else { $null }
            $parsedPersons = New-Object System.Collections.ArrayList
            if ($null -ne $rawParsedPersons) {
                if ($rawParsedPersons -is [System.Collections.IDictionary]) {
                    [void]$parsedPersons.Add($rawParsedPersons)
                } elseif ($rawParsedPersons -is [System.Collections.IEnumerable] -and -not ($rawParsedPersons -is [string])) {
                    foreach ($rpItem in $rawParsedPersons) {
                        if ($null -ne $rpItem) { [void]$parsedPersons.Add($rpItem) }
                    }
                } else {
                    [void]$parsedPersons.Add($rawParsedPersons)
                }
            }
            foreach ($p in $parsedPersons) {
                if ($null -eq $p) { continue }
                $pNameRaw = if ($p -is [System.Collections.IDictionary]) { if ($p.Contains("Name") -and $null -ne $p["Name"]) { [string]$p["Name"] } else { "" } } elseif ($null -ne $p.PSObject.Properties["Name"] -and $null -ne $p.Name) { [string]$p.Name } else { "" }
                $pCos     = if ($p -is [System.Collections.IDictionary]) { if ($p.Contains("CostumeOrChar") -and $null -ne $p["CostumeOrChar"]) { [string]$p["CostumeOrChar"] } else { "" } } elseif ($null -ne $p.PSObject.Properties["CostumeOrChar"] -and $null -ne $p.CostumeOrChar) { [string]$p.CostumeOrChar } else { "" }
                $pName = ConvertTo-CleanModelName $pNameRaw
                if (($pName -ieq $cleanTarget) -and -not [string]::IsNullOrWhiteSpace($pCos)) {
                    return $pCos.Trim()
                }
            }
        }
    }

    return ""
}

function Save-AllPhotoInfoAndLedger {
    param(
        [hashtable]$FormData,
        [object]$PersonsList,
        [hashtable]$PairedObj,
        [hashtable]$EffectiveConfig,
        [array]$RelatedFolders = @()
    )

    $catVal   = [string]$FormData.Category
    $dateVal  = [string]$FormData.DateStr
    $eventVal = [string]$FormData.EventName
    $megaVal  = [string]$FormData.MegaLink
    $gigaVal  = [string]$FormData.GigaFileLink
    $dlPwVal  = if ($FormData.ContainsKey("DlPassword")) { [string]$FormData.DlPassword } else { "" }
    $expVal   = if ($FormData.ContainsKey("GigaFileExpiry")) { [string]$FormData.GigaFileExpiry } else { "" }
    $sentVal  = if ($FormData.ContainsKey("SentStatus") -and -not [string]::IsNullOrWhiteSpace([string]$FormData.SentStatus)) {
                    $rawS = ([string]$FormData.SentStatus).Trim()
                    if ($rawS -eq "送付済") { "送付済み" } else { $rawS }
                } elseif (-not [string]::IsNullOrWhiteSpace($gigaVal)) {
                    "送付済み"
                } else {
                    "未送付"
                }
    $memoVal  = if ($FormData.ContainsKey("Memo")) { [string]$FormData.Memo } else { "" }

    $normalizedPersons = New-Object System.Collections.ArrayList
    $modelNamesForScene = @()
    $costumesForScene   = @()
    $inPersons = New-Object System.Collections.ArrayList
    if ($null -ne $PersonsList) {
        if ($PersonsList -is [System.Collections.IDictionary]) {
            [void]$inPersons.Add($PersonsList)
        } elseif ($PersonsList -is [System.Collections.IEnumerable] -and -not ($PersonsList -is [string])) {
            foreach ($item in $PersonsList) {
                if ($null -eq $item) { continue }
                if (($item -is [System.Collections.IEnumerable]) -and -not ($item -is [System.Collections.IDictionary]) -and -not ($item -is [string])) {
                    foreach ($subItem in $item) {
                        if ($null -ne $subItem) { [void]$inPersons.Add($subItem) }
                    }
                } else {
                    [void]$inPersons.Add($item)
                }
            }
        } else {
            [void]$inPersons.Add($PersonsList)
        }
    }

    for ($i = 0; $i -lt $inPersons.Count; $i++) {
        $p = $inPersons[$i]
        if ($null -eq $p) { continue }
        $pNameRaw = if ($p -is [System.Collections.IDictionary]) { [string]$p["Name"] } else { [string]$p.Name }
        $pCosRaw  = if ($p -is [System.Collections.IDictionary]) { [string]$p["CostumeOrChar"] } else { [string]$p.CostumeOrChar }
        $pXRaw    = if ($p -is [System.Collections.IDictionary]) { [string]$p["XAccount"] } else { [string]$p.XAccount }
        $pComRaw  = if ($p -is [System.Collections.IDictionary]) { [string]$p["Comment"] } else { [string]$p.Comment }
        $pName = ConvertTo-CleanModelName $pNameRaw
        $pCos  = if ($null -eq $pCosRaw) { "" } else { $pCosRaw.Trim() }
        $pX    = ConvertTo-NormalizedX $pXRaw
        $pCom  = if ($null -eq $pComRaw) { "" } else { $pComRaw.Trim() }

        if (-not [string]::IsNullOrWhiteSpace($pName)) { $modelNamesForScene += $pName }
        if (-not [string]::IsNullOrWhiteSpace($pCos))  { $costumesForScene += $pCos }

        [void]$normalizedPersons.Add(@{
            Name          = $pName
            CostumeOrChar = $pCos
            XAccount      = $pX
            Comment       = $pCom
        })

        if (-not [string]::IsNullOrWhiteSpace($pX) -or -not [string]::IsNullOrWhiteSpace($pName)) {
            if (Get-Command Save-XHistory -ErrorAction SilentlyContinue) {
                Save-XHistory -Account $pX -Name $pName -Config $EffectiveConfig -DateStr $dateVal
            }
        }
    }

    $savePayload = @{
        Category       = $catVal
        DateStr        = $dateVal
        ShootDate      = $dateVal
        EventName      = $eventVal
        MegaLink       = $megaVal
        GigaFileLink   = $gigaVal
        ShareUrl       = $gigaVal
        DlPassword     = $dlPwVal
        GigaFileExpiry = $expVal
        SentStatus     = $sentVal
        Notes          = $memoVal
        Persons        = ([object[]]$normalizedPersons.ToArray())
    }

    $savedDirs = New-Object System.Collections.Generic.List[string]
    foreach ($dir in @($PairedObj.Target, $PairedObj.ImportFolder, $PairedObj.DevFolder)) {
        if (-not [string]::IsNullOrWhiteSpace($dir) -and (Test-Path -LiteralPath $dir)) {
            $normDir = $dir.TrimEnd('\')
            if (-not $savedDirs.Contains($normDir)) {
                $savedDirs.Add($normDir)
                [void](Write-PhotoInfoTxt -FolderPath $normDir -Info $savePayload)
            }
        }
    }

    if (Get-Command Update-SceneHistoryData -ErrorAction SilentlyContinue) {
        $sceneHistPath = [string]$EffectiveConfig.SceneHistoryPath
        for ($i = 0; $i -lt $normalizedPersons.Count; $i++) {
            $np = $normalizedPersons[$i]
            $models = if ([string]::IsNullOrWhiteSpace($np.Name)) { @() } else { @($np.Name) }
            Update-SceneHistoryData -HistoryPath $sceneHistPath -Category $catVal -SceneName $eventVal -CostumeName $np.CostumeOrChar -ModelNames $models -DateStr $dateVal -Config $EffectiveConfig
        }
    }

    $multiFlagText = if ($null -ne $RelatedFolders -and @($RelatedFolders).Count -gt 1) { "複数あり ($(@($RelatedFolders).Count)件)" } else { "" }

    if (Get-Command Update-PhotoExcelLedger -ErrorAction SilentlyContinue) {
        $records = New-Object System.Collections.Generic.List[hashtable]
        for ($i = 0; $i -lt $normalizedPersons.Count; $i++) {
            $p = $normalizedPersons[$i]
            $xUrl = if ([string]::IsNullOrWhiteSpace($p.XAccount)) { "" } else { "https://x.com/" + $p.XAccount.TrimStart('@') }
            $rowComment = $p.Comment
            if ($i -eq 0 -and -not [string]::IsNullOrWhiteSpace($memoVal)) {
                $rowComment = if ([string]::IsNullOrWhiteSpace($rowComment)) { $memoVal } else { "$rowComment`r`n$memoVal" }
            }

            $records.Add(@{
                Category        = $catVal
                DateStr         = $dateVal
                EventName       = $eventVal
                CostumeOrChar   = $p.CostumeOrChar
                Name            = $p.Name
                XAccount        = $p.XAccount
                XUrl            = $xUrl
                Comment         = $rowComment
                SentStatus      = $sentVal
                MegaLink        = $megaVal
                GigaFileLink    = $gigaVal
                MultiFolder     = $multiFlagText
                MultiFolderFlag = $multiFlagText
                RelPath         = $PairedObj.RelPath
                ImportRoot      = $EffectiveConfig.ImportRoot1
                ImportFolder    = $PairedObj.ImportFolder
                DevRoot         = $EffectiveConfig.DevRoot
                DevFolder       = $PairedObj.DevFolder
                FolderName      = $PairedObj.FolderName
                PersonIndex     = ($i + 1)
            })
        }
        Update-PhotoExcelLedger -Records ([object[]]$records.ToArray()) -Config $EffectiveConfig
    }

    return @{
        Success   = $true
        SavedDirs = @($savedDirs)
        Message   = "保存およびExcel台帳の更新が完了しました。"
    }
}
