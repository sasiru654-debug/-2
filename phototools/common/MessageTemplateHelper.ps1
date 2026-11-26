#requires -Version 5.1
# ==============================================================================
# MessageTemplateHelper.ps1 - 送付メッセージ定型文管理・差し込み展開エンジン (UTF-8 BOM / CRLF)
# ==============================================================================
Set-StrictMode -Version Latest

function Get-MessageTemplateFilePath {
    param(
        [string]$RootDir = "",
        [hashtable]$Config = @{}
    )
    if ($null -ne $Config -and $Config.ContainsKey("MessageTemplatesPath") -and -not [string]::IsNullOrWhiteSpace([string]$Config["MessageTemplatesPath"])) {
        return [string]$Config["MessageTemplatesPath"]
    }
    if ($null -ne $Config -and $Config.ContainsKey("DataDir") -and -not [string]::IsNullOrWhiteSpace([string]$Config["DataDir"])) {
        return (Join-Path ([string]$Config["DataDir"]) "message_templates.json")
    }
    $resolvedRoot = $RootDir
    if ([string]::IsNullOrWhiteSpace($resolvedRoot) -and $null -ne $Config -and $Config.ContainsKey("RootDir")) {
        $resolvedRoot = [string]$Config["RootDir"]
    }
    if ([string]::IsNullOrWhiteSpace($resolvedRoot)) {
        $commonDir = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { "D:\PhotoTools\common" }
        $resolvedRoot = Split-Path -Parent $commonDir
    }
    return (Join-Path (Join-Path $resolvedRoot "data") "message_templates.json")
}

function Get-MessagePlaceholderDefinitions {
    return @(
        [ordered]@{ Token = "{名前}";         Label = "名前";         Description = "送信先モデルの名前" },
        [ordered]@{ Token = "{Xアカウント}";  Label = "Xアカウント";  Description = "送信先モデルのXアカウント（@付き）" },
        [ordered]@{ Token = "{X_URL}";        Label = "X_URL";        Description = "送信先モデルのXプロフィールURL" },
        [ordered]@{ Token = "{撮影日}";       Label = "撮影日";       Description = "撮影日（例: 2026/11/25）" },
        [ordered]@{ Token = "{撮影区分}";     Label = "撮影区分";     Description = "イベント / 個撮 / 併せ / その他" },
        [ordered]@{ Token = "{イベント名}";   Label = "イベント名";   Description = "イベント名・スタジオ名・併せ名・場所" },
        [ordered]@{ Token = "{衣装}";         Label = "衣装・キャラ"; Description = "送信先モデルの衣装・キャラ名" },
        [ordered]@{ Token = "{データリンク}"; Label = "データリンク"; Description = "ギガファイル便 または MEGAのリンクブロック" },
        [ordered]@{ Token = "{MEGAコメント}"; Label = "MEGAコメント"; Description = "MEGA選択時のみ出力する補足コメント（任意配置）" }
    )
}

function Get-DefaultMegaCommentPresets {
    return @(
        [ordered]@{
            Id   = "mega_detail"
            Name = "丁寧・詳細版（長文）"
            Body = ("※MEGAは会員登録不要でブラウザからご覧いただけます（Xのアプリ内ブラウザでは保存できない場合があるため、SafariやChrome等で開いてください）。`r`n" +
                    "※スマホブラウザでは1枚ずつの保存になります。まとめて保存する場合はPCブラウザまたはMEGAアプリをご利用ください。`r`n" +
                    "※データ整理のため一定期間後にリンクを削除する場合がありますので、お早めに保存をお願いいたします。`r`n" +
                    "※うまく開けない・保存できない場合はギガファイル便等で再送いたしますのでお気軽にご連絡ください。")
        },
        [ordered]@{
            Id   = "mega_balance"
            Name = "バランス版（3行）"
            Body = ("※MEGAは登録不要でブラウザ（Safari/Chrome等）から閲覧・保存できます。`r`n" +
                    "※一括保存はPCブラウザまたはMEGAアプリがスムーズです。お早めに保存をお願いいたします。`r`n" +
                    "※うまく開けない場合はギガファイル便等で再送しますのでお気軽にご連絡ください。")
        },
        [ordered]@{
            Id   = "mega_soft"
            Name = "やわらかめ版（3行）"
            Body = ("※MEGAはアカウント不要でSafari・Chrome等からご覧いただけます（一括保存はPCかアプリが便利です）。`r`n" +
                    "※容量整理のため後日リンクを削除する場合がありますので、お早めに保存をお願いします。`r`n" +
                    "※保存できない場合はギガファイル便等で送り直しますのでお知らせください！")
        },
        [ordered]@{
            Id   = "mega_min"
            Name = "最小限版（2行）"
            Body = ("※MEGAは登録不要でブラウザ（Safari/Chrome等）から保存できます。`r`n" +
                    "※データ整理のため予告なく削除する場合がありますので、お早めに保存をお願いいたします。")
        },
        [ordered]@{
            Id   = "mega_none"
            Name = "コメントなし"
            Body = ""
        }
    )
}

