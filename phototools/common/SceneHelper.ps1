#requires -Version 5.1
# ==============================================================================
# SceneHelper.ps1 - Scene / Costume History and Same Model Search (100% ASCII source, Unicode [char])
# ==============================================================================

function Get-Tag {
    param([int[]]$Codes)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $Codes) { [void]$sb.Append([char]$c) }
    return $sb.ToString()
}

function Get-ScenePropStr {
    param(
        [object]$Obj,
        [string[]]$Names,
        [string]$DefaultVal = ""
    )
    if ($null -eq $Obj) { return $DefaultVal }
    if ($Obj -is [System.Collections.IDictionary]) {
        foreach ($n in $Names) {
            if ($Obj.Contains($n) -and $null -ne $Obj[$n]) {
                return ([string]$Obj[$n]).Trim()
            }
        }
        return $DefaultVal
    }
    foreach ($n in $Names) {
        $prop = $Obj.PSObject.Properties[$n]
        if ($null -ne $prop -and $null -ne $prop.Value) {
            return ([string]$prop.Value).Trim()
        }
    }
    return $DefaultVal
}

function Get-SceneHistoryPath {
    param([hashtable]$Config = @{})
    if ($null -ne $Config) {
        if ($Config.ContainsKey("SceneHistoryPath") -and -not [string]::IsNullOrWhiteSpace([string]$Config["SceneHistoryPath"])) {
            return [string]$Config["SceneHistoryPath"]
        }
        if ($Config.ContainsKey("DataDir") -and -not [string]::IsNullOrWhiteSpace([string]$Config["DataDir"])) {
            return (Join-Path ([string]$Config["DataDir"]) "scene_history.json")
        }
        if ($Config.ContainsKey("RootDir") -and -not [string]::IsNullOrWhiteSpace([string]$Config["RootDir"])) {
            return (Join-Path ([string]$Config["RootDir"]) "data\scene_history.json")
        }
    }
    $root = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $PSScriptRoot } else { "D:\PhotoTools" }
    return (Join-Path $root "data\scene_history.json")
}

function Read-SceneHistory {
    param(
        [hashtable]$Config = @{},
        [string]$HistoryPath = ""
    )
    $path = if (-not [string]::IsNullOrWhiteSpace($HistoryPath)) { $HistoryPath } else { Get-SceneHistoryPath -Config $Config }
    if (-not (Test-Path -LiteralPath $path)) {
        return @()
    }
    try {
        $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $parsed = $raw | ConvertFrom-Json
        if ($null -eq $parsed) { return @() }
        $arr = @($parsed)
        return $arr
    } catch {
        return @()
    }
}

function Save-SceneHistoryEntry {
    param(
        [string]$Category = "Event",
        [string]$SceneName = "",
        [string]$ModelName = "",
        [string]$CostumeOrChar = "",
        [string]$DateStr = "",
        [hashtable]$Config = @{},
        [string]$HistoryPath = ""
    )
    if ([string]::IsNullOrWhiteSpace($SceneName) -and [string]::IsNullOrWhiteSpace($CostumeOrChar) -and [string]::IsNullOrWhiteSpace($ModelName)) {
        return
    }
    $path = if (-not [string]::IsNullOrWhiteSpace($HistoryPath)) { $HistoryPath } else { Get-SceneHistoryPath -Config $Config }
    $dir = Split-Path -Parent $path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $list = New-Object System.Collections.ArrayList
    foreach ($item in @(Read-SceneHistory -Config $Config -HistoryPath $path)) {
        if ($null -ne $item) { [void]$list.Add($item) }
    }

    $catNorm = if ([string]::IsNullOrWhiteSpace($Category)) { "Event" } else { $Category.Trim() }
    $scnNorm = if ($null -eq $SceneName) { "" } else { $SceneName.Trim() }
    $modNorm = if ($null -eq $ModelName) { "" } else { $ModelName.Trim() }
    $cosNorm = if ($null -eq $CostumeOrChar) { "" } else { $CostumeOrChar.Trim() }
    $dtNorm  = if ($null -eq $DateStr) { "" } else { $DateStr.Trim() }
    $nowStr  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    $matchedIdx = -1
    for ($i = 0; $i -lt $list.Count; $i++) {
        $it = $list[$i]
        $c1 = Get-ScenePropStr -Obj $it -Names @("Category", "category")
        $s1 = Get-ScenePropStr -Obj $it -Names @("SceneName")
        $m1 = Get-ScenePropStr -Obj $it -Names @("ModelName")
        $o1 = Get-ScenePropStr -Obj $it -Names @("CostumeOrChar", "value")
        if ($c1 -eq $catNorm -and $s1 -eq $scnNorm -and $m1 -eq $modNorm -and $o1 -eq $cosNorm) {
            $matchedIdx = $i
            break
        }
    }

    if ($matchedIdx -ge 0) {
        $old = $list[$matchedIdx]
        $oldCntStr = Get-ScenePropStr -Obj $old -Names @("Count", "count") -DefaultVal "1"
        $oldCnt = 1
        [void][int]::TryParse($oldCntStr, [ref]$oldCnt)
        if ($oldCnt -lt 1) { $oldCnt = 1 }
        $oldDate = Get-ScenePropStr -Obj $old -Names @("LastDate", "lastDate")

        $list.RemoveAt($matchedIdx)
        $entry = [PSCustomObject]@{
            Category      = $catNorm
            SceneName     = $scnNorm
            ModelName     = $modNorm
            CostumeOrChar = $cosNorm
            Count         = ($oldCnt + 1)
            LastDate      = if (-not [string]::IsNullOrWhiteSpace($dtNorm)) { $dtNorm } else { $oldDate }
            UpdatedAt     = $nowStr
        }
        $list.Insert(0, $entry)
    } else {
        $entry = [PSCustomObject]@{
            Category      = $catNorm
            SceneName     = $scnNorm
            ModelName     = $modNorm
            CostumeOrChar = $cosNorm
            Count         = 1
            LastDate      = $dtNorm
            UpdatedAt     = $nowStr
        }
        $list.Insert(0, $entry)
    }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $outArr = [object[]]$list.ToArray()
    $json = ConvertTo-Json -InputObject $outArr -Depth 5
    [System.IO.File]::WriteAllText($path, $json, $utf8Bom)
}

