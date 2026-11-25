#requires -Version 5.1

function Get-SceneHistoryPath {
    param([hashtable]$Config = @{})
    if ($null -ne $Config -and $Config.ContainsKey("SceneHistoryPath") -and -not [string]::IsNullOrWhiteSpace([string]$Config["SceneHistoryPath"])) {
        return [string]$Config["SceneHistoryPath"]
    }
    $root = if ($null -ne $Config -and $Config.ContainsKey("RootDir") -and -not [string]::IsNullOrWhiteSpace([string]$Config["RootDir"])) {
        [string]$Config["RootDir"]
    } else {
        Split-Path -Parent $PSScriptRoot
    }
    return (Join-Path $root "scene_history.json")
}

function Read-SceneHistory {
    param([hashtable]$Config = @{})
    $path = Get-SceneHistoryPath -Config $Config
    if (-not (Test-Path -LiteralPath $path)) {
        return @()
    }
    try {
        $raw = Get-Content -LiteralPath $path -Encoding UTF8 -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $parsed = $raw | ConvertFrom-Json
        if ($null -eq $parsed) { return @() }
        return @($parsed)
    } catch {
        return @()
    }
}

function Save-SceneHistoryEntry {
    param(
        [string]$Category = "イベント",
        [string]$SceneName = "",
        [string]$ModelName = "",
        [string]$CostumeOrChar = "",
        [hashtable]$Config = @{}
    )
    if ([string]::IsNullOrWhiteSpace($SceneName) -and [string]::IsNullOrWhiteSpace($CostumeOrChar) -and [string]::IsNullOrWhiteSpace($ModelName)) {
        return
    }
    $path = Get-SceneHistoryPath -Config $Config
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($item in (Read-SceneHistory -Config $Config)) {
        $list.Add($item)
    }

    $catNorm = if ([string]::IsNullOrWhiteSpace($Category)) { "イベント" } else { $Category.Trim() }
    $scnNorm = $SceneName.Trim()
    $modNorm = $ModelName.Trim()
    $cosNorm = $CostumeOrChar.Trim()

    $exists = $false
    foreach ($it in $list) {
        $c1 = if ($null -ne $it.Category) { [string]$it.Category } else { "" }
        $s1 = if ($null -ne $it.SceneName) { [string]$it.SceneName } else { "" }
        $m1 = if ($null -ne $it.ModelName) { [string]$it.ModelName } else { "" }
        $o1 = if ($null -ne $it.CostumeOrChar) { [string]$it.CostumeOrChar } else { "" }
        if ($c1 -eq $catNorm -and $s1 -eq $scnNorm -and $m1 -eq $modNorm -and $o1 -eq $cosNorm) {
            $exists = $true
            break
        }
    }

    if (-not $exists) {
        $list.Add([PSCustomObject]@{
            Category      = $catNorm
            SceneName     = $scnNorm
            ModelName     = $modNorm
            CostumeOrChar = $cosNorm
            UpdatedAt     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        })
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        $json = $list | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($path, $json, $utf8Bom)
    }
}

function Get-SceneCandidates {
    param(
        [string]$Category = "",
        [hashtable]$Config = @{}
    )
    $all = Read-SceneHistory -Config $Config
    $scenes = New-Object System.Collections.Generic.List[string]
    $costumes = New-Object System.Collections.Generic.List[string]
    $models = New-Object System.Collections.Generic.List[string]

    foreach ($it in $all) {
        $c1 = if ($null -ne $it.Category) { [string]$it.Category } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($Category) -and -not [string]::IsNullOrWhiteSpace($c1) -and $c1 -ne $Category) {
            continue
        }
        $s1 = if ($null -ne $it.SceneName) { ([string]$it.SceneName).Trim() } else { "" }
        $o1 = if ($null -ne $it.CostumeOrChar) { ([string]$it.CostumeOrChar).Trim() } else { "" }
        $m1 = if ($null -ne $it.ModelName) { ([string]$it.ModelName).Trim() } else { "" }

        if (-not [string]::IsNullOrWhiteSpace($s1) -and -not $scenes.Contains($s1)) { $scenes.Add($s1) }
        if (-not [string]::IsNullOrWhiteSpace($o1) -and -not $costumes.Contains($o1)) { $costumes.Add($o1) }
        if (-not [string]::IsNullOrWhiteSpace($m1) -and -not $models.Contains($m1)) { $models.Add($m1) }
    }

    return @{
        Scenes   = $scenes
        Costumes = $costumes
        Models   = $models
    }
}

function Find-SceneInfo {
    param([string[]]$SearchDirs)
    $res = @{
        Category      = ""
        SceneName     = ""
        CostumeOrChar = ""
        SourceFile    = ""
    }
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)

    foreach ($baseDir in $SearchDirs) {
        if ([string]::IsNullOrWhiteSpace($baseDir)) { continue }
        $curr = $baseDir
        for ($depth = 0; $depth -lt 5; $depth++) {
            if ([string]::IsNullOrWhiteSpace($curr)) { break }
            if (Test-Path -LiteralPath $curr) {
                $sceneFile = Join-Path $curr "scene.txt"
                $eventFile = Join-Path $curr "event.txt"

                if ((Test-Path -LiteralPath $eventFile) -and (-not (Test-Path -LiteralPath $sceneFile))) {
                    try {
                        Rename-Item -LiteralPath $eventFile -NewName "scene.txt" -Force -ErrorAction Stop
                    } catch {
                        Copy-Item -LiteralPath $eventFile -Destination $sceneFile -Force -ErrorAction SilentlyContinue
                    }
                }

                if (Test-Path -LiteralPath $sceneFile) {
                    $raw = Get-Content -LiteralPath $sceneFile -Encoding UTF8 -Raw
                    if (-not [string]::IsNullOrWhiteSpace($raw)) {
                        $res.SourceFile = $sceneFile
                        $lines = $raw -split "`r?`n"
                        $hasTag = $false
                        foreach ($ln in $lines) {
                            if ($ln -match '^【撮影区分】(.*)$') { $res.Category = $Matches[1].Trim(); $hasTag = $true }
                            elseif ($ln -match '^【(?:催事名|イベント名|スタジオ名|併せ名|場所)】(.*)$') { $res.SceneName = $Matches[1].Trim(); $hasTag = $true }
                            elseif ($ln -match '^【(?:衣装・キャラ|衣装名ORキャラ名|衣装)】(.*)$') { $res.CostumeOrChar = $Matches[1].Trim(); $hasTag = $true }
                        }
                        if (-not $hasTag) {
                            $res.SceneName = $raw.Trim()
                        }
                        return $res
                    }
                }
            }
            $curr = [System.IO.Path]::GetDirectoryName($curr)
        }
    }
    return $res
}

