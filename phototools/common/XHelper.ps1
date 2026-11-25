#requires -Version 5.1
# ==============================================================================
# XHelper.ps1 - X表示名4段階取得・履歴JSON管理・検索ダイアログ (UTF-8 BOM / CRLF)
# ==============================================================================

function Normalize-XAccount {
    param([string]$Raw)
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

function Clean-XDisplayName {
    param([string]$RawName)
    if ([string]::IsNullOrWhiteSpace($RawName)) { return "" }
    $n = [System.Net.WebUtility]::HtmlDecode($RawName).Trim()
    $n = $n -replace '\s*\(@[A-Za-z0-9_]+\)\s*/\s*X\s*$', ''
    $n = $n -replace '\s*\(@[A-Za-z0-9_]+\)\s*$', ''
    $n = $n -replace '\s*/\s*X\s*$', ''
    $n = $n -replace '\s*on\s+X\s*$', ''
    $idxHalf = $n.IndexOf('@')
    $idxFull = $n.IndexOf('＠')
    $cut = -1
    if ($idxHalf -ge 0 -and $idxFull -ge 0) { $cut = [Math]::Min($idxHalf, $idxFull) }
    elseif ($idxHalf -ge 0) { $cut = $idxHalf }
    elseif ($idxFull -ge 0) { $cut = $idxFull }
    if ($cut -gt 0) {
        $n = $n.Substring(0, $cut).Trim()
    }
    return $n.Trim()
}

function Invoke-XUtf8Get {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutMs = 8000
    )
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = "GET"
    $req.Timeout = $TimeoutMs
    $req.ReadWriteTimeout = $TimeoutMs
    $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    $req.Headers.Add("Accept-Language", "ja,en-US;q=0.9,en;q=0.8")
    $req.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $resp = $req.GetResponse()
    try {
        $stream = $resp.GetResponseStream()
        try {
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
            try {
                return $reader.ReadToEnd()
            } finally {
                $reader.Close()
            }
        } finally {
            $stream.Close()
        }
    } finally {
        $resp.Close()
    }
}

function Get-XPropValue {
    param(
        [object]$Obj,
        [string]$Key,
        [object]$DefaultVal = $null
    )
    if ($null -eq $Obj -or [string]::IsNullOrWhiteSpace($Key)) { return $DefaultVal }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Key)) { return $Obj[$Key] }
        return $DefaultVal
    }
    $prop = $Obj.PSObject.Properties[$Key]
    if ($null -ne $prop) { return $prop.Value }
    return $DefaultVal
}

function Write-XHelperLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    try {
        if (Get-Command Write-LogInfo -ErrorAction SilentlyContinue) {
            Write-LogInfo -Message $Message -ModuleName "XHelper" -Level $Level | Out-Null
        }
    } catch {}
}