function New-DefaultMessageTemplateStore {
    return [ordered]@{
        Version              = 1
        Templates            = @()
        MegaCommentPresets   = @(Get-DefaultMegaCommentPresets)
        DefaultMegaCommentId = "mega_balance"
    }
}

function ConvertTo-SafeStringProp {
    param(
        [object]$Obj,
        [string]$Key,
        [string]$Fallback = ""
    )
    if ($null -eq $Obj) { return $Fallback }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Key) -and $null -ne $Obj[$Key]) { return [string]$Obj[$Key] }
        return $Fallback
    }
    $p = $Obj.PSObject.Properties[$Key]
    if ($null -ne $p -and $null -ne $p.Value) { return [string]$p.Value }
    return $Fallback
}

function ConvertTo-SafeBoolProp {
    param(
        [object]$Obj,
        [string]$Key,
        [bool]$Fallback = $false
    )
    if ($null -eq $Obj) { return $Fallback }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Key) -and $null -ne $Obj[$Key]) { return [bool]$Obj[$Key] }
        return $Fallback
    }
    $p = $Obj.PSObject.Properties[$Key]
    if ($null -ne $p -and $null -ne $p.Value) { return [bool]$p.Value }
    return $Fallback
}

function Get-MessageTemplateStore {
    param(
        [string]$FilePath = "",
        [string]$RootDir = "",
        [hashtable]$Config = @{}
    )
    $targetPath = if (-not [string]::IsNullOrWhiteSpace($FilePath)) { $FilePath } else { Get-MessageTemplateFilePath -RootDir $RootDir -Config $Config }
    $store = New-DefaultMessageTemplateStore

    if (-not (Test-Path -LiteralPath $targetPath)) {
        return $store
    }

    try {
        $raw = [System.IO.File]::ReadAllText($targetPath, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $store
        }
        $parsed = $raw | ConvertFrom-Json
        if ($null -eq $parsed) {
            return $store
        }

        $tplList = New-Object System.Collections.ArrayList
        $rawTpls = if ($null -ne $parsed.PSObject.Properties["Templates"]) { $parsed.Templates } else { $null }
        if ($null -ne $rawTpls) {
            foreach ($t in @($rawTpls)) {
                if ($null -eq $t) { continue }
                $idVal = ConvertTo-SafeStringProp -Obj $t -Key "Id" -Fallback ([Guid]::NewGuid().ToString("N"))
                $nmVal = ConvertTo-SafeStringProp -Obj $t -Key "Name" -Fallback ""
                if ([string]::IsNullOrWhiteSpace($nmVal)) { continue }
                $catVal = ConvertTo-SafeStringProp -Obj $t -Key "Category" -Fallback "共通"
                $defVal = ConvertTo-SafeBoolProp -Obj $t -Key "IsDefault" -Fallback $false
                $bodyVal = (ConvertTo-SafeStringProp -Obj $t -Key "Body" -Fallback "").Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
                [void]$tplList.Add([ordered]@{
                    Id        = $idVal
                    Name      = $nmVal
                    Category  = $catVal
                    IsDefault = $defVal
                    Body      = $bodyVal
                })
            }
        }
        $store.Templates = @($tplList.ToArray())

        $presetList = New-Object System.Collections.ArrayList
        $rawPresets = if ($null -ne $parsed.PSObject.Properties["MegaCommentPresets"]) { $parsed.MegaCommentPresets } else { $null }
        if ($null -ne $rawPresets -and @($rawPresets).Count -gt 0) {
            foreach ($mp in @($rawPresets)) {
                if ($null -eq $mp) { continue }
                $pId = ConvertTo-SafeStringProp -Obj $mp -Key "Id" -Fallback ([Guid]::NewGuid().ToString("N"))
                $pNm = ConvertTo-SafeStringProp -Obj $mp -Key "Name" -Fallback ""
                if ([string]::IsNullOrWhiteSpace($pNm)) { continue }
                $pBody = (ConvertTo-SafeStringProp -Obj $mp -Key "Body" -Fallback "").Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
                [void]$presetList.Add([ordered]@{
                    Id   = $pId
                    Name = $pNm
                    Body = $pBody
                })
            }
        }
        if ($presetList.Count -gt 0) {
            $store.MegaCommentPresets = @($presetList.ToArray())
        }

        $defMegaId = ConvertTo-SafeStringProp -Obj $parsed -Key "DefaultMegaCommentId" -Fallback ""
        if (-not [string]::IsNullOrWhiteSpace($defMegaId)) {
            $existsDef = $false
            foreach ($mp in @($store.MegaCommentPresets)) {
                if ([string]$mp["Id"] -eq $defMegaId) { $existsDef = $true; break }
            }
            if ($existsDef) {
                $store.DefaultMegaCommentId = $defMegaId
            }
        }
    } catch {
        # JSON破損時は安全な既定構造を返す
    }

    return $store
}