function Get-SceneCandidates {
    param(
        [string]$Category = "",
        [hashtable]$Config = @{},
        [string]$HistoryPath = ""
    )
    $all = @(Read-SceneHistory -Config $Config -HistoryPath $HistoryPath)
    $scenes   = New-Object System.Collections.ArrayList
    $costumes = New-Object System.Collections.ArrayList
    $models   = New-Object System.Collections.ArrayList

    foreach ($it in $all) {
        if ($null -eq $it) { continue }
        $c1 = Get-ScenePropStr -Obj $it -Names @("Category", "category")
        if (-not [string]::IsNullOrWhiteSpace($Category) -and -not [string]::IsNullOrWhiteSpace($c1) -and $c1 -ne $Category) {
            continue
        }
        $s1 = Get-ScenePropStr -Obj $it -Names @("SceneName")
        $o1 = Get-ScenePropStr -Obj $it -Names @("CostumeOrChar", "value")
        $m1 = Get-ScenePropStr -Obj $it -Names @("ModelName")

        if (-not [string]::IsNullOrWhiteSpace($s1) -and ($scenes -notcontains $s1))   { [void]$scenes.Add($s1) }
        if (-not [string]::IsNullOrWhiteSpace($o1) -and ($costumes -notcontains $o1)) { [void]$costumes.Add($o1) }
        if (-not [string]::IsNullOrWhiteSpace($m1) -and ($models -notcontains $m1))   { [void]$models.Add($m1) }
    }

    return @{
        Scenes   = [string[]]$scenes.ToArray()
        Costumes = [string[]]$costumes.ToArray()
        Models   = [string[]]$models.ToArray()
    }
}

function Get-SceneHistoryData {
    param(
        [string]$HistoryPath = "",
        [string]$Category = "",
        [hashtable]$Config = @{}
    )
    return Get-SceneCandidates -Category $Category -Config $Config -HistoryPath $HistoryPath
}

function Update-SceneHistoryData {
    param(
        [string]$HistoryPath = "",
        [string]$Category = "Event",
        [string]$SceneName = "",
        [string]$CostumeName = "",
        [string[]]$ModelNames = @(),
        [string]$DateStr = "",
        [hashtable]$Config = @{}
    )
    $validModels = @()
    if ($null -ne $ModelNames) {
        foreach ($mn in @($ModelNames)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$mn)) {
                $validModels += ([string]$mn).Trim()
            }
        }
    }
    if (@($validModels).Count -eq 0) {
        Save-SceneHistoryEntry -Category $Category -SceneName $SceneName -ModelName "" -CostumeOrChar $CostumeName -DateStr $DateStr -Config $Config -HistoryPath $HistoryPath
        return
    }
    foreach ($m in $validModels) {
        Save-SceneHistoryEntry -Category $Category -SceneName $SceneName -ModelName $m -CostumeOrChar $CostumeName -DateStr $DateStr -Config $Config -HistoryPath $HistoryPath
    }
}