function Get-XDisplayName {
    param(
        [Parameter(Position = 0)]
        [string]$Account,
        [Parameter(Position = 1)]
        [hashtable]$Config = @{}
    )

    $norm = Normalize-XAccount $Account
    if ([string]::IsNullOrWhiteSpace($norm)) { return "" }
    $id = $norm.TrimStart('@')
    $fallbackName = ""

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    } catch {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    }

    # 1. X / Twitter oEmbed API
    try {
        $oembedUrl = "https://publish.twitter.com/oembed?url=" + [System.Uri]::EscapeDataString("https://x.com/$id")
        $rawJson = Invoke-XUtf8Get -Url $oembedUrl -TimeoutMs 8000
        if (-not [string]::IsNullOrWhiteSpace($rawJson)) {
            $resp = $rawJson | ConvertFrom-Json
            $authorRaw = [string](Get-XPropValue -Obj $resp -Key "author_name" -DefaultVal "")
            if (-not [string]::IsNullOrWhiteSpace($authorRaw)) {
                $cleaned = Clean-XDisplayName $authorRaw
                if (-not [string]::IsNullOrWhiteSpace($cleaned) -and $cleaned -ne $id) {
                    Write-XHelperLog "X表示名取得成功 (oEmbed): $norm -> $cleaned"
                    return $cleaned
                }
                if (-not [string]::IsNullOrWhiteSpace($cleaned)) {
                    $fallbackName = $cleaned
                }
            }
        }
    } catch {
        Write-XHelperLog "X表示名取得 Stage1(oEmbed) 失敗 ($norm): $($_.Exception.Message)" "WARN"
    }

    # 2. fxtwitter public profile API
    try {
        $fxUrl = "https://api.fxtwitter.com/$id"
        $fxJson = Invoke-XUtf8Get -Url $fxUrl -TimeoutMs 8000
        if (-not [string]::IsNullOrWhiteSpace($fxJson)) {
            $fxResp = $fxJson | ConvertFrom-Json
            $fxUser = Get-XPropValue -Obj $fxResp -Key "user" -DefaultVal $null
            $fxNameRaw = [string](Get-XPropValue -Obj $fxUser -Key "name" -DefaultVal "")
            if (-not [string]::IsNullOrWhiteSpace($fxNameRaw)) {
                $cleaned = Clean-XDisplayName $fxNameRaw
                if (-not [string]::IsNullOrWhiteSpace($cleaned)) {
                    Write-XHelperLog "X表示名取得成功 (fxtwitter): $norm -> $cleaned"
                    return $cleaned
                }
            }
        }
    } catch {
        Write-XHelperLog "X表示名取得 Stage2(fxtwitter) 失敗 ($norm): $($_.Exception.Message)" "WARN"
    }

    # 3. vxtwitter public profile API
    try {
        $vxUrl = "https://api.vxtwitter.com/$id"
        $vxJson = Invoke-XUtf8Get -Url $vxUrl -TimeoutMs 8000
        if (-not [string]::IsNullOrWhiteSpace($vxJson)) {
            $vxResp = $vxJson | ConvertFrom-Json
            $vxNameRaw = [string](Get-XPropValue -Obj $vxResp -Key "user_name" -DefaultVal "")
            if (-not [string]::IsNullOrWhiteSpace($vxNameRaw)) {
                $cleaned = Clean-XDisplayName $vxNameRaw
                if (-not [string]::IsNullOrWhiteSpace($cleaned)) {
                    Write-XHelperLog "X表示名取得成功 (vxtwitter): $norm -> $cleaned"
                    return $cleaned
                }
            }
        }
    } catch {
        Write-XHelperLog "X表示名取得 Stage3(vxtwitter) 失敗 ($norm): $($_.Exception.Message)" "WARN"
    }

    # 4. Direct HTML title / og:title fallback
    try {
        $pageUrl = "https://x.com/$id"
        $html = Invoke-XUtf8Get -Url $pageUrl -TimeoutMs 8000
        if (-not [string]::IsNullOrWhiteSpace($html)) {
            $ogRaw = ""
            if ($html -match '<meta[^>]+property=["'']og:title["''][^>]+content=["'']([^"'']+)["'']') {
                $ogRaw = $Matches[1]
            } elseif ($html -match '<meta[^>]+content=["'']([^"'']+)["''][^>]+property=["'']og:title["'']') {
                $ogRaw = $Matches[1]
            }
            if (-not [string]::IsNullOrWhiteSpace($ogRaw)) {
                $cleaned = Clean-XDisplayName $ogRaw
                if (-not [string]::IsNullOrWhiteSpace($cleaned) -and $cleaned -ne "X") {
                    Write-XHelperLog "X表示名取得成功 (HTML og:title): $norm -> $cleaned"
                    return $cleaned
                }
            }
            if ($html -match '<title[^>]*>([^<]+)</title>') {
                $cleaned = Clean-XDisplayName $Matches[1]
                if (-not [string]::IsNullOrWhiteSpace($cleaned) -and $cleaned -ne "X") {
                    Write-XHelperLog "X表示名取得成功 (HTML title): $norm -> $cleaned"
                    return $cleaned
                }
            }
        }
    } catch {
        Write-XHelperLog "X表示名取得 Stage4(HTML) 失敗 ($norm): $($_.Exception.Message)" "WARN"
    }

    if (-not [string]::IsNullOrWhiteSpace($fallbackName)) {
        Write-XHelperLog "X表示名取得フォールバック使用 ($norm): $fallbackName" "WARN"
        return $fallbackName
    }
    Write-XHelperLog "X表示名取得全段階失敗 ($norm)" "WARN"
    return ""
}

