#requires -Version 5.1
# ==============================================================================
# PhotoInfoHelper.ps1 - PhotoInfo read/write and legacy migration (100% ASCII)
# ==============================================================================
Set-StrictMode -Version Latest

function Get-Tag {
    param([int[]]$Codes)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $Codes) { [void]$sb.Append([char]$c) }
    return $sb.ToString()
}

function ConvertTo-SafeNormalizedX {
    param([string]$Raw)
    if (Get-Command Normalize-XAccount -ErrorAction SilentlyContinue) {
        return (Normalize-XAccount $Raw)
    }
    if ([string]::IsNullOrWhiteSpace($Raw)) { return "" }
    $s = $Raw.Trim()
    foreach ($charToRemove in @([char]0xFF08, [char]0xFF09, [char]0x0028, [char]0x0029, [char]0x0020)) {
        $s = $s.Replace([string]$charToRemove, '')
    }
    if ($s.Contains("x.com/") -or $s.Contains("twitter.com/")) {
        $idx = $s.IndexOf("x.com/")
        if ($idx -lt 0) { $idx = $s.IndexOf("twitter.com/") }
        if ($idx -ge 0) {
            $sub = $s.Substring($idx)
            $parts = $sub.Split('/')
            if ($parts.Length -ge 2 -and -not [string]::IsNullOrWhiteSpace($parts[1])) {
                return "@" + $parts[1].Trim()
            }
        }
    }
    $s = $s.TrimStart('@', [char]0xFF20)
    if (-not [string]::IsNullOrWhiteSpace($s)) {
        $clean = ""
        foreach ($ch in $s.ToCharArray()) {
            if (($ch -ge 'a' -and $ch -le 'z') -or ($ch -ge 'A' -and $ch -le 'Z') -or ($ch -ge '0' -and $ch -le '9') -or $ch -eq '_') {
                $clean += $ch
            } else {
                break
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($clean)) {
            return "@" + $clean
        }
    }
    return ""
}

function ConvertTo-SafeCleanModelName {
    param([string]$RawName)
    if (Get-Command ConvertTo-CleanModelName -ErrorAction SilentlyContinue) {
        return (ConvertTo-CleanModelName $RawName)
    }
    if ([string]::IsNullOrWhiteSpace($RawName)) { return "" }
    $n = $RawName.Trim()
    $idxHalf = $n.IndexOf('@')
    $idxFull = $n.IndexOf([char]0xFF20)
    $cut = -1
    if ($idxHalf -ge 0 -and $idxFull -ge 0) { $cut = [Math]::Min($idxHalf, $idxFull) }
    elseif ($idxHalf -ge 0) { $cut = $idxHalf }
    elseif ($idxFull -ge 0) { $cut = $idxFull }
    if ($cut -gt 0) { $n = $n.Substring(0, $cut).Trim() }
    return $n
}

function New-EmptyPhotoInfo {
    param([string]$FolderPath = "")
    $dateStr = ""
    if (-not [string]::IsNullOrWhiteSpace($FolderPath)) {
        $curr = $FolderPath
        for ($i = 0; $i -lt 5; $i++) {
            if ([string]::IsNullOrWhiteSpace($curr)) { break }
            $leaf = Split-Path $curr -Leaf
            if ($leaf.Length -ge 10) {
                $dateStr = $leaf.Substring(0, 10).Replace('-', '_').Replace('.', '_')
                break
            }
            $curr = Split-Path $curr -Parent
        }
    }
    $persons = New-Object System.Collections.Generic.List[hashtable]
    $persons.Add(@{ Name = ""; CostumeOrChar = ""; XAccount = ""; Comment = "" })

    return [ordered]@{
        FolderPath    = $FolderPath
        FolderName    = if ([string]::IsNullOrWhiteSpace($FolderPath)) { "" } else { Split-Path -Leaf $FolderPath }
        ShootDate     = $dateStr
        DateStr       = $dateStr
        Category      = (Get-Tag @(0x30A4, 0x30D9, 0x30F3, 0x30C8))
        EventName     = ""
        CostumeOrChar = ""
        Persons       = $persons
        Models        = @()
        MegaLink      = ""
        GigaFileLink  = ""
        ShareUrl      = ""
        DlPassword    = ""
        SentStatus    = (Get-Tag @(0x672A, 0x9001, 0x4ED8))
        IsSent        = $false
        Status        = (Get-Tag @(0x672A, 0x767B, 0x9332))
        IsRegistered  = $false
        Notes         = ""
        Comment       = ""
        UpdatedAt     = ""
    }
}

function Read-PhotoInfoTxt {
    param(
        [Parameter(Mandatory=$true)][string]$FolderPath,
        [string]$FilePath = "",
        [hashtable]$Config = @{}
    )

    $txtPath = if (-not [string]::IsNullOrWhiteSpace($FilePath)) { $FilePath } else { Join-Path $FolderPath "写真情報.txt" }
    $info = New-EmptyPhotoInfo -FolderPath $FolderPath
    if (-not (Test-Path -LiteralPath $txtPath)) {
        return $info
    }

    $rawText = try { [System.IO.File]::ReadAllText($txtPath, [System.Text.Encoding]::UTF8) } catch { "" }
    if ([string]::IsNullOrWhiteSpace($rawText)) {
        return $info
    }

    $lines = $rawText -split "`r?`n"
    $isBracketFormat = $rawText.Contains((Get-Tag @(0x3010)))

    if ($isBracketFormat) {
        $persons = New-Object System.Collections.Generic.List[hashtable]
        $curPerson = $null
        $inPersonComment = $false
        $inHeaderMemo = $false
        $headerCostume = ""
        $hasExplicitSentStatus = $false

        $tCat   = Get-Tag @(0x3010, 0x64EE, 0x5F71, 0x533A, 0x5206, 0x3011)
        $tDate1 = Get-Tag @(0x3010, 0x64EE, 0x5F71, 0x65E5, 0x3011)
        $tDate2 = Get-Tag @(0x3010, 0x65E5, 0x4ED8, 0x3011)
        $tEv1   = Get-Tag @(0x3010, 0x30A4, 0x30D9, 0x30F3, 0x30C8, 0x540D, 0x3011)
        $tEv2   = Get-Tag @(0x3010, 0x30A4, 0x30D9, 0x30F3, 0x30C8, 0x30FB, 0x5834, 0x6240, 0x3011)
        $tSts   = Get-Tag @(0x3010, 0x30B9, 0x30BF, 0x30B8, 0x30AA, 0x540D, 0x3011)
        $tAse   = Get-Tag @(0x3010, 0x4F75, 0x305B, 0x540D, 0x3011)
        $tPlc   = Get-Tag @(0x3010, 0x5834, 0x6245, 0x3011)
        $tSai   = Get-Tag @(0x3010, 0x50AC, 0x4E8B, 0x30FB, 0x5834, 0x6245, 0x540D, 0x3011)
        $tMega1 = Get-Tag @(0x3010, 0x004D, 0x0045, 0x0047, 0x30A2, 0x30EA, 0x30F3, 0x30AF, 0x3011)
        $tMega2 = Get-Tag @(0x3010, 0x004D, 0x0045, 0x0047, 0x0041, 0x5171, 0x6709, 0x0055, 0x0052, 0x004C, 0x3011)
        $tGiga1 = Get-Tag @(0x3010, 0x30AE, 0x30AC, 0x30D5, 0x30A1, 0x30A4, 0xEB, 0x4FBF, 0x30EA, 0x30F3, 0x30AF, 0x3011)
        $tGiga2 = Get-Tag @(0x3010, 0x30AE, 0x30AC, 0x30D5, 0x30A1, 0x30A4, 0xEB, 0x0055, 0x0052, 0x004C, 0x3011)
        $tUrl   = Get-Tag @(0x3010, 0x5171, 0x6709, 0x0055, 0x0052, 0x004C, 0x3011)
        $tSent1 = Get-Tag @(0x3010, 0x30C7, 0x30FC, 0x30BF, 0x9001, 0x4ED8, 0x72B6, 0x6CC1, 0x3011)
        $tSent2 = Get-Tag @(0x3010, 0x9001, 0x4ED8, 0x72B6, 0x6CC1, 0x3011)
        $tUpd   = Get-Tag @(0x3010, 0x6700, 0x7D42, 0x66F4, 0x65B0, 0x65E5, 0x6642, 0x3011)
        $tCos1  = Get-Tag @(0x3010, 0x8863, 0x88C5, 0x30FB, 0x30AD, 0x30E3, 0x30E9, 0x3011)
        $tCos2  = Get-Tag @(0x3010, 0x8863, 0x88C5, 0x540D, 0x004F, 0x0052, 0x30AD, 0x30E3, 0x30E9, 0x540D, 0x3011)
        $tCos3  = Get-Tag @(0x3010, 0x8863, 0x88C5, 0x3011)
        $tCos4  = Get-Tag @(0x3010, 0x30AD, 0x30E3, 0x30E9, 0x540D, 0x3011)
        $tNam1  = Get-Tag @(0x3010, 0x540D, 0x524D, 0x3011)
        $tNam2  = Get-Tag @(0x3010, 0x30E2, 0x30C7, 0x30EB, 0x540D, 0x3011)
        $tX1    = Get-Tag @(0x3010, 0x0058, 0x3011)
        $tX2    = Get-Tag @(0x3010, 0x0058, 0x30A2, 0x30AB, 0x30A6, 0x30F3, 0x30C8, 0x3011)
        $tX3    = Get-Tag @(0x3010, 0x30A2, 0x30AB, 0x30A6, 0x30F3, 0x30C8, 0x3011)
        $tX4    = Get-Tag @(0x3010, 0x30A2, 0x30AB, 0x30A6, 0x30F3, 0x30C8, 0x540D, 0x3011)
        $tX5    = Get-Tag @(0x3010, 0x0054, 0x0077, 0x0069, 0x0074, 0x0074, 0x0065, 0x0072, 0x3011)
        $tMemo  = Get-Tag @(0x3010, 0x30E1, 0x30ED, 0x3011)
        $tCom   = Get-Tag @(0x3010, 0x30B3, 0x30E1, 0x30F3, 0x30C8, 0x3011)
        $tRem   = Get-Tag @(0x3010, 0x5099, 0x8003, 0x3011)
        $bClose = [string][char]0x3011

        foreach ($line in $lines) {
            $trim = $line.Trim()
            if ($trim.Length -ge 5 -and $trim.Trim('-') -eq "") {
                if ($null -ne $curPerson) {
                    $curPerson.Comment = $curPerson.Comment.TrimEnd("`r", "`n")
                    $persons.Add($curPerson)
                    $curPerson = $null
                }
                $inPersonComment = $false
                $inHeaderMemo = $false
                continue
            }

            if ($trim.StartsWith($tCat)) {
                $inPersonComment = $false; $inHeaderMemo = $false
                $colonIdx = $trim.IndexOf($bClose)
                if ($colonIdx -ge 0) {
                    $v = $trim.Substring($colonIdx + 1).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($v)) { $info.Category = $v }
                }
            }
            elseif ($trim.StartsWith($tDate1) -or $trim.StartsWith($tDate2)) {
                $inPersonComment = $false; $inHeaderMemo = $false
                $colonIdx = $trim.IndexOf($bClose)
                if ($colonIdx -ge 0) {
                    $v = $trim.Substring($colonIdx + 1).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($v)) {
                        $info.ShootDate = $v
                        $info.DateStr = $v
                    }
                }
            }
            elseif ($trim.StartsWith($tEv1) -or $trim.StartsWith($tEv2) -or $trim.StartsWith($tSts) -or $trim.StartsWith($tAse) -or $trim.StartsWith($tPlc) -or $trim.StartsWith($tSai)) {
                $inPersonComment = $false; $inHeaderMemo = $false
                $colonIdx = $trim.IndexOf($bClose)
                if ($colonIdx -ge 0) { $info.EventName = $trim.Substring($colonIdx + 1).Trim() }
            }
            elseif ($trim.StartsWith($tMega1) -or $trim.StartsWith($tMega2)) {
                $inPersonComment = $false; $inHeaderMemo = $false
                $colonIdx = $trim.IndexOf($bClose)
                if ($colonIdx -ge 0) { $info.MegaLink = $trim.Substring($colonIdx + 1).Trim() }
            }
            elseif ($trim.StartsWith($tGiga1) -or $trim.StartsWith($tGiga2) -or $trim.StartsWith($tUrl)) {
                $inPersonComment = $false; $inHeaderMemo = $false
                $colonIdx = $trim.IndexOf($bClose)
                if ($colonIdx -ge 0) {
                    $v = $trim.Substring($colonIdx + 1).Trim()
                    $info.GigaFileLink = $v
                    $info.ShareUrl = $v
                }
            }
            elseif ($trim.StartsWith($tSent1) -or $trim.StartsWith($tSent2)) {
                $inPersonComment = $false; $inHeaderMemo = $false
                $colonIdx = $trim.IndexOf($bClose)
                if ($colonIdx -ge 0) {
                    $v = $trim.Substring($colonIdx + 1).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($v)) {
                        $hasExplicitSentStatus = $true
                        $sentDone = Get-Tag @(0x9001, 0x4ED8, 0x6E08, 0x307F)
                        $sentDoneAlt = Get-Tag @(0x9001, 0x4ED8, 0x6E08)
                        $sentNot = Get-Tag @(0x672A, 0x9001, 0x4ED8)
                        $info.IsSent = ($v -eq $sentDone -or $v -eq $sentDoneAlt -or $v -eq "True" -or $v -eq "1" -or $v -eq [string][char]0x25CF)
                        $info.SentStatus = if ($info.IsSent) { $sentDone } else { $sentNot }
                    }
                }
            }
            elseif ($trim.StartsWith($tUpd)) {
                $inPersonComment = $false; $inHeaderMemo = $false
                $colonIdx = $trim.IndexOf($bClose)
                if ($colonIdx -ge 0) { $info.UpdatedAt = $trim.Substring($colonIdx + 1).Trim() }
            }
            elseif ($trim.StartsWith($tCos1) -or $trim.StartsWith($tCos2) -or $trim.StartsWith($tCos3) -or $trim.StartsWith($tCos4)) {
                $inPersonComment = $false; $inHeaderMemo = $false
                $colonIdx = $trim.IndexOf($bClose)
                if ($colonIdx -ge 0) {
                    $cVal = $trim.Substring($colonIdx + 1).Trim()
                    if ($null -ne $curPerson) {
                        $curPerson.CostumeOrChar = $cVal
                    } else {
                        $headerCostume = $cVal
                    }
                }
            }
            elseif ($trim.StartsWith($tNam1) -or $trim.StartsWith($tNam2)) {
                $inPersonComment = $false; $inHeaderMemo = $false
                if ($null -ne $curPerson) {
                    $curPerson.Comment = $curPerson.Comment.TrimEnd("`r", "`n")
                    $persons.Add($curPerson)
                }
                $colonIdx = $trim.IndexOf($bClose)
                $nVal = if ($colonIdx -ge 0) { $trim.Substring($colonIdx + 1).Trim() } else { "" }
                $curPerson = @{
                    Name          = ConvertTo-SafeCleanModelName $nVal
                    CostumeOrChar = ""
                    XAccount      = ""
                    Comment       = ""
                }
            }
            elseif ($trim.StartsWith($tX1) -or $trim.StartsWith($tX2) -or $trim.StartsWith($tX3) -or $trim.StartsWith($tX4) -or $trim.StartsWith($tX5)) {
                $inPersonComment = $false; $inHeaderMemo = $false
                if ($null -eq $curPerson) {
                    $curPerson = @{ Name = ""; CostumeOrChar = ""; XAccount = ""; Comment = "" }
                }
                $colonIdx = $trim.IndexOf($bClose)
                $xVal = if ($colonIdx -ge 0) { $trim.Substring($colonIdx + 1).Trim() } else { "" }
                $curPerson.XAccount = ConvertTo-SafeNormalizedX $xVal
            }
            elseif ($trim.StartsWith($tMemo) -or $trim.StartsWith($tCom) -or $trim.StartsWith($tRem)) {
                $colonIdx = $trim.IndexOf($bClose)
                $memoVal = if ($colonIdx -ge 0) { $trim.Substring($colonIdx + 1).Trim() } else { "" }
                if ($null -ne $curPerson) {
                    $curPerson.Comment = $memoVal
                    $inPersonComment = $true
                    $inHeaderMemo = $false
                } else {
                    $info.Notes = $memoVal
                    $inHeaderMemo = $true
                    $inPersonComment = $false
                }
            }
            elseif ($inPersonComment -and $null -ne $curPerson) {
                if ([string]::IsNullOrEmpty($curPerson.Comment)) { $curPerson.Comment = $line }
                else { $curPerson.Comment += "`r`n" + $line }
            }
            elseif ($inHeaderMemo) {
                if ([string]::IsNullOrEmpty($info.Notes)) { $info.Notes = $line }
                else { $info.Notes += "`r`n" + $line }
            }
        }

        if ($null -ne $curPerson) {
            $curPerson.Comment = $curPerson.Comment.TrimEnd("`r", "`n")
            $persons.Add($curPerson)
        }
        if ($persons.Count -eq 0) {
            $persons.Add(@{ Name = ""; CostumeOrChar = ""; XAccount = ""; Comment = "" })
        }
        if (-not [string]::IsNullOrWhiteSpace($headerCostume) -and [string]::IsNullOrWhiteSpace($persons[0].CostumeOrChar)) {
            $persons[0].CostumeOrChar = $headerCostume
        }

        for ($i = 0; $i -lt $persons.Count; $i++) {
            $p = $persons[$i]
            if ([string]::IsNullOrWhiteSpace([string]$p.CostumeOrChar) -and -not [string]::IsNullOrWhiteSpace([string]$p.Comment)) {
                $com = [string]$p.Comment
                $cTag1 = Get-Tag @(0x30AD, 0x30E3, 0x30E9, 0xFF1A)
                $cTag2 = Get-Tag @(0x8863, 0x88C5, 0xFF1A)
                $cTag3 = Get-Tag @(0x30AD, 0x30E3, 0x30E9, 0x003A)
                $cTag4 = Get-Tag @(0x8863, 0x88C5, 0x003A)
                if ($com.Contains($cTag1) -or $com.Contains($cTag2) -or $com.Contains($cTag3) -or $com.Contains($cTag4)) {
                    $colonIdx2 = $com.IndexOf([char]0xFF1A)
                    if ($colonIdx2 -lt 0) { $colonIdx2 = $com.IndexOf([char]0x003A) }
                    if ($colonIdx2 -ge 0) {
                        $p.CostumeOrChar = $com.Substring($colonIdx2 + 1).Split("`r`n")[0].Trim()
                    }
                }
            }
        }

        $info.Persons = $persons
    }
    else {
        $hasCostumeField = $false
        $hasExplicitSentStatus = $false
        $legacyModels = @()
        foreach ($rawLine in $lines) {
            $line = $rawLine.Trim()
            if ($line -eq "" -or $line.StartsWith("#")) { continue }
            $colonIdx = $line.IndexOf([char]0x003A)
            if ($colonIdx -lt 0) { $colonIdx = $line.IndexOf([char]0xFF1A) }
            if ($colonIdx -ge 0) {
                $key = $line.Substring(0, $colonIdx).Trim()
                $val = $line.Substring($colonIdx + 1).Trim()
                $kDate = Get-Tag @(0x64EE, 0x5F71, 0x65E5)
                $kCat = Get-Tag @(0x64EE, 0x5F71, 0x533A, 0x5206)
                $kDiv = Get-Tag @(0x533A, 0x5206)
                $kEv = Get-Tag @(0x30A4, 0x30D9, 0x30F3, 0x30C8, 0x540D)
                $kStsName = Get-Tag @(0x30B9, 0x30BF, 0x30B8, 0x30AA, 0x540D)
                $kAseName = Get-Tag @(0x4F75, 0x305B, 0x540D)
                $kPlcName = Get-Tag @(0x5834, 0x6245)
                $kCosName = Get-Tag @(0x8863, 0x88C5, 0x540D, 0x004F, 0x0052, 0x30AD, 0x30E3, 0x30E9, 0x540D)
                $kCharOnly = Get-Tag @(0x30AD, 0x30E3, 0x30E9, 0x540D)
                $kCosOnly = Get-Tag @(0x8863, 0x88C5)
                $kModel = Get-Tag @(0x30E2, 0x30C7, 0x30EB)
                $kModelInfo = Get-Tag @(0x30E2, 0x30C7, 0x30EB, 0x60C5, 0x5831)
                $kShare = Get-Tag @(0x5171, 0x6709, 0x0055, 0x0052, 0x004C)
                $kGiga = Get-Tag @(0x30AE, 0x30AC, 0x30D5, 0x30A1, 0x30A4, 0xEB, 0x0055, 0x0052, 0x004C)
                $kMega = Get-Tag @(0x004D, 0x0045, 0x0047, 0x0041, 0x30EA, 0x30F3, 0x30AF)
                $kMegaU = Get-Tag @(0x004D, 0x0045, 0x0047, 0x0041, 0x5171, 0x6709, 0x0055, 0x0052, 0x004C)
                $kPass = Get-Tag @(0x0044, 0x004C, 0x30D1, 0x30B9, 0x30EF, 0x30FC, 0x30C9)
                $kPass2 = Get-Tag @(0x30D1, 0x30B9, 0x30EF, 0x30FC, 0x30C9)
                $kSent = Get-Tag @(0x9001, 0x4ED8, 0x72B6, 0x6CC1)
                $kSentD = Get-Tag @(0x30C7, 0x30FC, 0x30BF, 0x9001, 0x4ED8, 0x72B6, 0x6CC1)
                $kSentDon = Get-Tag @(0x9001, 0x4ED8, 0x6E08)
                $kSentDonF = Get-Tag @(0x9001, 0x4ED8, 0x6E08, 0x307F)
                $kStatus = Get-Tag @(0x72B6, 0x614B)
                $kStatusS = Get-Tag @(0x30B9, 0x30C6, 0x30FC, 0x30BF, 0x30B9)
                $kComment = Get-Tag @(0x30B3, 0x30E1, 0x30F3, 0x30C8)
                $kMemo = Get-Tag @(0x30E1, 0x30ED)
                $kUpdTime = Get-Tag @(0x6700, 0x7D42, 0x66F4, 0x65B0, 0x65E5, 0x6642)

                if ($key -eq $kDate -or $key -eq "ShootDate") { $info.ShootDate = $val; $info.DateStr = $val }
                elseif ($key -eq $kCat -or $key -eq $kDiv -or $key -eq "Category") { if ($val -ne "") { $info.Category = $val } }
                elseif ($key -eq $kEv -or $key -eq $kStsName -or $key -eq $kAseName -or $key -eq $kPlcName -or $key -eq "EventName") { $info.EventName = $val }
                elseif ($key -eq $kCosName -or $key -eq $kCharOnly -or $key -eq $kCosOnly -or $key -eq "CostumeOrChar") {
                    $info.CostumeOrChar = $val
                    $hasCostumeField = $true
                }
                elseif ($key -eq $kModel -or $key -eq $kModelInfo -or $key.StartsWith("Model") -or $key -eq "Models") {
                    if ($val -ne "") {
                        $parts = $val.Split('|')
                        $mName = ConvertTo-SafeCleanModelName $parts[0].Trim()
                        $mX = if ($parts.Length -ge 2) { ConvertTo-SafeNormalizedX $parts[1].Trim() } else { "" }
                        $mChar = if ($parts.Length -ge 3) { $parts[2].Trim() } else { "" }
                        $legacyModels += @{ Name = $mName; CostumeOrChar = $mChar; XAccount = $mX; Comment = "" }
                    }
                }
                elseif ($key -eq $kShare -or $key -eq $kGiga -or $key -eq "URL" -or $key -eq "ShareUrl") { $info.ShareUrl = $val; $info.GigaFileLink = $val }
                elseif ($key -eq $kMega -or $key -eq $kMegaU) { $info.MegaLink = $val }
                elseif ($key -eq $kPass -or $key -eq $kPass2 -or $key -eq "DlPassword") { $info.DlPassword = $val }
                elseif ($key -eq $kSent -or $key -eq $kSentD -or $key -eq $kSentDon -or $key -eq $kSentDonF -or $key -eq "IsSent") {
                    if ($val -ne "") { $hasExplicitSentStatus = $true }
                    $sentDone = Get-Tag @(0x9001, 0x4ED8, 0x6E08, 0x307F)
                    $info.IsSent = ($val -eq "True" -or $val -eq $sentDone -or $val -eq $sentDon -or $val -eq "1" -or $val -eq [string][char]0x25CF)
                    $info.SentStatus = if ($info.IsSent) { $sentDone } else { Get-Tag @(0x672A, 0x9001, 0x4ED8) }
                }
                elseif ($key -eq $kStatus -or $key -eq $kStatusS -or $key -eq "Status") { if ($val -ne "") { $info.Status = $val } }
                elseif ($key -eq $kComment -or $key -eq $kMemo -or $key -eq "Comment") { $info.Notes = $val; $info.Comment = $val }
                elseif ($key -eq $kUpdTime -or $key -eq "UpdatedAt") { $info.UpdatedAt = $val }
            }
        }
        if (-not $hasCostumeField -and $info.CostumeOrChar -eq "" -and $info.Comment -ne "") {
            $info.CostumeOrChar = $info.Comment
            $info.Comment = ""
            $info.Notes = ""
        }
        $persons = New-Object System.Collections.Generic.List[hashtable]
        if (@($legacyModels).Count -gt 0) {
            foreach ($lm in $legacyModels) {
                if ([string]::IsNullOrWhiteSpace($lm.CostumeOrChar) -and -not [string]::IsNullOrWhiteSpace($info.CostumeOrChar)) {
                    $lm.CostumeOrChar = $info.CostumeOrChar
                }
                $persons.Add($lm)
            }
        } else {
            $persons.Add(@{ Name = ""; CostumeOrChar = $info.CostumeOrChar; XAccount = ""; Comment = $info.Comment })
        }
        $info.Persons = $persons
    }

    if ([string]::IsNullOrWhiteSpace($info.ShareUrl) -and -not [string]::IsNullOrWhiteSpace($info.GigaFileLink)) {
        $info.ShareUrl = $info.GigaFileLink
    } elseif ([string]::IsNullOrWhiteSpace($info.GigaFileLink) -and -not [string]::IsNullOrWhiteSpace($info.ShareUrl)) {
        $info.GigaFileLink = $info.ShareUrl
    }
    $sentNot = Get-Tag @(0x672A, 0x9001, 0x4ED8)
    $sentDone = Get-Tag @(0x9001, 0x4ED8, 0x6E08, 0x307F)
    if ((-not $hasExplicitSentStatus) -and (-not [string]::IsNullOrWhiteSpace($info.GigaFileLink)) -and ($info.SentStatus -eq $sentNot)) {
        $info.SentStatus = $sentDone
        $info.IsSent = $true
    }
    $modelsArr = @()
    foreach ($p in $info.Persons) {
        if ($null -eq $p) { continue }
        $pNm = if ($p -is [System.Collections.IDictionary] -and $p.Contains("Name")) { [string]$p["Name"] } else { "" }
        $pXa = if ($p -is [System.Collections.IDictionary] -and $p.Contains("XAccount")) { [string]$p["XAccount"] } else { "" }
        $pCh = if ($p -is [System.Collections.IDictionary] -and $p.Contains("CostumeOrChar")) { [string]$p["CostumeOrChar"] } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($pNm) -or -not [string]::IsNullOrWhiteSpace($pXa) -or -not [string]::IsNullOrWhiteSpace($pCh)) {
            $modelsArr += [pscustomobject]@{
                Name     = $pNm
                XId      = $pXa.TrimStart('@')
                CharName = $pCh
            }
        }
    }
    $info.Models = $modelsArr
    if ([string]::IsNullOrWhiteSpace($info.CostumeOrChar) -and @($info.Persons).Count -gt 0 -and $null -ne $info.Persons[0]) {
        $info.CostumeOrChar = if ($info.Persons[0] -is [System.Collections.IDictionary] -and $info.Persons[0].Contains("CostumeOrChar")) { [string]$info.Persons[0]["CostumeOrChar"] } else { "" }
    }
    $hasAnyInfo = (-not [string]::IsNullOrWhiteSpace($info.EventName)) -or (@($modelsArr).Count -gt 0) -or (-not [string]::IsNullOrWhiteSpace($info.CostumeOrChar))
    if ($hasAnyInfo) {
        $info.Status = Get-Tag @(0x767B, 0x6E08)
        $info.IsRegistered = $true
    }
    $info.Comment = $info.Notes
    return $info
}