function Update-SceneHistoryFromInfo {
    param(
        [string]$RootDir = "",
        [Parameter(Mandatory=$true)]$Info,
        [hashtable]$Config = @{}
    )
    $histPath = if (-not [string]::IsNullOrWhiteSpace($RootDir)) { Join-Path $RootDir "data\scene_history.json" } else { "" }
    if ($null -ne $Config -and $Config.ContainsKey("SceneHistoryPath") -and -not [string]::IsNullOrWhiteSpace([string]$Config["SceneHistoryPath"])) {
        $histPath = [string]$Config["SceneHistoryPath"]
    }
    $cat = Get-ScenePropStr -Obj $Info -Names @("Category") -DefaultVal "Event"
    $scn = Get-ScenePropStr -Obj $Info -Names @("EventName")
    $dt  = Get-ScenePropStr -Obj $Info -Names @("ShootDate", "DateStr")

    $persons = @()
    if ($null -ne $Info.Persons -and @($Info.Persons).Count -gt 0) {
        $persons = @($Info.Persons)
    } elseif ($null -ne $Info.Models -and @($Info.Models).Count -gt 0) {
        foreach ($m in @($Info.Models)) {
            $persons += @{ Name = [string]$m.Name; CostumeOrChar = [string]$m.CharName }
        }
    }

    if (@($persons).Count -eq 0) {
        $defCos = Get-ScenePropStr -Obj $Info -Names @("CostumeOrChar")
        if (-not [string]::IsNullOrWhiteSpace($scn) -or -not [string]::IsNullOrWhiteSpace($defCos)) {
            Save-SceneHistoryEntry -Category $cat -SceneName $scn -CostumeOrChar $defCos -DateStr $dt -Config $Config -HistoryPath $histPath
        }
        return
    }

    foreach ($p in $persons) {
        $pName = Get-ScenePropStr -Obj $p -Names @("Name")
        $pCos  = Get-ScenePropStr -Obj $p -Names @("CostumeOrChar")
        Save-SceneHistoryEntry -Category $cat -SceneName $scn -ModelName $pName -CostumeOrChar $pCos -DateStr $dt -Config $Config -HistoryPath $histPath
    }
}

function Get-ScenePatternCandidateDirs {
    param([string]$FolderPath)
    $out = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($FolderPath)) { return @() }

    $norm = $FolderPath.Trim().TrimEnd('\')
    if (Test-Path -LiteralPath $norm -PathType Leaf) {
        $norm = [System.IO.Path]::GetDirectoryName($norm)
    }
    if ([string]::IsNullOrWhiteSpace($norm)) { return @() }

    $dateRegex = '^\d{4}(?:[-_.]\d{2}[-_.]\d{2}|\d{4})(?:$|[_\-\s].*)'
    $chain = New-Object System.Collections.Generic.List[string]
    $curr = $norm
    $dateIdx = -1
    for ($i = 0; $i -lt 10; $i++) {
        if ([string]::IsNullOrWhiteSpace($curr)) { break }
        [void]$chain.Add($curr)
        $leaf = [System.IO.Path]::GetFileName($curr)
        if ($leaf -match $dateRegex) {
            $dateIdx = $chain.Count - 1
            break
        }
        $curr = [System.IO.Path]::GetDirectoryName($curr)
    }

    if ($dateIdx -ge 0) {
        if ($dateIdx -ge 1) {
            [void]$out.Add($chain[$dateIdx - 1])
        }
        [void]$out.Add($chain[$dateIdx])
    } else {
        [void]$out.Add($norm)
        $parent = [System.IO.Path]::GetDirectoryName($norm)
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            [void]$out.Add($parent)
        }
    }
    return @($out)
}

