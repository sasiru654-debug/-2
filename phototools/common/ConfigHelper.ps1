#requires -Version 5.1
# ==============================================================================
# ConfigHelper.ps1 - settings.ini 読込・期分け判定・互換設定解決 (UTF-8 BOM / CRLF)
# ==============================================================================
Set-StrictMode -Version Latest

function ConvertTo-PhotoExtensionArray {
    param([object]$RawValue)
    if ($null -eq $RawValue) { return @() }
    $items = @()
    if ($RawValue -is [System.Array]) {
        foreach ($v in $RawValue) {
            if (-not [string]::IsNullOrWhiteSpace([string]$v)) {
                $items += ([string]$v).Split(',')
            }
        }
    } else {
        $items = ([string]$RawValue).Split(',')
    }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($it in $items) {
        $s = $it.Trim().ToUpper()
        if ([string]::IsNullOrWhiteSpace($s)) { continue }
        if (-not $s.StartsWith(".")) { $s = "." + $s }
        if (-not $out.Contains($s)) { $out.Add($s) }
    }
    return @($out)
}

function Get-PhotoToolsConfig {
    param(
        [string]$IniPath = "",
        [string]$RootDir = ""
    )

    if ([string]::IsNullOrWhiteSpace($RootDir)) {
        if (-not [string]::IsNullOrWhiteSpace($IniPath)) {
            $RootDir = Split-Path -Parent $IniPath
        } elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
            $RootDir = Split-Path -Parent $PSScriptRoot
        } else {
            $RootDir = "D:\PhotoTools"
        }
    }
    if ([string]::IsNullOrWhiteSpace($IniPath)) {
        $IniPath = Join-Path $RootDir "settings.ini"
    }

    $cfg = @{
        Paths = @{
            ImportRoot           = "G:\写真\eos"
            ImportRoot1          = "G:\写真\eos"
            ImportRoot2          = "H:\写真作業用\eos"
            RawSaveRoot          = "G:\写真raw"
            RawSaveRoot2         = "H:\写真作業用\作業用RAW"
            DevelopedRoot        = "G:\写真\現像後"
            RawArchiveRoot       = "L:"
            DevelopedArchiveRoot = "J:\写真2\現像後"
            DataDir              = (Join-Path $RootDir "data")
            LedgerFileName       = "写真管理一覧.xlsx"
            ExcelPath            = ""
            XHistoryPath         = ""
            SceneHistoryPath     = ""
            GigaFileScriptPath   = (Join-Path $RootDir "gigafile\send_to_gigafile.ps1")
            MegaSyncRootPath     = ""
        }
        ArchivePeriod = @{
            Q1_Months = @(1, 2, 3)
            Q2_Months = @(4, 5, 6)
            Q3_Months = @(7, 8, 9)
            Q4_Months = @(10, 11, 12)
        }
        Extensions = @{
            RawExtensions   = @(".ARW", ".CR2", ".CR3", ".NEF", ".RAF", ".ORF", ".RW2", ".DNG")
            ImageExtensions = @(".JPG", ".JPEG", ".PNG", ".TIF", ".TIFF")
        }
        Mega = @{
            MegaCmdPath    = ""
            MegaRemoteRoot = "/写真1/現像後"
            MegaLogPath    = ""
        }
    }

    $flat = @{}
    if (Test-Path -LiteralPath $IniPath) {
        $currentSection = ""
        $lines = [System.IO.File]::ReadAllLines($IniPath, [System.Text.Encoding]::UTF8)
        foreach ($rawLine in $lines) {
            $line = $rawLine.Trim()
            if ($line -eq "" -or $line.StartsWith(";") -or $line.StartsWith("#")) { continue }
            if ($line -match '^\[(.+)\]$') {
                $currentSection = $Matches[1].Trim()
                if (-not $cfg.ContainsKey($currentSection)) { $cfg[$currentSection] = @{} }
                continue
            }
            if ($line -match '^([^=]+)=(.*)$') {
                $k = $Matches[1].Trim()
                $v = $Matches[2].Trim()
                $flat[$k] = $v
                if ($currentSection -ne "") {
                    if ($k -like "*Months") {
                        $nums = @($v -split ',' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [int]$_.Trim() })
                        $cfg[$currentSection][$k] = $nums
                    } elseif ($k -like "*Extensions") {
                        $cfg[$currentSection][$k] = ConvertTo-PhotoExtensionArray $v
                    } else {
                        $cfg[$currentSection][$k] = $v
                    }
                }
            }
        }
    }

    $pick = {
        param([string[]]$Keys, [string]$DefaultVal)
        foreach ($key in $Keys) {
            if ($flat.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string]$flat[$key])) {
                return [string]$flat[$key]
            }
        }
        return $DefaultVal
    }

    $importRoot1 = (& $pick @("ImportRoot1", "ImportRoot", "RawRootPath") $cfg.Paths.ImportRoot1).TrimEnd('\')
    $importRoot2 = (& $pick @("ImportRoot2") $cfg.Paths.ImportRoot2).TrimEnd('\')
    $rawSaveRoot = (& $pick @("RawSaveRoot", "WorkRawRoot") $cfg.Paths.RawSaveRoot).TrimEnd('\')
    $rawSaveRoot2 = (& $pick @("RawSaveRoot2", "WorkRawRoot2") $cfg.Paths.RawSaveRoot2).TrimEnd('\')
    $devRoot     = (& $pick @("DevelopedRoot", "DevelopedRootPath", "DevRoot", "DevRootDir") $cfg.Paths.DevelopedRoot).TrimEnd('\')
    $rawArch     = (& $pick @("RawArchiveRoot") $cfg.Paths.RawArchiveRoot).TrimEnd('\')
    if ($rawArch -match '^[A-Za-z]:$') { $rawArch += "\" }
    $devArch     = (& $pick @("DevelopedArchiveRoot") $cfg.Paths.DevelopedArchiveRoot).TrimEnd('\')
    $importArch  = (& $pick @("ImportArchiveRoot", "PhotoArchiveRoot") "J:\写真2\eos").TrimEnd('\')
    $dataDir     = (& $pick @("DataDir") (Join-Path $RootDir "data")).TrimEnd('\')
    $ledgerName  = & $pick @("LedgerFileName") "写真管理一覧.xlsx"
    $excelPath   = & $pick @("ExcelPath", "ExcelLedgerPath") ""
    if ([string]::IsNullOrWhiteSpace($excelPath)) {
        $excelPath = Join-Path $devRoot $ledgerName
    }

    $xHistPath   = & $pick @("XHistoryPath", "HistoryPath") (Join-Path $dataDir "x_history.json")
    $sHistPath   = & $pick @("SceneHistoryPath") (Join-Path $dataDir "scene_history.json")
    $gigaPath    = & $pick @("GigaFileScriptPath", "GigaScriptPath") (Join-Path $RootDir "gigafile\send_to_gigafile.ps1")
    $megaCmd     = & $pick @("MegaCmdPath") (Join-Path $env:LOCALAPPDATA "MEGAcmd\mega-export.bat")
    $megaRemote  = & $pick @("MegaRemoteRoot") "/写真1/現像後"
    $megaLog     = & $pick @("MegaLogPath") (Join-Path $dataDir "logs\mega_debug.log")
    $megaSync    = & $pick @("MegaSyncRootPath") ""

    # 階層セクションとフラット互換キーの双方を最新解決値で同期
    $cfg.Paths.ImportRoot           = $importRoot1
    $cfg.Paths.ImportRoot1          = $importRoot1
    $cfg.Paths.ImportRoot2          = $importRoot2
    $cfg.Paths.RawSaveRoot          = $rawSaveRoot
    $cfg.Paths.RawSaveRoot2         = $rawSaveRoot2
    $cfg.Paths.DevelopedRoot        = $devRoot
    $cfg.Paths.RawArchiveRoot       = $rawArch
    $cfg.Paths.DevelopedArchiveRoot = $devArch
    $cfg.Paths.ImportArchiveRoot    = $importArch
    $cfg.Paths.DataDir              = $dataDir
    $cfg.Paths.LedgerFileName       = $ledgerName
    $cfg.Paths.ExcelPath            = $excelPath
    $cfg.Paths.XHistoryPath         = $xHistPath
    $cfg.Paths.SceneHistoryPath     = $sHistPath
    $cfg.Paths.GigaFileScriptPath   = $gigaPath
    $cfg.Paths.MegaSyncRootPath     = $megaSync

    $cfg.Mega.MegaCmdPath    = $megaCmd
    $cfg.Mega.MegaRemoteRoot = $megaRemote
    $cfg.Mega.MegaLogPath    = $megaLog

    # フラットアクセス用プロパティ（PhotoEditorLogic / DailyWorkflow / SyncExcelFromTxt 互換）
    $cfg["RootDir"]              = $RootDir
    $cfg["IniPath"]              = $IniPath
    $cfg["ImportRoot"]           = $importRoot1
    $cfg["ImportRoot1"]          = $importRoot1
    $cfg["ImportRoot2"]          = $importRoot2
    $cfg["RawSaveRoot"]          = $rawSaveRoot
    $cfg["RawSaveRoot2"]         = $rawSaveRoot2
    $cfg["WorkRawRoot"]          = $rawSaveRoot
    $cfg["WorkRawRoot2"]         = $rawSaveRoot2
    $cfg["DevelopedRoot"]        = $devRoot
    $cfg["DevRoot"]              = $devRoot
    $cfg["DevRootDir"]           = $devRoot
    $cfg["RawArchiveRoot"]       = $rawArch
    $cfg["DevelopedArchiveRoot"] = $devArch
    $cfg["ImportArchiveRoot"]    = $importArch
    $cfg["DataDir"]              = $dataDir
    $cfg["LedgerFileName"]       = $ledgerName
    $cfg["ExcelPath"]            = $excelPath
    $cfg["XHistoryPath"]         = $xHistPath
    $cfg["HistoryPath"]          = $xHistPath
    $cfg["SceneHistoryPath"]     = $sHistPath
    $cfg["GigaScriptPath"]       = $gigaPath
    $cfg["GigaFileScriptPath"]   = $gigaPath
    $cfg["MegaCmdPath"]          = $megaCmd
    $cfg["MegaRemoteRoot"]       = $megaRemote
    $cfg["MegaLogPath"]          = $megaLog
    $cfg["MegaSyncRootPath"]     = $megaSync

    return $cfg
}

function Get-PhotoConfig {
    param([string]$IniPath = "", [string]$RootDir = "")
    return Get-PhotoToolsConfig -IniPath $IniPath -RootDir $RootDir
}

function Get-PhotoToolConfig {
    param([string]$IniPath = "", [string]$RootDir = "")
    return Get-PhotoToolsConfig -IniPath $IniPath -RootDir $RootDir
}

function Resolve-DateFromFolderName {
    param([string]$FolderName)
    if ([string]::IsNullOrWhiteSpace($FolderName)) { return $null }
    if ($FolderName -match '(\d{4})[-._/年](\d{1,2})[-._/月](\d{1,2})') {
        try {
            return [datetime]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
        } catch { return $null }
    }
    if ($FolderName -match '(\d{4})(\d{2})(\d{2})') {
        try {
            return [datetime]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
        } catch { return $null }
    }
    return $null
}

function Get-ArchiveSubPathForDate {
    param(
        [Parameter(Mandatory=$true)][datetime]$TargetDate,
        [hashtable]$Config = $null
    )
    if ($null -eq $Config) { $Config = Get-PhotoToolsConfig }
    $yearFolder = "{0}年" -f $TargetDate.Year
    $m = $TargetDate.Month
    $qNum = 1
    if ($Config.ArchivePeriod.Q1_Months -contains $m) { $qNum = 1 }
    elseif ($Config.ArchivePeriod.Q2_Months -contains $m) { $qNum = 2 }
    elseif ($Config.ArchivePeriod.Q3_Months -contains $m) { $qNum = 3 }
    elseif ($Config.ArchivePeriod.Q4_Months -contains $m) { $qNum = 4 }
    $quarterFolder = "{0}期" -f $qNum
    return (Join-Path $yearFolder $quarterFolder)
}

function Get-ArchivePeriodSubPath {
    param(
        [Parameter(Mandatory=$true)][string]$DateFolderName,
        [hashtable]$Config = $null
    )
    if ($null -eq $Config) { $Config = Get-PhotoToolsConfig }
    $dt = Resolve-DateFromFolderName -FolderName $DateFolderName
    if ($null -eq $dt) {
        throw "フォルダ名から撮影日を判定できません: $DateFolderName"
    }
    $rel = Get-ArchiveSubPathForDate -TargetDate $dt -Config $Config
    $yearFolder = "{0}年" -f $dt.Year
    $quarterFolder = Split-Path -Leaf $rel
    return @{
        TargetDate         = $dt
        YearFolder         = $yearFolder
        QuarterFolder      = $quarterFolder
        RelativePeriodPath = $rel
    }
}

function Save-PhotoToolsSettingsIni {
    param(
        [Parameter(Mandatory=$true)][string]$IniPath,
        [Parameter(Mandatory=$true)][hashtable]$Settings
    )
    $parentDir = Split-Path -Parent $IniPath
    if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    $getVal = {
        param([string]$Section, [string]$Key, [string]$Fallback = "")
        if ($Settings.ContainsKey($Section) -and $Settings[$Section] -is [System.Collections.IDictionary] -and $Settings[$Section].Contains($Key)) {
            $v = $Settings[$Section][$Key]
            if ($null -ne $v) { return [string]$v }
        }
        if ($Settings.ContainsKey($Key) -and $null -ne $Settings[$Key]) {
            return [string]$Settings[$Key]
        }
        return $Fallback
    }

    $normMonths = {
        param([string]$Raw, [string]$DefaultVal)
        $parts = @($Raw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' })
        if ($parts.Count -eq 0) { return $DefaultVal }
        $nums = New-Object System.Collections.Generic.List[string]
        foreach ($p in $parts) {
            $n = [int]$p
            if ($n -ge 1 -and $n -le 12 -and -not $nums.Contains([string]$n)) {
                [void]$nums.Add([string]$n)
            }
        }
        if ($nums.Count -eq 0) { return $DefaultVal }
        return ($nums -join ",")
    }

    $normExts = {
        param([string]$Raw, [string]$DefaultVal)
        $arr = @(ConvertTo-PhotoExtensionArray $Raw)
        if ($arr.Count -eq 0) { return $DefaultVal }
        return ($arr -join ",")
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("[Paths]")
    $pathKeys = @(
        "ImportRoot1",
        "ImportRoot2",
        "RawSaveRoot",
        "RawSaveRoot2",
        "DevelopedRoot",
        "RawArchiveRoot",
        "DevelopedArchiveRoot",
        "ImportArchiveRoot",
        "DataDir",
        "LedgerFileName",
        "ExcelPath",
        "XHistoryPath",
        "SceneHistoryPath",
        "GigaFileScriptPath",
        "MegaSyncRootPath"
    )
    foreach ($pk in $pathKeys) {
        $val = (& $getVal "Paths" $pk "").Trim()
        [void]$sb.AppendLine("$pk=$val")
    }
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("[ArchivePeriod]")
    [void]$sb.AppendLine("Q1_Months=" + (& $normMonths (& $getVal "ArchivePeriod" "Q1_Months" "1,2,3") "1,2,3"))
    [void]$sb.AppendLine("Q2_Months=" + (& $normMonths (& $getVal "ArchivePeriod" "Q2_Months" "4,5,6") "4,5,6"))
    [void]$sb.AppendLine("Q3_Months=" + (& $normMonths (& $getVal "ArchivePeriod" "Q3_Months" "7,8,9") "7,8,9"))
    [void]$sb.AppendLine("Q4_Months=" + (& $normMonths (& $getVal "ArchivePeriod" "Q4_Months" "10,11,12") "10,11,12"))
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("[Extensions]")
    [void]$sb.AppendLine("RawExtensions=" + (& $normExts (& $getVal "Extensions" "RawExtensions" ".ARW,.CR2,.CR3,.NEF,.RAF,.ORF,.RW2,.DNG") ".ARW,.CR2,.CR3,.NEF,.RAF,.ORF,.RW2,.DNG"))
    [void]$sb.AppendLine("ImageExtensions=" + (& $normExts (& $getVal "Extensions" "ImageExtensions" ".JPG,.JPEG,.PNG,.TIF,.TIFF") ".JPG,.JPEG,.PNG,.TIF,.TIFF"))
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("[Mega]")
    [void]$sb.AppendLine("MegaCmdPath=" + (& $getVal "Mega" "MegaCmdPath" "").Trim())
    [void]$sb.AppendLine("MegaRemoteRoot=" + (& $getVal "Mega" "MegaRemoteRoot" "/写真1/現像後").Trim())
    [void]$sb.AppendLine("MegaLogPath=" + (& $getVal "Mega" "MegaLogPath" "").Trim())

    if (Test-Path -LiteralPath $IniPath) {
        Copy-Item -LiteralPath $IniPath -Destination ($IniPath + ".bak") -Force -ErrorAction SilentlyContinue
    }
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($IniPath, $sb.ToString(), $utf8Bom)
    return $IniPath
}