function Write-PhotoInfoTxt {
    param(
        [Parameter(Mandatory=$true)][string]$FolderPath,
        [Parameter(Mandatory=$true)]$Info
    )
    if (-not (Test-Path -LiteralPath $FolderPath)) {
        throw "Target folder not found: $FolderPath"
    }
    $txtPath = Join-Path $FolderPath "写真情報.txt"
    $nowStr = (Get-Date).ToString("yyyy/MM/dd HH:mm:ss")

    $getProp = {
        param([object]$Obj, [string]$Key, [string]$Fallback = "")
        if ($null -eq $Obj) { return $Fallback }
        if ($Obj -is [System.Collections.IDictionary]) {
            if ($Obj.Contains($Key) -and $null -ne $Obj[$Key]) { return [string]$Obj[$Key] }
        } else {
            $p = $Obj.PSObject.Properties[$Key]
            if ($null -ne $p -and $null -ne $p.Value) { return [string]$p.Value }
        }
        return $Fallback
    }

    $catVal   = & $getProp $Info "Category" (Get-Tag @(0x30A4, 0x30D9, 0x30F3, 0x30C8))
    $dateVal  = & $getProp $Info "DateStr" (& $getProp $Info "ShootDate" "")
    $eventVal = & $getProp $Info "EventName" ""
    $megaVal  = & $getProp $Info "MegaLink" ""
    $gigaVal  = & $getProp $Info "GigaFileLink" (& $getProp $Info "ShareUrl" "")
    $sentVal  = & $getProp $Info "SentStatus" ""
    $sentDone = Get-Tag @(0x9001, 0x4ED8, 0x6E08, 0x307F)
    $sentDoneAlt = Get-Tag @(0x9001, 0x4ED8, 0x6E08)
    $sentNot = Get-Tag @(0x672A, 0x9001, 0x4ED8)
    if ($sentVal -eq $sentDoneAlt) { $sentVal = $sentDone }
    if ([string]::IsNullOrWhiteSpace($sentVal)) {
        $isSentFlag = $false
        if ($Info -is [System.Collections.IDictionary] -and $Info.Contains("IsSent")) { $isSentFlag = [bool]$Info["IsSent"] }
        elseif ($null -ne $Info.PSObject.Properties["IsSent"]) { $isSentFlag = [bool]$Info.IsSent }
        $sentVal = if ($isSentFlag -or -not [string]::IsNullOrWhiteSpace($gigaVal)) { $sentDone } else { $sentNot }
    }
    $memoVal  = & $getProp $Info "Notes" (& $getProp $Info "Comment" "")

    $personsList = New-Object System.Collections.ArrayList
    $rawPersons = if ($Info -is [System.Collections.IDictionary] -and $Info.Contains("Persons")) { $Info["Persons"] }
                  elseif ($null -ne $Info.PSObject.Properties["Persons"]) { $Info.Persons }
                  else { $null }

    $personItems = New-Object System.Collections.ArrayList
    if ($null -ne $rawPersons) {
        if (($rawPersons -is [System.Collections.IDictionary]) -or ($rawPersons -is [PSCustomObject])) {
            [void]$personItems.Add($rawPersons)
        } elseif ($rawPersons -is [System.Collections.IEnumerable] -and -not ($rawPersons -is [string])) {
            foreach ($rpItem in $rawPersons) {
                if ($null -ne $rpItem) {
                    if (($rpItem -is [System.Collections.IDictionary]) -or ($rpItem -is [PSCustomObject])) {
                        [void]$personItems.Add($rpItem)
                    } elseif (($rpItem -is [System.Collections.IEnumerable]) -and -not ($rpItem -is [string])) {
                        foreach ($subRp in $rpItem) {
                            if ($null -ne $subRp) { [void]$personItems.Add($subRp) }
                        }
                    } else {
                        [void]$personItems.Add($rpItem)
                    }
                }
            }
        } else {
            [void]$personItems.Add($rawPersons)
        }
    }

    if ($personItems.Count -gt 0) {
        foreach ($rp in $personItems) {
            [void]$personsList.Add(@{
                Name          = ConvertTo-SafeCleanModelName (& $getProp $rp "Name" "")
                CostumeOrChar = & $getProp $rp "CostumeOrChar" (& $getProp $rp "CharName" "")
                XAccount      = ConvertTo-SafeNormalizedX (& $getProp $rp "XAccount" (& $getProp $rp "XId" ""))
                Comment       = & $getProp $rp "Comment" ""
            })
        }
    } else {
        $rawModels = if ($Info -is [System.Collections.IDictionary] -and $Info.Contains("Models")) { $Info["Models"] }
                     elseif ($null -ne $Info.PSObject.Properties["Models"]) { $Info.Models }
                     else { $null }
        $defCostume = & $getProp $Info "CostumeOrChar" ""
        if ($null -ne $rawModels -and @($rawModels).Count -gt 0) {
            foreach ($rm in $rawModels) {
                $c = & $getProp $rm "CharName" ""
                if ([string]::IsNullOrWhiteSpace($c)) { $c = $defCostume }
                [void]$personsList.Add(@{
                    Name          = ConvertTo-SafeCleanModelName (& $getProp $rm "Name" "")
                    CostumeOrChar = $c
                    XAccount      = ConvertTo-SafeNormalizedX (& $getProp $rm "XId" "")
                    Comment       = ""
                })
            }
        } else {
            [void]$personsList.Add(@{
                Name          = ""
                CostumeOrChar = $defCostume
                XAccount      = ""
                Comment       = ""
            })
        }
    }

    $tCatTag   = Get-Tag @(0x3010, 0x64EE, 0x5F71, 0x533A, 0x5206, 0x3011)
    $tDateTag  = Get-Tag @(0x3010, 0x64EE, 0x5F71, 0x65E5, 0x3011)
    $tEvTag    = Get-Tag @(0x3010, 0x30A4, 0x30D9, 0x30F3, 0x30C8, 0x540D, 0x3011)
    $tSentTag  = Get-Tag @(0x3010, 0x30C7, 0x30FC, 0x30BF, 0x9001, 0x4ED8, 0x72B6, 0x6CC1, 0x3011)
    $tMegaTag  = Get-Tag @(0x3010, 0x004D, 0x0045, 0x0047, 0x30A2, 0x30EA, 0x30F3, 0x30AF, 0x3011)
    $tGigaTag  = Get-Tag @(0x3010, 0x30AE, 0x30AC, 0x30D5, 0x30A1, 0x30A4, 0xEB, 0x4FBF, 0x30EA, 0x30F3, 0x30AF, 0x3011)
    $tMemoTag  = Get-Tag @(0x3010, 0x30E1, 0x30ED, 0x3011)
    $tUpdTag   = Get-Tag @(0x3010, 0x6700, 0x7D42, 0x66F4, 0x65B0, 0x65E5, 0x6642, 0x3011)
    $tNameTag  = Get-Tag @(0x3010, 0x540D, 0x524D, 0x3011)
    $tCosTag   = Get-Tag @(0x3010, 0x8863, 0x88C5, 0x30FB, 0x30AD, 0x30E3, 0x30E9, 0x3011)
    $tXTag     = Get-Tag @(0x3010, 0x0058, 0x3011)
    $tComTag   = Get-Tag @(0x3010, 0x30B3, 0x30E1, 0x30F3, 0x30C8, 0x3011)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("$tCatTag$catVal")
    [void]$sb.AppendLine("$tDateTag$dateVal")
    [void]$sb.AppendLine("$tEvTag$eventVal")
    [void]$sb.AppendLine("$tSentTag$sentVal")
    if (-not [string]::IsNullOrWhiteSpace($megaVal)) {
        [void]$sb.AppendLine("$tMegaTag$megaVal")
    }
    if (-not [string]::IsNullOrWhiteSpace($gigaVal)) {
        [void]$sb.AppendLine("$tGigaTag$gigaVal")
    }
    if (-not [string]::IsNullOrWhiteSpace($memoVal)) {
        [void]$sb.AppendLine("$tMemoTag$memoVal")
    }
    [void]$sb.AppendLine("$tUpdTag$nowStr")
    [void]$sb.AppendLine("----------------------------------------")

    foreach ($p in $personsList) {
        $xUrl = if ([string]::IsNullOrWhiteSpace($p.XAccount)) { "" } else { "https://x.com/" + $p.XAccount.TrimStart('@') }
        [void]$sb.AppendLine("$tNameTag$($p.Name)")
        [void]$sb.AppendLine("$tCosTag$($p.CostumeOrChar)")
        [void]$sb.AppendLine("$tXTag$xUrl")
        [void]$sb.AppendLine("$tComTag$($p.Comment)")
        [void]$sb.AppendLine("----------------------------------------")
    }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($txtPath, $sb.ToString(), $utf8Bom)
    return $txtPath
}

function Read-PhotoInfoFile {
    param([Parameter(Mandatory=$true)][string]$FolderPath, [hashtable]$Config = @{})
    return Read-PhotoInfoTxt -FolderPath $FolderPath -Config $Config
}

function Get-PhotoInfoData {
    param([Parameter(Mandatory=$true)][string]$FolderPath, [hashtable]$Config = @{})
    return Read-PhotoInfoTxt -FolderPath $FolderPath -Config $Config
}

function Save-PhotoInfoData {
    param([Parameter(Mandatory=$true)][string]$FolderPath, [Parameter(Mandatory=$true)]$Data)
    return Write-PhotoInfoTxt -FolderPath $FolderPath -Info $Data
}
