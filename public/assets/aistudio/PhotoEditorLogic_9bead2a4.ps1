#requires -Version 5.1

function Initialize-PhotoEditorEnvironment {
    param(
        [string]$ScriptDir,
        [hashtable]$ExternalConfig = @{}
    )

    if ([string]::IsNullOrWhiteSpace($ScriptDir)) {
        $ScriptDir = "D:\PhotoTools\editor"
    }
    $rootDir = Split-Path -Parent $ScriptDir
    if (-not (Test-Path -LiteralPath (Join-Path $rootDir "settings.ini"))) {
        if (Test-Path -LiteralPath "D:\PhotoTools\settings.ini") {
            $rootDir = "D:\PhotoTools"
        } else {
            $rootDir = $ScriptDir
        }
    }

    $cfg = @{}
    if ($null -ne $ExternalConfig) {
        foreach ($k in $ExternalConfig.Keys) {
            $cfg[$k] = $ExternalConfig[$k]
        }
    }

    if ($cfg.Count -eq 0) {
        $iniPath = Join-Path $rootDir "settings.ini"
        if (Test-Path -LiteralPath $iniPath) {
            $lines = Get-Content -LiteralPath $iniPath -Encoding UTF8
            foreach ($line in $lines) {
                $t = $line.Trim()
                if ([string]::IsNullOrWhiteSpace($t) -or $t.StartsWith("#") -or $t.StartsWith(";") -or ($t.StartsWith("[") -and $t.EndsWith("]"))) { continue }
                $idx = $t.IndexOf("=")
                if ($idx -gt 0) {
                    $k = $t.Substring(0, $idx).Trim()
                    $v = $t.Substring($idx + 1).Trim()
                    $cfg[$k] = $v
                }
            }
        }
    }

    $getVal = {
        param([string]$Key, [string]$Def)
        if ($cfg.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace([string]$cfg[$Key])) {
            return [string]$cfg[$Key]
        }
        return $Def
    }

    $eff = @{
        RootDir          = $rootDir
        ImportRoot1      = (& $getVal "ImportRoot1" "H:\写真作業用\eos").TrimEnd('\')
        ImportRoot2      = (& $getVal "ImportRoot2" "I:\写真\eos").TrimEnd('\')
        WorkRawRoot      = (& $getVal "WorkRawRoot" "H:\写真作業用\作業用RAW").TrimEnd('\')
        DevRoot          = (& $getVal "DevRoot" "G:\写真\現像後").TrimEnd('\')
        ExcelPath        = & $getVal "ExcelPath" "G:\写真\現像後\写真管理一覧.xlsx"
        XHistoryPath     = & $getVal "XHistoryPath" (& $getVal "HistoryPath" (Join-Path $rootDir "x_history.json"))
        HistoryPath      = & $getVal "XHistoryPath" (& $getVal "HistoryPath" (Join-Path $rootDir "x_history.json"))
        SceneHistoryPath = & $getVal "SceneHistoryPath" (Join-Path $rootDir "scene_history.json")
        MegaCmdPath      = & $getVal "MegaCmdPath" (Join-Path $env:LOCALAPPDATA "MEGAcmd\mega-export.bat")
        MegaRemoteRoot   = & $getVal "MegaRemoteRoot" "/写真1/現像後"
        MegaLogPath      = & $getVal "MegaLogPath" (Join-Path $rootDir "mega_debug.log")
        GigaScriptPath   = & $getVal "GigaScriptPath" (Join-Path $rootDir "gigafile\send_to_gigafile.ps1")
    }

    $commonDir = Join-Path $rootDir "common"
    foreach ($helper in @("MegaHelper.ps1", "XHelper.ps1", "ExcelHelper.ps1", "SceneHelper.ps1", "GigaFileHelper.ps1")) {
        $hp1 = Join-Path $commonDir $helper
        $hp2 = Join-Path $rootDir $helper
        if (Test-Path -LiteralPath $hp1) {
            . $hp1
        } elseif (Test-Path -LiteralPath $hp2) {
            . $hp2
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
    $s = $Raw.Trim()
    $s = $s -replace '^[（\(\s]+', ''
    $s = $s -replace '[）\)\s]+$', ''
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
    if ($idxHalf -ge 0 -and $idxFull -ge 0) {
        $cut = [Math]::Min($idxHalf, $idxFull)
    } elseif ($idxHalf -ge 0) {
        $cut = $idxHalf
    } elseif ($idxFull -ge 0) {
        $cut = $idxFull
    }
    if ($cut -gt 0) {
        $n = $n.Substring(0, $cut).Trim()
    }
    return $n
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
        DevFolder    = ""
        DateStr      = ""
        FolderName   = [System.IO.Path]::GetFileName($Folder)
    }
    if ([string]::IsNullOrWhiteSpace($Folder)) { return $res }

    $roots = @(
        @{ Path = $EffectiveConfig.ImportRoot1; Type = "Import" },
        @{ Path = $EffectiveConfig.ImportRoot2; Type = "Import" },
        @{ Path = $EffectiveConfig.WorkRawRoot; Type = "WorkRaw" },
        @{ Path = $EffectiveConfig.DevRoot;     Type = "Dev" }
    )

    foreach ($r in $roots) {
        $rp = $r.Path
        if (-not [string]::IsNullOrWhiteSpace($rp) -and $Folder.StartsWith($rp, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = $Folder.Substring($rp.Length).TrimStart('\')
            $res.RelPath = $rel
            if (-not [string]::IsNullOrWhiteSpace($rel)) {
                $parts = $rel -split '\\'
                if ($parts.Count -ge 1 -and $parts[0] -match '\d{4}[_-]\d{2}[_-]\d{2}') {
                    $res.DateStr = $parts[0]
                }
                $c1 = Join-Path $EffectiveConfig.ImportRoot1 $rel
                $c2 = Join-Path $EffectiveConfig.ImportRoot2 $rel
                if (Test-Path -LiteralPath $c1) { $res.ImportFolder = $c1 }
                elseif (Test-Path -LiteralPath $c2) { $res.ImportFolder = $c2 }
                else { $res.ImportFolder = $c1 }

                $res.DevFolder = Join-Path $EffectiveConfig.DevRoot $rel
            }
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($res.DateStr)) {
        $curr = $Folder
        for ($i = 0; $i -lt 5; $i++) {
            if ([string]::IsNullOrWhiteSpace($curr)) { break }
            $fn = [System.IO.Path]::GetFileName($curr)
            if ($fn -match '\d{4}[_-]\d{2}[_-]\d{2}') {
                $res.DateStr = $fn
                break
            }
            $curr = [System.IO.Path]::GetDirectoryName($curr)
        }
    }

    if ([string]::IsNullOrWhiteSpace($res.ImportFolder) -and [string]::IsNullOrWhiteSpace($res.DevFolder)) {
        $res.DevFolder = $Folder
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
            if (Test-Path -LiteralPath $pOld) {
                if (-not (Test-Path -LiteralPath $pNew)) {
                    Rename-Item -LiteralPath $pOld -NewName "写真情報.txt" -Force -ErrorAction SilentlyContinue
                }
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
                if ($dest -ne $latest.FullName) {
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
        $sInfo = Resolve-SceneInfoFromHierarchy -StartDir $PairedObj.Target
        if ($null -ne $sInfo -and -not [string]::IsNullOrWhiteSpace([string]$sInfo.SceneName)) {
            return $sInfo
        }
    }
    foreach ($baseDir in @($PairedObj.Target, $PairedObj.ImportFolder, $PairedObj.DevFolder)) {
        $curr = $baseDir
        for ($i = 0; $i -lt 5; $i++) {
            if ([string]::IsNullOrWhiteSpace($curr)) { break }
            if (Test-Path -LiteralPath $curr) {
                $scFile = Join-Path $curr "scene.txt"
                $evFile = Join-Path $curr "event.txt"
                if ((Test-Path -LiteralPath $evFile) -and (-not (Test-Path -LiteralPath $scFile))) {
                    Rename-Item -LiteralPath $evFile -NewName "scene.txt" -Force -ErrorAction SilentlyContinue
                }
                if (Test-Path -LiteralPath $scFile) {
                    $lines = Get-Content -LiteralPath $scFile -Encoding UTF8
                    $cat = "イベント"
                    $sName = ""
                    foreach ($l in $lines) {
                        if ($l -match '^【撮影区分】(.*)$') { $cat = $Matches[1].Trim() }
                        elseif ($l -match '^【(?:催事・場所名|イベント名|スタジオ名|併せ名|場所)】(.*)$') { $sName = $Matches[1].Trim() }
                        elseif ([string]::IsNullOrWhiteSpace($sName) -and -not $l.StartsWith("【")) { $sName = $l.Trim() }
                    }
                    if (-not [string]::IsNullOrWhiteSpace($sName)) {
                        return @{ Category = $cat; SceneName = $sName }
                    }
                }
            }
            $curr = [System.IO.Path]::GetDirectoryName($curr)
        }
    }
    return @{ Category = "イベント"; SceneName = "" }
}

function Read-PhotoInfoData {
    param(
        [string]$FilePath,
        [hashtable]$PairedObj
    )
    $result = @{
        Category     = "イベント"
        DateStr      = $PairedObj.DateStr
        EventName    = ""
        MegaLink     = ""
        GigaFileLink = ""
        Persons      = New-Object System.Collections.Generic.List[hashtable]
    }
    if ([string]::IsNullOrWhiteSpace($FilePath) -or -not (Test-Path -LiteralPath $FilePath)) {
        $result.Persons.Add(@{ Name = ""; CostumeOrChar = ""; XAccount = ""; Comment = "" })
        return $result
    }

    $rawText = Get-Content -LiteralPath $FilePath -Encoding UTF8 -Raw
    if ([string]::IsNullOrWhiteSpace($rawText)) {
        $result.Persons.Add(@{ Name = ""; CostumeOrChar = ""; XAccount = ""; Comment = "" })
        return $result
    }

    $lines = $rawText -split "`r?`n"
    $curPerson = $null
    $inComment = $false
    $headerCostume = ""

    foreach ($line in $lines) {
        $trim = $line.Trim()
        if ($trim -match '^-{5,}$') {
            if ($null -ne $curPerson) {
                $curPerson.Comment = $curPerson.Comment.TrimEnd("`r", "`n")
                $result.Persons.Add($curPerson)
                $curPerson = $null
            }
            $inComment = $false
            continue
        }

        if ($line -match '^【撮影区分】(.*)$') {
            $inComment = $false
            $v = $Matches[1].Trim()
            if (-not [string]::IsNullOrWhiteSpace($v)) { $result.Category = $v }
        }
        elseif ($line -match '^【日付】(.*)$') {
            $inComment = $false
            $v = $Matches[1].Trim()
            if (-not [string]::IsNullOrWhiteSpace($v)) { $result.DateStr = $v }
        }
        elseif ($line -match '^【(?:イベント名|スタジオ名|併せ名|場所|催事・場所名)】(.*)$') {
            $inComment = $false
            $result.EventName = $Matches[1].Trim()
        }
        elseif ($line -match '^【(?:衣装・キャラ|衣装名ORキャラ名|衣装|キャラ名)】(.*)$') {
            $inComment = $false
            $cVal = $Matches[1].Trim()
            if ($null -ne $curPerson) {
                $curPerson.CostumeOrChar = $cVal
            } else {
                $headerCostume = $cVal
            }
        }
        elseif ($line -match '^【MEGAリンク】(.*)$') {
            $inComment = $false
            $result.MegaLink = $Matches[1].Trim()
        }
        elseif ($line -match '^【ギガファイル便リンク】(.*)$') {
            $inComment = $false
            $result.GigaFileLink = $Matches[1].Trim()
        }
        elseif ($line -match '^【(?:名前|モデル名)】(.*)$') {
            $inComment = $false
            if ($null -ne $curPerson) {
                $curPerson.Comment = $curPerson.Comment.TrimEnd("`r", "`n")
                $result.Persons.Add($curPerson)
            }
            $curPerson = @{
                Name          = ConvertTo-CleanModelName $Matches[1].Trim()
                CostumeOrChar = ""
                XAccount      = ""
                Comment       = ""
            }
        }
        elseif ($line -match '^【(?:X|Xアカウント|アカウント|アカウント名|Twitter)】(.*)$') {
            $inComment = $false
            if ($null -eq $curPerson) {
                $curPerson = @{ Name = ""; CostumeOrChar = ""; XAccount = ""; Comment = "" }
            }
            $curPerson.XAccount = ConvertTo-NormalizedX $Matches[1].Trim()
        }
        elseif ($line -match '^【(?:コメント|メモ|備考)】(.*)$') {
            if ($null -eq $curPerson) {
                $curPerson = @{ Name = ""; CostumeOrChar = ""; XAccount = ""; Comment = "" }
            }
            $curPerson.Comment = $Matches[1].Trim()
            $inComment = $true
        }
        elseif ($inComment -and $null -ne $curPerson) {
            if ([string]::IsNullOrEmpty($curPerson.Comment)) {
                $curPerson.Comment = $line
            } else {
                $curPerson.Comment += "`r`n" + $line
            }
        }
    }

    if ($null -ne $curPerson) {
        $curPerson.Comment = $curPerson.Comment.TrimEnd("`r", "`n")
        $result.Persons.Add($curPerson)
    }

    if ($result.Persons.Count -eq 0) {
        $result.Persons.Add(@{ Name = ""; CostumeOrChar = ""; XAccount = ""; Comment = "" })
    }

    if (-not [string]::IsNullOrWhiteSpace($headerCostume) -and [string]::IsNullOrWhiteSpace($result.Persons[0].CostumeOrChar)) {
        $result.Persons[0].CostumeOrChar = $headerCostume
    }

    for ($i = 0; $i -lt $result.Persons.Count; $i++) {
        $p = $result.Persons[$i]
        if ([string]::IsNullOrWhiteSpace([string]$p.CostumeOrChar) -and -not [string]::IsNullOrWhiteSpace([string]$p.Comment)) {
            $com = [string]$p.Comment
            if (Get-Command Extract-CostumeFromLegacyComment -ErrorAction SilentlyContinue) {
                $ext = Extract-CostumeFromLegacyComment -CommentText $com
                if (-not [string]::IsNullOrWhiteSpace($ext)) { $p.CostumeOrChar = $ext }
            } elseif ($com -match '(?:キャラ|衣装)[：:\s]+([^\r\n]+)') {
                $p.CostumeOrChar = $Matches[1].Trim()
            }
        }
    }

    return $result
}

function Find-SameDayCostumeForModel {
    param(
        [string]$ModelName,
        [string]$DateStr,
        [hashtable]$PairedObj,
        [System.Collections.Generic.List[hashtable]]$CurrentPersons,
        [int]$ExcludeIndex = -1
    )
    $cleanTarget = ConvertTo-CleanModelName $ModelName
    if ([string]::IsNullOrWhiteSpace($cleanTarget)) { return "" }

    if ($null -ne $CurrentPersons) {
        for ($i = 0; $i -lt $CurrentPersons.Count; $i++) {
            if ($i -eq $ExcludeIndex) { continue }
            $p = $CurrentPersons[$i]
            $pName = ConvertTo-CleanModelName ([string]$p["Name"])
            $pCos  = [string]$p["CostumeOrChar"]
            if ($pName.Equals($cleanTarget, [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace($pCos)) {
                return $pCos.Trim()
            }
        }
    }

    $searchRoots = New-Object System.Collections.Generic.List[string]
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
        if (-not [string]::IsNullOrWhiteSpace($dateRoot) -and (Test-Path -LiteralPath $dateRoot) -and -not $searchRoots.Contains($dateRoot)) {
            $searchRoots.Add($dateRoot)
        }
    }

    foreach ($root in $searchRoots) {
        $infoFiles = Get-ChildItem -LiteralPath $root -Filter "写真情報.txt" -Recurse -File -ErrorAction SilentlyContinue
        foreach ($fi in $infoFiles) {
            $parsed = Read-PhotoInfoData -FilePath $fi.FullName -PairedObj $PairedObj
            foreach ($p in $parsed.Persons) {
                $pName = ConvertTo-CleanModelName ([string]$p["Name"])
                $pCos  = [string]$p["CostumeOrChar"]
                if ($pName.Equals($cleanTarget, [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace($pCos)) {
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
        [System.Collections.Generic.List[hashtable]]$PersonsList,
        [hashtable]$PairedObj,
        [hashtable]$EffectiveConfig,
        [array]$RelatedFolders
    )

    $catVal   = [string]$FormData.Category
    $dateVal  = [string]$FormData.DateStr
    $eventVal = [string]$FormData.EventName
    $megaVal  = [string]$FormData.MegaLink
    $gigaVal  = [string]$FormData.GigaFileLink

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("【撮影区分】$catVal")
    [void]$sb.AppendLine("【日付】$dateVal")
    [void]$sb.AppendLine("【イベント名】$eventVal")
    [void]$sb.AppendLine("----------------------------------------")

    $modelNamesForScene = @()
    $costumesForScene   = @()

    for ($i = 0; $i -lt $PersonsList.Count; $i++) {
        $p = $PersonsList[$i]
        $pName = ConvertTo-CleanModelName ([string]$p["Name"])
        $pCos  = [string]$p["CostumeOrChar"]
        $pX    = ConvertTo-NormalizedX ([string]$p["XAccount"])
        $pCom  = [string]$p["Comment"]
        $xUrl  = if ([string]::IsNullOrWhiteSpace($pX)) { "" } else { "https://x.com/" + $pX.TrimStart('@') }

        if (-not [string]::IsNullOrWhiteSpace($pName)) { $modelNamesForScene += $pName }
        if (-not [string]::IsNullOrWhiteSpace($pCos))  { $costumesForScene += $pCos }

        [void]$sb.AppendLine("【名前】$pName")
        [void]$sb.AppendLine("【衣装・キャラ】$pCos")
        [void]$sb.AppendLine("【X】$xUrl")
        [void]$sb.AppendLine("【コメント】$pCom")
        [void]$sb.AppendLine("----------------------------------------")

        if (-not [string]::IsNullOrWhiteSpace($pX) -and -not [string]::IsNullOrWhiteSpace($pName)) {
            if (Get-Command Save-XHistory -ErrorAction SilentlyContinue) {
                Save-XHistory $pX $pName $EffectiveConfig $dateVal
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($megaVal)) {
        [void]$sb.AppendLine("【MEGAリンク】$megaVal")
    }
    if (-not [string]::IsNullOrWhiteSpace($gigaVal)) {
        [void]$sb.AppendLine("【ギガファイル便リンク】$gigaVal")
    }

    $outContent = $sb.ToString()
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)

    $savedDirs = New-Object System.Collections.Generic.List[string]
    foreach ($dir in @($PairedObj.Target, $PairedObj.ImportFolder, $PairedObj.DevFolder)) {
        if (-not [string]::IsNullOrWhiteSpace($dir) -and (Test-Path -LiteralPath $dir)) {
            if (-not $savedDirs.Contains($dir)) {
                $savedDirs.Add($dir)
                $infoFile = Join-Path $dir "写真情報.txt"
                [System.IO.File]::WriteAllText($infoFile, $outContent, $utf8Bom)

                if (-not [string]::IsNullOrWhiteSpace($eventVal)) {
                    $parentDir = [System.IO.Path]::GetDirectoryName($dir)
                    if (-not [string]::IsNullOrWhiteSpace($parentDir) -and (Test-Path -LiteralPath $parentDir)) {
                        $scFile = Join-Path $parentDir "scene.txt"
                        $evFile = Join-Path $parentDir "event.txt"
                        if ((Test-Path -LiteralPath $evFile) -and (-not (Test-Path -LiteralPath $scFile))) {
                            Rename-Item -LiteralPath $evFile -NewName "scene.txt" -Force -ErrorAction SilentlyContinue
                        }
                        if (-not (Test-Path -LiteralPath $scFile)) {
                            $scText = "【撮影区分】$catVal`r`n【催事・場所名】$eventVal`r`n"
                            [System.IO.File]::WriteAllText($scFile, $scText, $utf8Bom)
                        }
                    }
                }
            }
        }
    }

    if (Get-Command Update-SceneHistoryData -ErrorAction SilentlyContinue) {
        $firstCostume = if ($costumesForScene.Count -gt 0) { $costumesForScene[0] } else { "" }
        Update-SceneHistoryData -HistoryPath $EffectiveConfig.SceneHistoryPath -Category $catVal -SceneName $eventVal -CostumeName $firstCostume -ModelNames $modelNamesForScene
        for ($cIdx = 1; $cIdx -lt $costumesForScene.Count; $cIdx++) {
            Update-SceneHistoryData -HistoryPath $EffectiveConfig.SceneHistoryPath -Category $catVal -SceneName "" -CostumeName $costumesForScene[$cIdx] -ModelNames @()
        }
    }

    $multiFlagText = if ($null -ne $RelatedFolders -and $RelatedFolders.Count -gt 1) { "複数あり ($($RelatedFolders.Count)件)" } else { "" }

    if (Get-Command Update-PhotoExcelLedger -ErrorAction SilentlyContinue) {
        $records = New-Object System.Collections.Generic.List[hashtable]
        for ($i = 0; $i -lt $PersonsList.Count; $i++) {
            $p = $PersonsList[$i]
            $pName = ConvertTo-CleanModelName ([string]$p["Name"])
            $pCos  = [string]$p["CostumeOrChar"]
            $pX    = ConvertTo-NormalizedX ([string]$p["XAccount"])
            $pCom  = [string]$p["Comment"]
            $xUrl  = if ([string]::IsNullOrWhiteSpace($pX)) { "" } else { "https://x.com/" + $pX.TrimStart('@') }

            $records.Add(@{
                Category      = $catVal
                DateStr       = $dateVal
                EventName     = $eventVal
                CostumeOrChar = $pCos
                Name          = $pName
                XAccount      = $pX
                XUrl          = $xUrl
                Comment       = $pCom
                MegaLink      = $megaVal
                GigaFileLink  = $gigaVal
                MultiFolder   = $multiFlagText
                RelPath       = $PairedObj.RelPath
                ImportRoot    = $EffectiveConfig.ImportRoot1
                ImportFolder  = $PairedObj.ImportFolder
                DevRoot       = $EffectiveConfig.DevRoot
                DevFolder     = $PairedObj.DevFolder
                FolderName    = $PairedObj.FolderName
                PersonIndex   = ($i + 1)
            })
        }
        Update-PhotoExcelLedger $records $EffectiveConfig
    }
}