function Get-XHistoryFilePath {
    param([hashtable]$Config = @{})
    if ($null -ne $Config) {
        if ($Config.ContainsKey("XHistoryPath") -and -not [string]::IsNullOrWhiteSpace([string]$Config["XHistoryPath"])) {
            return [string]$Config["XHistoryPath"]
        }
        if ($Config.ContainsKey("HistoryPath") -and -not [string]::IsNullOrWhiteSpace([string]$Config["HistoryPath"])) {
            return [string]$Config["HistoryPath"]
        }
        if ($Config.ContainsKey("DataDir") -and -not [string]::IsNullOrWhiteSpace([string]$Config["DataDir"])) {
            return (Join-Path ([string]$Config["DataDir"]) "x_history.json")
        }
        if ($Config.ContainsKey("RootDir") -and -not [string]::IsNullOrWhiteSpace([string]$Config["RootDir"])) {
            return (Join-Path ([string]$Config["RootDir"]) "data\x_history.json")
        }
    }
    $root = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $PSScriptRoot } else { "D:\PhotoTools" }
    return (Join-Path $root "data\x_history.json")
}

function Ensure-XHistoryFile {
    param([string]$HistoryPath)
    if ([string]::IsNullOrWhiteSpace($HistoryPath)) { return }
    try {
        $dir = [System.IO.Path]::GetDirectoryName($HistoryPath)
        if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        if (-not (Test-Path -LiteralPath $HistoryPath)) {
            $utf8Bom = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($HistoryPath, "[]`r`n", $utf8Bom)
        }
    } catch {}
}