function Save-MessageTemplateStore {
    param(
        [Parameter(Mandatory = $true)]$Store,
        [string]$FilePath = "",
        [string]$RootDir = "",
        [hashtable]$Config = @{}
    )
    $targetPath = if (-not [string]::IsNullOrWhiteSpace($FilePath)) { $FilePath } else { Get-MessageTemplateFilePath -RootDir $RootDir -Config $Config }
    $parentDir = Split-Path -Parent $targetPath
    if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    if (Test-Path -LiteralPath $targetPath) {
        Copy-Item -LiteralPath $targetPath -Destination ($targetPath + ".bak") -Force -ErrorAction SilentlyContinue
    }

    $normTemplates = @()
    $rawTpls = if ($Store -is [System.Collections.IDictionary] -and $Store.Contains("Templates")) { $Store["Templates"] }
               elseif ($null -ne $Store.PSObject.Properties["Templates"]) { $Store.Templates }
               else { @() }
    foreach ($t in @($rawTpls)) {
        if ($null -eq $t) { continue }
        $nm = ConvertTo-SafeStringProp -Obj $t -Key "Name" -Fallback ""
        if ([string]::IsNullOrWhiteSpace($nm)) { continue }
        $normTemplates += [ordered]@{
            Id        = ConvertTo-SafeStringProp -Obj $t -Key "Id" -Fallback ([Guid]::NewGuid().ToString("N"))
            Name      = $nm.Trim()
            Category  = ConvertTo-SafeStringProp -Obj $t -Key "Category" -Fallback "共通"
            IsDefault = ConvertTo-SafeBoolProp -Obj $t -Key "IsDefault" -Fallback $false
            Body      = (ConvertTo-SafeStringProp -Obj $t -Key "Body" -Fallback "").Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
        }
    }

    $normPresets = @()
    $rawPresets = if ($Store -is [System.Collections.IDictionary] -and $Store.Contains("MegaCommentPresets")) { $Store["MegaCommentPresets"] }
                  elseif ($null -ne $Store.PSObject.Properties["MegaCommentPresets"]) { $Store.MegaCommentPresets }
                  else { @(Get-DefaultMegaCommentPresets) }
    foreach ($mp in @($rawPresets)) {
        if ($null -eq $mp) { continue }
        $pNm = ConvertTo-SafeStringProp -Obj $mp -Key "Name" -Fallback ""
        if ([string]::IsNullOrWhiteSpace($pNm)) { continue }
        $normPresets += [ordered]@{
            Id   = ConvertTo-SafeStringProp -Obj $mp -Key "Id" -Fallback ([Guid]::NewGuid().ToString("N"))
            Name = $pNm.Trim()
            Body = (ConvertTo-SafeStringProp -Obj $mp -Key "Body" -Fallback "").Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
        }
    }
    if (@($normPresets).Count -eq 0) {
        $normPresets = @(Get-DefaultMegaCommentPresets)
    }

    $defMegaId = ConvertTo-SafeStringProp -Obj $Store -Key "DefaultMegaCommentId" -Fallback ([string]$normPresets[0]["Id"])

    $payload = [ordered]@{
        Version              = 1
        Templates            = @($normTemplates)
        MegaCommentPresets   = @($normPresets)
        DefaultMegaCommentId = $defMegaId
    }

    $json = $payload | ConvertTo-Json -Depth 6
    $normJson = $json.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($targetPath, $normJson, $utf8Bom)
    return $targetPath
}