function Save-SceneFile {
    param(
        [string]$TargetDir,
        [string]$Category = "イベント",
        [string]$SceneName = "",
        [string]$CostumeOrChar = ""
    )
    if ([string]::IsNullOrWhiteSpace($TargetDir) -or -not (Test-Path -LiteralPath $TargetDir)) { return }
    if ([string]::IsNullOrWhiteSpace($SceneName) -and [string]::IsNullOrWhiteSpace($CostumeOrChar)) { return }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $sceneFile = Join-Path $TargetDir "scene.txt"
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("【撮影区分】$Category")
    [void]$sb.AppendLine("【催事名】$SceneName")
    if (-not [string]::IsNullOrWhiteSpace($CostumeOrChar)) {
        [void]$sb.AppendLine("【衣装・キャラ】$CostumeOrChar")
    }
    [System.IO.File]::WriteAllText($sceneFile, $sb.ToString(), $utf8Bom)
}

function Extract-CostumeFromLegacyComment {
    param([string]$CommentText)
    if ([string]::IsNullOrWhiteSpace($CommentText)) { return "" }
    $lines = $CommentText -split "`r?`n"
    foreach ($ln in $lines) {
        $t = $ln.Trim()
        if ($t -match '^(?:キャラ|キャラ名|衣装|衣装名|作品)[：:\s]+(.+)$') {
            return $Matches[1].Trim()
        }
        if ($t -match '^【(?:キャラ|キャラ名|衣装|衣装名)】(.+)$') {
            return $Matches[1].Trim()
        }
    }
    return ""
}

function Find-SameModelFoldersOnDate {
    param(
        [string]$CurrentFolder,
        [string]$DateStr,
        [string[]]$ModelNames
    )
    $matchesList = New-Object System.Collections.Generic.List[hashtable]
    $validModels = @($ModelNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    if ($validModels.Count -eq 0 -or [string]::IsNullOrWhiteSpace($CurrentFolder)) {
        return $matchesList
    }

    $dateRoot = ""
    $curr = $CurrentFolder
    for ($i = 0; $i -lt 5; $i++) {
        if ([string]::IsNullOrWhiteSpace($curr)) { break }
        $leaf = [System.IO.Path]::GetFileName($curr)
        if ((-not [string]::IsNullOrWhiteSpace($DateStr) -and $leaf -eq $DateStr) -or ($leaf -match '^\d{4}[_-]\d{2}[_-]\d{2}')) {
            $dateRoot = $curr
            break
        }
        $curr = [System.IO.Path]::GetDirectoryName($curr)
    }

    if ([string]::IsNullOrWhiteSpace($dateRoot) -or -not (Test-Path -LiteralPath $dateRoot)) {
        return $matchesList
    }

    $infoFiles = Get-ChildItem -LiteralPath $dateRoot -Filter "写真情報.txt" -Recurse -File -ErrorAction SilentlyContinue
    foreach ($fi in $infoFiles) {
        $dir = $fi.DirectoryName
        $raw = Get-Content -LiteralPath $fi.FullName -Encoding UTF8 -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }

        $foundNames = New-Object System.Collections.Generic.List[string]
        $costume = ""
        $scene = ""
        foreach ($ln in ($raw -split "`r?`n")) {
            if ($ln -match '^【(?:名前|モデル名)】(.*)$') {
                $nm = $Matches[1].Trim()
                if (-not [string]::IsNullOrWhiteSpace($nm)) { $foundNames.Add($nm) }
            }
            elseif ($ln -match '^【(?:衣装・キャラ|衣装名ORキャラ名|衣装)】(.*)$') {
                $costume = $Matches[1].Trim()
            }
            elseif ($ln -match '^【(?:イベント名|催事名|スタジオ名|併せ名|場所)】(.*)$') {
                $scene = $Matches[1].Trim()
            }
        }

        $hitModel = ""
        foreach ($vm in $validModels) {
            if ($foundNames.Contains($vm)) {
                $hitModel = $vm
                break
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($hitModel)) {
            $rel = $dir.Substring($dateRoot.Length).TrimStart('\')
            if ([string]::IsNullOrWhiteSpace($rel)) { $rel = [System.IO.Path]::GetFileName($dir) }
            $matchesList.Add(@{
                FolderPath    = $dir
                RelativeLabel = $rel
                ModelName     = $hitModel
                SceneName     = $scene
                CostumeOrChar = $costume
                IsCurrent     = ($dir.TrimEnd('\') -eq $CurrentFolder.TrimEnd('\'))
            })
        }
    }
    return $matchesList
}