function Read-XHistoryList {
    param([string]$HistoryPath)
    $list = New-Object System.Collections.Generic.List[hashtable]
    if ([string]::IsNullOrWhiteSpace($HistoryPath)) {
        return
    }
    if (-not (Test-Path -LiteralPath $HistoryPath)) {
        Ensure-XHistoryFile -HistoryPath $HistoryPath
        return
    }
    try {
        $raw = Get-Content -LiteralPath $HistoryPath -Encoding UTF8 -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return }
        $parsed = $raw | ConvertFrom-Json
        if ($null -eq $parsed) { return }

        $items = @()
        if ($parsed -is [System.Array]) {
            $items = @($parsed)
        } elseif ($parsed -is [System.Collections.IDictionary]) {
            if ($parsed.Contains("items") -and $null -ne $parsed["items"]) { $items = @($parsed["items"]) }
            elseif ($parsed.Contains("history") -and $null -ne $parsed["history"]) { $items = @($parsed["history"]) }
            else { $items = @($parsed) }
        } elseif ($null -ne $parsed.PSObject.Properties["items"] -and $null -ne $parsed.items) {
            $items = @($parsed.items)
        } elseif ($null -ne $parsed.PSObject.Properties["history"] -and $null -ne $parsed.history) {
            $items = @($parsed.history)
        } else {
            $items = @($parsed)
        }

        foreach ($it in $items) {
            if ($null -eq $it) { continue }
            $acc = ""
            $nm  = ""
            $upd = ""
            $datesList = New-Object System.Collections.Generic.List[string]

            $addDateVal = {
                param([object]$Val)
                if ($null -eq $Val) { return }
                if (($Val -is [System.Array] -or $Val -is [System.Collections.IList]) -or ($Val -is [System.Collections.IEnumerable] -and -not ($Val -is [string]))) {
                    foreach ($d in $Val) {
                        if ($null -eq $d) { continue }
                        $ds = ([string]$d).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($ds) -and -not $datesList.Contains($ds)) {
                            $datesList.Add($ds)
                        }
                    }
                } else {
                    $ds = ([string]$Val).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($ds) -and -not $datesList.Contains($ds)) {
                        $datesList.Add($ds)
                    }
                }
            }

            if ($it -is [System.Collections.IDictionary]) {
                if ($it.Contains("account") -and $null -ne $it["account"]) { $acc = [string]$it["account"] }
                elseif ($it.Contains("XAccount") -and $null -ne $it["XAccount"]) { $acc = [string]$it["XAccount"] }
                if ($it.Contains("name") -and $null -ne $it["name"]) { $nm = [string]$it["name"] }
                elseif ($it.Contains("Name") -and $null -ne $it["Name"]) { $nm = [string]$it["Name"] }
                if ($it.Contains("updatedAt") -and $null -ne $it["updatedAt"]) { $upd = [string]$it["updatedAt"] }
                if ($it.Contains("dates"))    { & $addDateVal $it["dates"] }
                if ($it.Contains("lastDate")) { & $addDateVal $it["lastDate"] }
                if ($it.Contains("date"))     { & $addDateVal $it["date"] }
                if ($it.Contains("DateStr"))  { & $addDateVal $it["DateStr"] }
            } else {
                $pAcc = Get-XPropValue -Obj $it -Key "account" -DefaultVal (Get-XPropValue -Obj $it -Key "XAccount" -DefaultVal "")
                $pNm  = Get-XPropValue -Obj $it -Key "name"    -DefaultVal (Get-XPropValue -Obj $it -Key "Name" -DefaultVal "")
                $pUpd = Get-XPropValue -Obj $it -Key "updatedAt" -DefaultVal ""
                $acc = if ($null -eq $pAcc) { "" } else { [string]$pAcc }
                $nm  = if ($null -eq $pNm)  { "" } else { [string]$pNm }
                $upd = if ($null -eq $pUpd) { "" } else { [string]$pUpd }
                & $addDateVal (Get-XPropValue -Obj $it -Key "dates" -DefaultVal $null)
                & $addDateVal (Get-XPropValue -Obj $it -Key "lastDate" -DefaultVal $null)
                & $addDateVal (Get-XPropValue -Obj $it -Key "date" -DefaultVal $null)
                & $addDateVal (Get-XPropValue -Obj $it -Key "DateStr" -DefaultVal $null)
            }

            $normAcc = Normalize-XAccount $acc
            $cleanNm = Clean-XDisplayName $nm
            $sortedDates = if ($datesList.Count -gt 0) { @($datesList | Sort-Object -Descending) } else { @() }
            $latestDate = if (@($sortedDates).Count -gt 0) { [string]$sortedDates[0] } else { "" }

            if (-not [string]::IsNullOrWhiteSpace($normAcc) -or -not [string]::IsNullOrWhiteSpace($cleanNm)) {
                $list.Add(@{
                    account   = $normAcc
                    name      = $cleanNm
                    dates     = $sortedDates
                    lastDate  = $latestDate
                    date      = $latestDate
                    updatedAt = $upd
                })
            }
        }
    } catch {
        if (Get-Command Write-LogError -ErrorAction SilentlyContinue) {
            Write-LogError -Message "X履歴読込エラー" -ErrorRecord $_ -ModuleName "XHelper" -Context @{ HistoryPath = $HistoryPath } | Out-Null
        }
    }
    if ($list.Count -eq 0) { return }
    return ([object[]]$list.ToArray())
}