function Select-DefaultTemplateForCategory {
    param(
        [Parameter(Mandatory = $true)]$Store,
        [string]$Category = ""
    )
    $tpls = @()
    if ($Store -is [System.Collections.IDictionary] -and $Store.Contains("Templates")) {
        $tpls = @($Store["Templates"])
    } elseif ($null -ne $Store.PSObject.Properties["Templates"]) {
        $tpls = @($Store.Templates)
    }
    if (@($tpls).Count -eq 0) { return $null }

    $cat = if ($null -eq $Category) { "" } else { $Category.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($cat)) {
        foreach ($t in $tpls) {
            if ((ConvertTo-SafeStringProp $t "Category") -eq $cat -and (ConvertTo-SafeBoolProp $t "IsDefault")) {
                return $t
            }
        }
        foreach ($t in $tpls) {
            if ((ConvertTo-SafeStringProp $t "Category") -eq $cat) {
                return $t
            }
        }
    }
    foreach ($t in $tpls) {
        if ((ConvertTo-SafeStringProp $t "Category") -eq "共通" -and (ConvertTo-SafeBoolProp $t "IsDefault")) {
            return $t
        }
    }
    foreach ($t in $tpls) {
        if ((ConvertTo-SafeStringProp $t "Category") -eq "共通") {
            return $t
        }
    }
    return $tpls[0]
}