function Read-SceneFileRaw {
    param([string]$DirPath)
    if ([string]::IsNullOrWhiteSpace($DirPath) -or -not (Test-Path -LiteralPath $DirPath)) { return $null }
    $sceneFile = Join-Path $DirPath "scene.txt"
    $eventFile = Join-Path $DirPath "event.txt"
    if ((Test-Path -LiteralPath $eventFile) -and (-not (Test-Path -LiteralPath $sceneFile))) {
        try {
            Rename-Item -LiteralPath $eventFile -NewName "scene.txt" -Force -ErrorAction Stop
        } catch {
            Copy-Item -LiteralPath $eventFile -Destination $sceneFile -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not (Test-Path -LiteralPath $sceneFile)) { return $null }
    $raw = try { [System.IO.File]::ReadAllText($sceneFile, [System.Text.Encoding]::UTF8) } catch { "" }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    $res = @{
        Category      = ""
        SceneName     = ""
        CostumeOrChar = ""
        SourceFile    = $sceneFile
    }
    $lines = $raw -split "`r?`n"
    $hasTag = $false

    $tCat  = Get-Tag @(0x3010, 0x64EE, 0x5F71, 0x533A, 0x5206, 0x3011)
    $tEv1  = Get-Tag @(0x3010, 0x50AC, 0x4E8B, 0x540D, 0x3011)
    $tEv2  = Get-Tag @(0x3010, 0x30A4, 0x30D9, 0x30F3, 0x30C8, 0x540D, 0x3011)
    $tEv3  = Get-Tag @(0x3010, 0x30B9, 0x30BF, 0x30B8, 0x30AA, 0x540D, 0x3011)
    $tEv4  = Get-Tag @(0x3010, 0x5834, 0x6245, 0x3011)
    $tCos1 = Get-Tag @(0x3010, 0x8863, 0x88C5, 0x30FB, 0x30AD, 0x30E3, 0x30E9, 0x30BF, 0x30FC, 0x3011)
    $tCos2 = Get-Tag @(0x3010, 0x8863, 0x88C5, 0x3011)
    $bClose = [string][char]0x3011

    foreach ($ln in $lines) {
        $trimLn = $ln.Trim()
        if ($trimLn.StartsWith($tCat)) { $res.Category = $trimLn.Substring($tCat.Length).Trim(); $hasTag = $true }
        elseif ($trimLn.StartsWith($tEv1) -or $trimLn.StartsWith($tEv2) -or $trimLn.StartsWith($tEv3) -or $trimLn.StartsWith($tEv4)) {
            $colonIdx = $trimLn.IndexOf($bClose)
            if ($colonIdx -ge 0) { $res.SceneName = $trimLn.Substring($colonIdx + 1).Trim(); $hasTag = $true }
        }
        elseif ($trimLn.StartsWith($tCos1) -or $trimLn.StartsWith($tCos2)) {
            $colonIdx = $trimLn.IndexOf($bClose)
            if ($colonIdx -ge 0) { $res.CostumeOrChar = $trimLn.Substring($colonIdx + 1).Trim(); $hasTag = $true }
        }
    }
    if (-not $hasTag -and $lines.Count -gt 0) {
        $res.SceneName = ($lines[0]).Trim()
    }
    return $res
}

function Find-SceneInfo {
    param([string[]]$SearchDirs)
    $res = @{
        Category      = ""
        SceneName     = ""
        CostumeOrChar = ""
        SourceFile    = ""
    }

    $patternBCands = New-Object System.Collections.Generic.List[string]
    $patternACands = New-Object System.Collections.Generic.List[string]
    foreach ($baseDir in @($SearchDirs)) {
        if ([string]::IsNullOrWhiteSpace($baseDir)) { continue }
        $cands = @(Get-ScenePatternCandidateDirs -FolderPath $baseDir)
        if (@($cands).Count -ge 2) {
            if (-not $patternBCands.Contains($cands[0])) { [void]$patternBCands.Add($cands[0]) }
            if (-not $patternACands.Contains($cands[1])) { [void]$patternACands.Add($cands[1]) }
        } elseif (@($cands).Count -eq 1) {
            if (-not $patternACands.Contains($cands[0])) { [void]$patternACands.Add($cands[0]) }
        }
    }

    foreach ($candDir in @($patternBCands) + @($patternACands)) {
        $parsed = Read-SceneFileRaw -DirPath $candDir
        if ($null -ne $parsed -and (-not [string]::IsNullOrWhiteSpace($parsed.SceneName) -or -not [string]::IsNullOrWhiteSpace($parsed.CostumeOrChar))) {
            return $parsed
        }
    }
    return $res
}

function Resolve-SceneInfoFromHierarchy {
    param(
        [string]$StartDir = "",
        [hashtable]$PairedObj = $null
    )
    $dirs = @()
    if (-not [string]::IsNullOrWhiteSpace($StartDir)) { $dirs += $StartDir }
    if ($null -ne $PairedObj) {
        foreach ($d in @($PairedObj.Target, $PairedObj.ImportFolder, $PairedObj.DevFolder)) {
            if (-not [string]::IsNullOrWhiteSpace($d) -and ($dirs -notcontains $d)) {
                $dirs += $d
            }
        }
    }
    return Find-SceneInfo -SearchDirs $dirs
}

function Save-SceneFile {
    param(
        [string]$TargetDir,
        [string]$Category = "Event",
        [string]$SceneName = "",
        [string]$CostumeOrChar = ""
    )
    if ([string]::IsNullOrWhiteSpace($TargetDir) -or -not (Test-Path -LiteralPath $TargetDir)) { return }
    if ([string]::IsNullOrWhiteSpace($SceneName) -and [string]::IsNullOrWhiteSpace($CostumeOrChar)) { return }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $sceneFile = Join-Path $TargetDir "scene.txt"
    $tCat = Get-Tag @(0x3010, 0x64EE, 0x5F71, 0x533A, 0x5206, 0x3011)
    $tScn = Get-Tag @(0x3010, 0x50AC, 0x4E8B, 0x30FB, 0x5834, 0x6245, 0x540D, 0x3011)
    $tCos = Get-Tag @(0x3010, 0x8863, 0x88C5, 0x30FB, 0x30AD, 0x30E3, 0x30E9, 0x30BF, 0x30FC, 0x3011)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("$tCat$Category")
    [void]$sb.AppendLine("$tScn$SceneName")
    if (-not [string]::IsNullOrWhiteSpace($CostumeOrChar)) {
        [void]$sb.AppendLine("$tCos$CostumeOrChar")
    }
    [System.IO.File]::WriteAllText($sceneFile, $sb.ToString(), $utf8Bom)
}

function Extract-CostumeFromLegacyComment {
    param([string]$CommentText)
    if ([string]::IsNullOrWhiteSpace($CommentText)) { return "" }
    return ""
}

function Find-SameModelFoldersOnDate {
    param(
        [string]$CurrentFolder,
        [string]$DateStr = "",
        [string]$ModelName = "",
        [string[]]$ModelNames = @(),
        [string[]]$AdditionalRoots = @()
    )
    $matchesArr = New-Object System.Collections.ArrayList
    $targetModels = @()
    if (-not [string]::IsNullOrWhiteSpace($ModelName)) {
        $targetModels += $ModelName.Trim()
    }
    if ($null -ne $ModelNames) {
        foreach ($mn in @($ModelNames)) {
            $mnt = if ($null -eq $mn) { "" } else { ([string]$mn).Trim() }
            if (-not [string]::IsNullOrWhiteSpace($mnt) -and ($targetModels -notcontains $mnt)) {
                $targetModels += $mnt
            }
        }
    }
    if (@($targetModels).Count -eq 0 -or [string]::IsNullOrWhiteSpace($CurrentFolder)) {
        return @()
    }

    $dateRoots = @()
    $candidateBases = @($CurrentFolder)
    if ($null -ne $AdditionalRoots) {
        foreach ($ar in @($AdditionalRoots)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$ar)) {
                $candidateBases += [string]$ar
            }
        }
    }

    foreach ($base in $candidateBases) {
        if ([string]::IsNullOrWhiteSpace($base) -or -not (Test-Path -LiteralPath $base)) { continue }
        $curr = $base
        $foundDateRoot = ""
        for ($i = 0; $i -lt 5; $i++) {
            if ([string]::IsNullOrWhiteSpace($curr)) { break }
            $leaf = [System.IO.Path]::GetFileName($curr)
            if ((-not [string]::IsNullOrWhiteSpace($DateStr) -and $leaf -eq $DateStr) -or ($leaf -match '^\d{4}[_-]\d{2}[_-]\d{2}')) {
                $foundDateRoot = $curr
                break
            }
            $curr = [System.IO.Path]::GetDirectoryName($curr)
        }
        if (-not [string]::IsNullOrWhiteSpace($foundDateRoot) -and (Test-Path -LiteralPath $foundDateRoot) -and ($dateRoots -notcontains $foundDateRoot)) {
            $dateRoots += $foundDateRoot
        }
    }

    if (@($dateRoots).Count -eq 0) {
        return @()
    }

    $tName1 = Get-Tag @(0x3010, 0x540D, 0x524D, 0x3011)
    $tName2 = Get-Tag @(0x3010, 0x30E2, 0x30C7, 0x30EB, 0x540D, 0x3011)
    $tCos1  = Get-Tag @(0x3010, 0x8863, 0x88C5, 0x30FB, 0x30AD, 0x30E3, 0x30E9, 0x3011)
    $tCos2  = Get-Tag @(0x3010, 0x8863, 0x88C5, 0x3011)
    $tCos3  = Get-Tag @(0x3010, 0x30ad, 0x30e3, 0x30e9, 0x30bf, 0x30fc, 0x540d, 0x3011)
    $tEv1   = Get-Tag @(0x3010, 0x30A4, 0x30D9, 0x30F3, 0x30C8, 0x540D, 0x3011)
    $tEv2   = Get-Tag @(0x3010, 0x50AC, 0x4E8B, 0x540D, 0x3011)
    $tEv3   = Get-Tag @(0x3010, 0x5834, 0x6245, 0x3011)
    $bClose = [string][char]0x3011

    $normCurrent = ($CurrentFolder -replace '\\+$', '')
    $seenFolders = @{}
    foreach ($dateRoot in $dateRoots) {
        $paths = try { @([System.IO.Directory]::GetFiles($dateRoot, "写真情報.txt", [System.IO.SearchOption]::AllDirectories)) } catch { @() }
        foreach ($p in $paths) {
            if ([string]::IsNullOrWhiteSpace($p)) { continue }
            $fi = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
            if ($null -eq $fi) { continue }
            $dir = ($fi.DirectoryName -replace '\\+$', '')
            if ($seenFolders.ContainsKey($dir)) { continue }

            $raw = try { [System.IO.File]::ReadAllText($fi.FullName, [System.Text.Encoding]::UTF8) } catch { "" }
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }

            $personBlocks = @()
            $curName = ""
            $curCostume = ""
            $scene = ""
            foreach ($ln in ($raw -split "`r?`n")) {
                $trimLn = $ln.Trim()
                if ($trimLn -match '^-{5,}$') {
                    if (-not [string]::IsNullOrWhiteSpace($curName)) {
                        $personBlocks += @{ Name = $curName; Costume = $curCostume }
                    }
                    $curName = ""
                    $curCostume = ""
                }
                elseif ($trimLn.StartsWith($tName1) -or $trimLn.StartsWith($tName2)) {
                    if (-not [string]::IsNullOrWhiteSpace($curName)) {
                        $personBlocks += @{ Name = $curName; Costume = $curCostume }
                        $curCostume = ""
                    }
                    $colonIdx = $trimLn.IndexOf($bClose)
                    if ($colonIdx -ge 0) { $curName = $trimLn.Substring($colonIdx + 1).Trim() }
                }
                elseif ($trimLn.StartsWith($tCos1) -or $trimLn.StartsWith($tCos2) -or $trimLn.StartsWith($tCos3)) {
                    $colonIdx = $trimLn.IndexOf($bClose)
                    if ($colonIdx -ge 0) { $curCostume = $trimLn.Substring($colonIdx + 1).Trim() }
                }
                elseif ($trimLn.StartsWith($tEv1) -or $trimLn.StartsWith($tEv2) -or $trimLn.StartsWith($tEv3)) {
                    $colonIdx = $trimLn.IndexOf($bClose)
                    if ($colonIdx -ge 0) { $scene = $trimLn.Substring($colonIdx + 1).Trim() }
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($curName)) {
                $personBlocks += @{ Name = $curName; Costume = $curCostume }
            }

            $hitModel = ""
            $hitCostume = ""
            foreach ($pb in $personBlocks) {
                $pbName = [string]$pb["Name"]
                foreach ($vm in $targetModels) {
                    if ($pbName -ieq $vm) {
                        $hitModel = $pbName
                        $hitCostume = [string]$pb["Costume"]
                        break
                    }
                }
                if (-not [string]::IsNullOrWhiteSpace($hitModel)) { break }
            }

            if (-not [string]::IsNullOrWhiteSpace($hitModel)) {
                $seenFolders[$dir] = $true
                $rel = ($dir.Substring($dateRoot.Length) -replace '^\\+', '')
                if ([string]::IsNullOrWhiteSpace($rel)) { $rel = [System.IO.Path]::GetFileName($dir) }
                [void]$matchesArr.Add(@{
                    FolderPath    = $dir
                    RelativeLabel = $rel
                    ModelName     = $hitModel
                    SceneName     = $scene
                    CostumeOrChar = $hitCostume
                    IsCurrent     = ($dir -ieq $normCurrent)
                })
            }
        }
    }
    return ([object[]]$matchesArr.ToArray())
}