function Save-XHistory {
    param(
        [Parameter(Position = 0)]
        [string]$Account,
        [Parameter(Position = 1)]
        [string]$Name,
        [Parameter(Position = 2)]
        [hashtable]$Config = @{},
        [Parameter(Position = 3)]
        [string]$DateStr = ""
    )

    $histPath = Get-XHistoryFilePath -Config $Config
    Ensure-XHistoryFile -HistoryPath $histPath

    $normAcc = Normalize-XAccount $Account
    $cleanNm = Clean-XDisplayName $Name
    if ([string]::IsNullOrWhiteSpace($normAcc) -and [string]::IsNullOrWhiteSpace($cleanNm)) { return }

    $list = @(Read-XHistoryList -HistoryPath $histPath | Where-Object { $null -ne $_ })
    $nowStr = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $dateVal = if ($null -eq $DateStr) { "" } else { $DateStr.Trim() }

    $mergedDates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($dateVal)) {
        $mergedDates.Add($dateVal)
    }

    $others = New-Object System.Collections.Generic.List[hashtable]
    foreach ($item in $list) {
        if ($null -eq $item) { continue }
        $itAccRaw = Get-XPropValue -Obj $item -Key "account" -DefaultVal ""
        $itNmRaw  = Get-XPropValue -Obj $item -Key "name" -DefaultVal ""
        $itDates  = Get-XPropValue -Obj $item -Key "dates" -DefaultVal @()
        $itLast   = Get-XPropValue -Obj $item -Key "lastDate" -DefaultVal ""
        $itUpd    = Get-XPropValue -Obj $item -Key "updatedAt" -DefaultVal ""

        $itAcc = if ($null -eq $itAccRaw) { "" } else { [string]$itAccRaw }
        $itNm  = if ($null -eq $itNmRaw)  { "" } else { [string]$itNmRaw }
        $itLastStr = if ($null -eq $itLast) { "" } else { [string]$itLast }
        $itUpdStr  = if ($null -eq $itUpd)  { "" } else { [string]$itUpd }

        $sameAcc = (-not [string]::IsNullOrWhiteSpace($normAcc)) -and ($itAcc -ieq $normAcc)
        $sameNm  = ([string]::IsNullOrWhiteSpace($normAcc)) -and ($itNm -ieq $cleanNm)
        if ($sameAcc -or $sameNm) {
            if ($null -ne $itDates) {
                foreach ($d in @($itDates)) {
                    if ($null -eq $d) { continue }
                    $ds = ([string]$d).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($ds) -and -not $mergedDates.Contains($ds)) {
                        $mergedDates.Add($ds)
                    }
                }
            }
            if ([string]::IsNullOrWhiteSpace($cleanNm) -and -not [string]::IsNullOrWhiteSpace($itNm)) {
                $cleanNm = $itNm
            }
            continue
        }
        $cleanDatesArr = @()
        if ($null -ne $itDates) {
            $cleanDatesArr = @($itDates | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
        }
        $others.Add(@{
            account   = $itAcc
            name      = $itNm
            dates     = $cleanDatesArr
            lastDate  = $itLastStr
            updatedAt = $itUpdStr
        })
    }

    $sortedMerged = if ($mergedDates.Count -gt 0) { @($mergedDates | Sort-Object -Descending) } else { @() }
    $latest = if (@($sortedMerged).Count -gt 0) { [string]$sortedMerged[0] } else { "" }

    $outList = New-Object System.Collections.Generic.List[hashtable]
    $outList.Add(@{
        account   = $normAcc
        name      = $cleanNm
        dates     = $sortedMerged
        lastDate  = $latest
        updatedAt = $nowStr
    })
    foreach ($o in $others) {
        if ($null -ne $o) { $outList.Add($o) }
    }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $json = ConvertTo-Json -InputObject ([object[]]$outList.ToArray()) -Depth 5
    if ([string]::IsNullOrWhiteSpace($json)) { $json = "[]" }
    [System.IO.File]::WriteAllText($histPath, ($json.TrimEnd() + "`r`n"), $utf8Bom)
}