function ConvertTo-FullWidthDigits {
    param([int]$Number)
    $s = [string]$Number
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        if ($ch -ge '0' -and $ch -le '9') {
            $fw = [char](0xFF10 + ([int]$ch - [int][char]'0'))
            [void]$sb.Append($fw)
        } else {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString()
}

function Format-GigaFileExpiryText {
    param(
        [string]$RawExpiry = "",
        [int]$LifetimeDays = 0,
        [datetime]$BaseDate = [datetime]::MinValue
    )
    $s = if ($null -eq $RawExpiry) { "" } else { $RawExpiry.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($s)) {
        if ($s -match '^(\d{4})[/\-\.年](\d{1,2})[/\-\.月](\d{1,2})日?(?:まで)?$') {
            $y = [int]$Matches[1]
            $m = [int]$Matches[2]
            $d = [int]$Matches[3]
            return ("{0:D4}/{1:D2}/{2:D2}まで" -f $y, $m, $d)
        }
        if ($s -match '^(\d+)日$') {
            $days = [int]$Matches[1]
            $ref = if ($BaseDate -ne [datetime]::MinValue) { $BaseDate } else { Get-Date }
            return ($ref.AddDays($days).ToString("yyyy/MM/dd") + "まで")
        }
        if ($s.EndsWith("まで")) { return $s }
        return ($s + "まで")
    }
    if ($LifetimeDays -gt 0) {
        $ref = if ($BaseDate -ne [datetime]::MinValue) { $BaseDate } else { Get-Date }
        return ($ref.AddDays($LifetimeDays).ToString("yyyy/MM/dd") + "まで")
    }
    return ""
}

function Format-ShootDateDisplay {
    param([string]$RawDate = "")
    if ([string]::IsNullOrWhiteSpace($RawDate)) { return "" }
    $s = $RawDate.Trim()
    if ($s -match '^(\d{4})[-_/.](\d{1,2})[-_/.](\d{1,2})') {
        return ("{0:D4}/{1:D2}/{2:D2}" -f [int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
    }
    if ($s -match '^(\d{4})(\d{2})(\d{2})') {
        return ("{0:D4}/{1:D2}/{2:D2}" -f [int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
    }
    return $s
}

function ConvertTo-NormXForMatch {
    param([string]$RawX = "")
    if ([string]::IsNullOrWhiteSpace($RawX)) { return "" }
    $s = $RawX.Trim()
    if ($s -match '(?:https?://)?(?:www\.)?(?:x\.com|twitter\.com)/([A-Za-z0-9_]+)') {
        return ("@" + $Matches[1]).ToLowerInvariant()
    }
    $s = $s.TrimStart('@', [char]0xFF20)
    if ($s -match '^([A-Za-z0-9_]+)') {
        return ("@" + $Matches[1]).ToLowerInvariant()
    }
    return ""
}

function Get-CompanionsLineForFolder {
    param(
        [array]$Persons = @(),
        [string]$RecipientName = "",
        [string]$RecipientXAccount = ""
    )
    $recXNorm = ConvertTo-NormXForMatch -RawX $RecipientXAccount
    $recNameClean = if ($null -eq $RecipientName) { "" } else { $RecipientName.Trim() }

    $validPersons = New-Object System.Collections.ArrayList
    foreach ($p in @($Persons)) {
        if ($null -eq $p) { continue }
        $pn = ConvertTo-SafeStringProp -Obj $p -Key "Name" -Fallback ""
        $pc = ConvertTo-SafeStringProp -Obj $p -Key "CostumeOrChar" -Fallback (ConvertTo-SafeStringProp -Obj $p -Key "CharName" -Fallback "")
        $px = ConvertTo-SafeStringProp -Obj $p -Key "XAccount" -Fallback (ConvertTo-SafeStringProp -Obj $p -Key "XId" -Fallback "")
        if ([string]::IsNullOrWhiteSpace($pn) -and [string]::IsNullOrWhiteSpace($pc) -and [string]::IsNullOrWhiteSpace($px)) {
            continue
        }
        [void]$validPersons.Add(@{
            Name          = $pn.Trim()
            CostumeOrChar = $pc.Trim()
            XNorm         = (ConvertTo-NormXForMatch -RawX $px)
            XRaw          = $px.Trim()
        })
    }

    if ($validPersons.Count -lt 2) { return "" }

    $companions = New-Object System.Collections.Generic.List[string]
    $matchedSelfOnce = $false
    foreach ($vp in $validPersons) {
        $isSelf = $false
        if (-not $matchedSelfOnce) {
            if (-not [string]::IsNullOrWhiteSpace($recXNorm) -and -not [string]::IsNullOrWhiteSpace($vp.XNorm) -and ($vp.XNorm -eq $recXNorm)) {
                $isSelf = $true
            } elseif (-not [string]::IsNullOrWhiteSpace($recNameClean) -and -not [string]::IsNullOrWhiteSpace($vp.Name) -and ($vp.Name -ieq $recNameClean)) {
                $isSelf = $true
            }
            if ($isSelf) {
                $matchedSelfOnce = $true
                continue
            }
        }
        $dispName = if (-not [string]::IsNullOrWhiteSpace($vp.Name)) { $vp.Name } elseif (-not [string]::IsNullOrWhiteSpace($vp.XRaw)) { $vp.XRaw } else { "" }
        $dispChar = $vp.CostumeOrChar
        if (-not [string]::IsNullOrWhiteSpace($dispName) -and -not [string]::IsNullOrWhiteSpace($dispChar)) {
            [void]$companions.Add("${dispName}（${dispChar}）")
        } elseif (-not [string]::IsNullOrWhiteSpace($dispName)) {
            [void]$companions.Add($dispName)
        } elseif (-not [string]::IsNullOrWhiteSpace($dispChar)) {
            [void]$companions.Add("（${dispChar}）")
        }
    }

    if ($companions.Count -eq 0) { return "" }
    return ($companions -join "、")
}

function Build-DataLinkSection {
    param(
        [ValidateSet("GigaFile", "MEGA")]
        [string]$LinkType = "GigaFile",
        [array]$FolderEntries = @(),
        [string]$RecipientName = "",
        [string]$RecipientXAccount = "",
        [string]$OverrideDlPassword = "",
        [string]$OverrideExpiryText = "",
        [string]$MegaCommentText = "",
        [bool]$AppendMegaComment = $false
    )

    $linkItems = New-Object System.Collections.ArrayList
    $hasAnyMultiPerson = $false

    foreach ($entry in @($FolderEntries)) {
        if ($null -eq $entry) { continue }
        $persons = @()
        if ($entry -is [System.Collections.IDictionary] -and $entry.Contains("Persons")) {
            $persons = @($entry["Persons"])
        } elseif ($null -ne $entry.PSObject.Properties["Persons"]) {
            $persons = @($entry.Persons)
        }

        $nonEmptyPersons = 0
        foreach ($p in $persons) {
            if ($null -eq $p) { continue }
            $pn = ConvertTo-SafeStringProp -Obj $p -Key "Name" -Fallback ""
            $px = ConvertTo-SafeStringProp -Obj $p -Key "XAccount" -Fallback (ConvertTo-SafeStringProp -Obj $p -Key "XId" -Fallback "")
            $pc = ConvertTo-SafeStringProp -Obj $p -Key "CostumeOrChar" -Fallback (ConvertTo-SafeStringProp -Obj $p -Key "CharName" -Fallback "")
            if (-not [string]::IsNullOrWhiteSpace($pn) -or -not [string]::IsNullOrWhiteSpace($px) -or -not [string]::IsNullOrWhiteSpace($pc)) {
                $nonEmptyPersons++
            }
        }
        $isMultiPerson = ($nonEmptyPersons -ge 2)
        if ($isMultiPerson) { $hasAnyMultiPerson = $true }

        $companionLine = if ($isMultiPerson) {
            Get-CompanionsLineForFolder -Persons $persons -RecipientName $RecipientName -RecipientXAccount $RecipientXAccount
        } else {
            ""
        }

        if ($LinkType -eq "GigaFile") {
            $urls = New-Object System.Collections.Generic.List[string]
            if ($entry -is [System.Collections.IDictionary] -and $entry.Contains("GigaFileUrls") -and $null -ne $entry["GigaFileUrls"]) {
                foreach ($u in @($entry["GigaFileUrls"])) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$u)) { [void]$urls.Add(([string]$u).Trim()) }
                }
            }
            $singleUrl = ConvertTo-SafeStringProp -Obj $entry -Key "GigaFileLink" -Fallback (ConvertTo-SafeStringProp -Obj $entry -Key "ShareUrl" -Fallback "")
            if ($urls.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($singleUrl)) {
                foreach ($part in ($singleUrl -split '[\r\n]+')) {
                    $tp = $part.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($tp)) { [void]$urls.Add($tp) }
                }
            }

            $pw = if (-not [string]::IsNullOrWhiteSpace($OverrideDlPassword)) {
                $OverrideDlPassword.Trim()
            } else {
                (ConvertTo-SafeStringProp -Obj $entry -Key "DlPassword" -Fallback "").Trim()
            }

            $rawExp = if (-not [string]::IsNullOrWhiteSpace($OverrideExpiryText)) {
                $OverrideExpiryText.Trim()
            } else {
                (ConvertTo-SafeStringProp -Obj $entry -Key "GigaFileExpiry" -Fallback "").Trim()
            }
            $expFormatted = Format-GigaFileExpiryText -RawExpiry $rawExp

            foreach ($u in $urls) {
                [void]$linkItems.Add(@{
                    Url           = $u
                    DlPassword    = $pw
                    ExpiryText    = $expFormatted
                    IsMultiPerson = $isMultiPerson
                    CompanionLine = $companionLine
                })
            }
        } else {
            $megaUrl = (ConvertTo-SafeStringProp -Obj $entry -Key "MegaLink" -Fallback "").Trim()
            if (-not [string]::IsNullOrWhiteSpace($megaUrl)) {
                [void]$linkItems.Add(@{
                    Url           = $megaUrl
                    DlPassword    = ""
                    ExpiryText    = ""
                    IsMultiPerson = $isMultiPerson
                    CompanionLine = $companionLine
                })
            }
        }
    }

    $useHeaders = ($linkItems.Count -gt 1) -or $hasAnyMultiPerson
    $soloCounter = 0
    $multiCounter = 0
    $blocks = New-Object System.Collections.Generic.List[string]

    foreach ($item in $linkItems) {
        $lines = New-Object System.Collections.Generic.List[string]
        if ($useHeaders) {
            if ($item.IsMultiPerson) {
                $multiCounter++
                [void]$lines.Add("複数リンク" + (ConvertTo-FullWidthDigits -Number $multiCounter))
                if (-not [string]::IsNullOrWhiteSpace($item.CompanionLine)) {
                    [void]$lines.Add($item.CompanionLine)
                }
            } else {
                $soloCounter++
                [void]$lines.Add("個撮リンク" + (ConvertTo-FullWidthDigits -Number $soloCounter))
            }
        }

        [void]$lines.Add($item.Url)

        if ($LinkType -eq "GigaFile") {
            if (-not [string]::IsNullOrWhiteSpace($item.DlPassword)) {
                [void]$lines.Add("DLパスワード：" + $item.DlPassword)
            }
            if (-not [string]::IsNullOrWhiteSpace($item.ExpiryText)) {
                [void]$lines.Add("保持期間：" + $item.ExpiryText)
            }
        }

        [void]$blocks.Add(($lines -join "`r`n"))
    }

    $resultText = $blocks -join "`r`n`r`n"

    if ($LinkType -eq "MEGA" -and $AppendMegaComment -and -not [string]::IsNullOrWhiteSpace($MegaCommentText)) {
        $trimmedComment = $MegaCommentText.Trim().Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
        if ([string]::IsNullOrWhiteSpace($resultText)) {
            $resultText = $trimmedComment
        } else {
            $resultText = $resultText + "`r`n`r`n" + $trimmedComment
        }
    }

    return $resultText
}

function Render-DeliveryMessage {
    param(
        [Parameter(Mandatory = $true)][string]$TemplateBody,
        [ValidateSet("GigaFile", "MEGA")]
        [string]$LinkType = "GigaFile",
        [array]$FolderEntries = @(),
        [string]$RecipientName = "",
        [string]$RecipientXAccount = "",
        [string]$RecipientXUrl = "",
        [string]$OverrideDlPassword = "",
        [string]$OverrideExpiryText = "",
        [string]$MegaCommentText = ""
    )

    $body = $TemplateBody.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    $firstEntry = if (@($FolderEntries).Count -gt 0) { $FolderEntries[0] } else { $null }

    $shootDate = Format-ShootDateDisplay -RawDate (ConvertTo-SafeStringProp -Obj $firstEntry -Key "DateStr" -Fallback (ConvertTo-SafeStringProp -Obj $firstEntry -Key "ShootDate" -Fallback ""))
    $category  = ConvertTo-SafeStringProp -Obj $firstEntry -Key "Category" -Fallback ""
    $eventName = ConvertTo-SafeStringProp -Obj $firstEntry -Key "EventName" -Fallback ""

    $recXNorm = ConvertTo-NormXForMatch -RawX $RecipientXAccount
    $recXDisp = if (-not [string]::IsNullOrWhiteSpace($RecipientXAccount)) {
        if ($RecipientXAccount.Trim().StartsWith("@")) { $RecipientXAccount.Trim() } else { "@" + $RecipientXAccount.Trim().TrimStart([char]0xFF20) }
    } else { "" }
    $recXUrlDisp = if (-not [string]::IsNullOrWhiteSpace($RecipientXUrl)) {
        $RecipientXUrl.Trim()
    } elseif (-not [string]::IsNullOrWhiteSpace($recXDisp)) {
        "https://x.com/" + $recXDisp.TrimStart('@')
    } else { "" }

    # 送信先モデルの衣装・キャラ一覧を重複排除して収集
    $costumes = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($FolderEntries)) {
        if ($null -eq $entry) { continue }
        $persons = if ($entry -is [System.Collections.IDictionary] -and $entry.Contains("Persons")) { @($entry["Persons"]) }
                   elseif ($null -ne $entry.PSObject.Properties["Persons"]) { @($entry.Persons) }
                   else { @() }
        $matchedCos = ""
        foreach ($p in $persons) {
            if ($null -eq $p) { continue }
            $px = ConvertTo-NormXForMatch -RawX (ConvertTo-SafeStringProp -Obj $p -Key "XAccount" -Fallback (ConvertTo-SafeStringProp -Obj $p -Key "XId" -Fallback ""))
            $pn = (ConvertTo-SafeStringProp -Obj $p -Key "Name" -Fallback "").Trim()
            $pc = (ConvertTo-SafeStringProp -Obj $p -Key "CostumeOrChar" -Fallback (ConvertTo-SafeStringProp -Obj $p -Key "CharName" -Fallback "")).Trim()
            if ((-not [string]::IsNullOrWhiteSpace($recXNorm) -and $px -eq $recXNorm) -or
                (-not [string]::IsNullOrWhiteSpace($RecipientName) -and $pn -ieq $RecipientName.Trim())) {
                if (-not [string]::IsNullOrWhiteSpace($pc)) {
                    $matchedCos = $pc
                    break
                }
            }
        }
        if ([string]::IsNullOrWhiteSpace($matchedCos)) {
            $matchedCos = (ConvertTo-SafeStringProp -Obj $entry -Key "CostumeOrChar" -Fallback "").Trim()
        }
        if (-not [string]::IsNullOrWhiteSpace($matchedCos) -and -not $costumes.Contains($matchedCos)) {
            [void]$costumes.Add($matchedCos)
        }
    }
    $costumeDisp = $costumes -join " / "

    $hasExplicitMegaCommentToken = $body.Contains("{MEGAコメント}")
    $megaCommentEffective = if ($LinkType -eq "MEGA") {
        $MegaCommentText.Trim().Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    } else {
        ""
    }

    $dataLinkText = Build-DataLinkSection `
        -LinkType $LinkType `
        -FolderEntries $FolderEntries `
        -RecipientName $RecipientName `
        -RecipientXAccount $recXDisp `
        -OverrideDlPassword $OverrideDlPassword `
        -OverrideExpiryText $OverrideExpiryText `
        -MegaCommentText $megaCommentEffective `
        -AppendMegaComment (-not $hasExplicitMegaCommentToken)

    $rendered = $body
    $rendered = $rendered.Replace("{名前}", $RecipientName.Trim())
    $rendered = $rendered.Replace("{Xアカウント}", $recXDisp)
    $rendered = $rendered.Replace("{X_URL}", $recXUrlDisp)
    $rendered = $rendered.Replace("{撮影日}", $shootDate)
    $rendered = $rendered.Replace("{撮影区分}", $category)
    $rendered = $rendered.Replace("{イベント名}", $eventName)
    $rendered = $rendered.Replace("{衣装}", $costumeDisp)
    $rendered = $rendered.Replace("{データリンク}", $dataLinkText)

    if ($hasExplicitMegaCommentToken) {
        if ([string]::IsNullOrWhiteSpace($megaCommentEffective)) {
            # 単独行の {MEGAコメント} は行ごと綺麗に除去
            $rendered = [regex]::Replace($rendered, '(?m)^[ \t]*\{MEGAコメント\}[ \t]*\r?\n?', '')
            $rendered = $rendered.Replace("{MEGAコメント}", "")
        } else {
            $rendered = $rendered.Replace("{MEGAコメント}", $megaCommentEffective)
        }
    }

    $rendered = $rendered.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    return $rendered.TrimEnd("`r", "`n")
}
