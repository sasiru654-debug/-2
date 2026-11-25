# ConfigHelper.ps1 - settings.ini 読込・期分け判定 (UTF-8 BOM)
Set-StrictMode -Version Latest

function Get-PhotoToolsConfig {
    param([string]$IniPath = "D:\PhotoTools\settings.ini")
    $cfg = @{
        Paths = @{
            ImportRoot = "G:\写真\eos"
            RawSaveRoot = "G:\写真raw"
            DevelopedRoot = "G:\写真\現像後"
            RawArchiveRoot = "L:\"
            DevelopedArchiveRoot = "J:\写真2\現像後"
            DataDir = "D:\PhotoTools\data"
            LedgerFileName = "PhotoLedger.xlsx"
        }
        ArchivePeriod = @{
            Q1_Months = @(1,2,3)
            Q2_Months = @(4,5,6)
            Q3_Months = @(7,8,9)
            Q4_Months = @(10,11,12)
        }
        Extensions = @{
            RawExtensions = @(".ARW",".CR2",".CR3",".NEF",".RAF",".ORF",".RW2",".DNG")
            ImageExtensions = @(".JPG",".JPEG",".PNG",".TIF",".TIFF")
        }
        Mega = @{
            MegaCmdPath = ""
        }
    }
    if (-not (Test-Path -LiteralPath $IniPath)) {
        return $cfg
    }
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
        if ($line -match '^([^=]+)=(.*)$' -and $currentSection -ne "") {
            $k = $Matches[1].Trim()
            $v = $Matches[2].Trim()
            if ($k -like "*Months") {
                $cfg[$currentSection][$k] = @($v -split ',' | ForEach-Object { [int]$_.Trim() })
            } elseif ($k -like "*Extensions") {
                $cfg[$currentSection][$k] = @($v -split ',' | ForEach-Object { $_.Trim().ToUpper() })
            } else {
                $cfg[$currentSection][$k] = $v
            }
        }
    }
    return $cfg
}

function Get-ArchiveSubPathForDate {
    param(
        [Parameter(Mandatory=$true)][datetime]$TargetDate,
        [hashtable]$Config
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

function Resolve-DateFromFolderName {
    param([string]$FolderName)
    if ($FolderName -match '(\d{4})[-._/年]?(\d{1,2})[-._/月]?(\d{1,2})') {
        try {
            return [datetime]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
        } catch { return $null }
    }
    return $null
}