function Update-XHistoryFromInfo {
    param(
        [string]$RootDir = "",
        [Parameter(Mandatory=$true)]$Info,
        [hashtable]$Config = @{}
    )
    if ($null -eq $Info) { return }
    $cfg = if ($null -ne $Config -and ($Config -is [System.Collections.IDictionary]) -and $Config.Count -gt 0) { $Config } else { @{} }
    if (-not [string]::IsNullOrWhiteSpace($RootDir) -and -not $cfg.ContainsKey("RootDir")) {
        $cfg["RootDir"] = $RootDir
    }
    $dtRaw = Get-XPropValue -Obj $Info -Key "ShootDate" -DefaultVal (Get-XPropValue -Obj $Info -Key "DateStr" -DefaultVal "")
    $dt = if ($null -eq $dtRaw) { "" } else { [string]$dtRaw }

    $personsVal = Get-XPropValue -Obj $Info -Key "Persons" -DefaultVal $null
    $modelsVal  = Get-XPropValue -Obj $Info -Key "Models"  -DefaultVal $null

    if ($null -ne $personsVal -and @($personsVal).Count -gt 0) {
        foreach ($p in @($personsVal)) {
            if ($null -eq $p) { continue }
            $nm = [string](Get-XPropValue -Obj $p -Key "Name" -DefaultVal "")
            $xa = [string](Get-XPropValue -Obj $p -Key "XAccount" -DefaultVal "")
            if (-not [string]::IsNullOrWhiteSpace($xa) -or -not [string]::IsNullOrWhiteSpace($nm)) {
                Save-XHistory -Account $xa -Name $nm -Config $cfg -DateStr $dt
            }
        }
    } elseif ($null -ne $modelsVal -and @($modelsVal).Count -gt 0) {
        foreach ($m in @($modelsVal)) {
            if ($null -eq $m) { continue }
            $nm = [string](Get-XPropValue -Obj $m -Key "Name" -DefaultVal "")
            $xa = [string](Get-XPropValue -Obj $m -Key "XId" -DefaultVal "")
            if (-not [string]::IsNullOrWhiteSpace($xa) -or -not [string]::IsNullOrWhiteSpace($nm)) {
                Save-XHistory -Account $xa -Name $nm -Config $cfg -DateStr $dt
            }
        }
    }
}

function Show-XHistoryDialog {
    param(
        [Parameter(Position = 0)]
        [hashtable]$Config = @{},
        [Parameter(Position = 1)]
        [string]$FilterDate = ""
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $histPath = Get-XHistoryFilePath -Config $Config
    $allItems = @(Read-XHistoryList -HistoryPath $histPath | Where-Object { $null -ne $_ })

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Xアカウント履歴検索"
    $dlg.Size = New-Object System.Drawing.Size(580, 440)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5)

    $lblSearch = New-Object System.Windows.Forms.Label
    $lblSearch.Text = "検索:"
    $lblSearch.Location = New-Object System.Drawing.Point(12, 15)
    $lblSearch.Size = New-Object System.Drawing.Size(45, 23)
    $dlg.Controls.Add($lblSearch)

    $txtQuery = New-Object System.Windows.Forms.TextBox
    $txtQuery.Location = New-Object System.Drawing.Point(60, 12)
    $txtQuery.Size = New-Object System.Drawing.Size(270, 25)
    $dlg.Controls.Add($txtQuery)

    $chkSameDate = New-Object System.Windows.Forms.CheckBox
    $chkSameDate.Text = if ([string]::IsNullOrWhiteSpace($FilterDate)) { "同日のみ絞り込み" } else { "同日のみ ($FilterDate)" }
    $chkSameDate.Location = New-Object System.Drawing.Point(342, 13)
    $chkSameDate.Size = New-Object System.Drawing.Size(220, 24)
    $chkSameDate.Enabled = (-not [string]::IsNullOrWhiteSpace($FilterDate))
    $chkSameDate.Checked = $false
    $dlg.Controls.Add($chkSameDate)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Location = New-Object System.Drawing.Point(12, 46)
    $lv.Size = New-Object System.Drawing.Size(540, 295)
    $lv.View = [System.Windows.Forms.View]::Details
    $lv.FullRowSelect = $true
    $lv.GridLines = $true
    [void]$lv.Columns.Add("名前", 180)
    [void]$lv.Columns.Add("Xアカウント", 150)
    [void]$lv.Columns.Add("撮影日", 105)
    [void]$lv.Columns.Add("更新日時", 95)
    $dlg.Controls.Add($lv)

    $lblCount = New-Object System.Windows.Forms.Label
    $lblCount.Location = New-Object System.Drawing.Point(12, 355)
    $lblCount.Size = New-Object System.Drawing.Size(260, 23)
    $lblCount.ForeColor = [System.Drawing.Color]::DimGray
    $dlg.Controls.Add($lblCount)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "選択して反映"
    $btnOk.Location = New-Object System.Drawing.Point(350, 350)
    $btnOk.Size = New-Object System.Drawing.Size(115, 32)
    $btnOk.BackColor = [System.Drawing.Color]::SteelBlue
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "キャンセル"
    $btnCancel.Location = New-Object System.Drawing.Point(472, 350)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 32)
    $dlg.Controls.Add($btnCancel)

    $refreshList = {
        $lv.BeginUpdate()
        try {
            $lv.Items.Clear()
            $q = $txtQuery.Text.Trim()
            $onlyDate = $chkSameDate.Checked -and (-not [string]::IsNullOrWhiteSpace($FilterDate))
            $shown = 0
            foreach ($it in $allItems) {
                if ($null -eq $it) { continue }
                $nm    = if ($it -is [System.Collections.IDictionary]) { [string]$it["name"] }      else { [string]$it.name }
                $acc   = if ($it -is [System.Collections.IDictionary]) { [string]$it["account"] }   else { [string]$it.account }
                $dates = if ($it -is [System.Collections.IDictionary]) { @($it["dates"]) }           else { @($it.dates) }
                $dt    = if ($it -is [System.Collections.IDictionary]) { [string]$it["lastDate"] }  else { [string]$it.lastDate }
                $upd   = if ($it -is [System.Collections.IDictionary]) { [string]$it["updatedAt"] } else { [string]$it.updatedAt }

                if ($onlyDate) {
                    $hasDate = ($dates -contains $FilterDate) -or ($dt -eq $FilterDate)
                    if (-not $hasDate) { continue }
                    $dt = $FilterDate
                }
                if (-not [string]::IsNullOrWhiteSpace($q)) {
                    $hitNm  = $nm.IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                    $hitAcc = $acc.IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                    if (-not ($hitNm -or $hitAcc)) { continue }
                }

                $row = New-Object System.Windows.Forms.ListViewItem($nm)
                [void]$row.SubItems.Add($acc)
                [void]$row.SubItems.Add($dt)
                [void]$row.SubItems.Add($upd)
                $row.Tag = $it
                [void]$lv.Items.Add($row)
                $shown++
            }
            $lblCount.Text = "表示件数: $shown 件 / 全 $(@($allItems).Count) 件"
        } finally {
            $lv.EndUpdate()
        }
    }

    $script:SelectedXItem = $null
    $selectAndClose = {
        if ($lv.SelectedItems.Count -gt 0) {
            $script:SelectedXItem = $lv.SelectedItems[0].Tag
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dlg.Close()
        }
    }

    $txtQuery.Add_TextChanged($refreshList)
    $chkSameDate.Add_CheckedChanged($refreshList)
    $btnOk.Add_Click($selectAndClose)
    $lv.Add_DoubleClick($selectAndClose)
    $btnCancel.Add_Click({
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dlg.Close()
    })

    & $refreshList
    $res = $dlg.ShowDialog()
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        return $script:SelectedXItem
    }
    return $null
}
