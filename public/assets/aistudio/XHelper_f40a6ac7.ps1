#requires -Version 5.1

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

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    } catch {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    }

    $headers = @{
        "User-Agent"      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        "Accept-Language" = "ja,en-US;q=0.9,en;q=0.8"
    }

    # 1. X / Twitter oEmbed API
    try {
        $oembedUrl = "https://publish.twitter.com/oembed?url=" + [System.Uri]::EscapeDataString("https://x.com/$id")
        $resp = Invoke-RestMethod -Uri $oembedUrl -Headers $headers -TimeoutSec 8 -ErrorAction Stop
        if ($null -ne $resp -and -not [string]::IsNullOrWhiteSpace([string]$resp.author_name)) {
            $cleaned = Clean-XDisplayName ([string]$resp.author_name)
            if (-not [string]::IsNullOrWhiteSpace($cleaned) -and $cleaned -ne $id) {
                return $cleaned
            }
            if (-not [string]::IsNullOrWhiteSpace($cleaned)) {
                $fallbackName = $cleaned
            }
        }
    } catch {}

    # 2. fxtwitter public profile API
    try {
        $fxUrl = "https://api.fxtwitter.com/$id"
        $fxResp = Invoke-RestMethod -Uri $fxUrl -Headers $headers -TimeoutSec 8 -ErrorAction Stop
        if ($null -ne $fxResp -and $null -ne $fxResp.user -and -not [string]::IsNullOrWhiteSpace([string]$fxResp.user.name)) {
            $cleaned = Clean-XDisplayName ([string]$fxResp.user.name)
            if (-not [string]::IsNullOrWhiteSpace($cleaned)) {
                return $cleaned
            }
        }
    } catch {}

    # 3. vxtwitter public profile API
    try {
        $vxUrl = "https://api.vxtwitter.com/$id"
        $vxResp = Invoke-RestMethod -Uri $vxUrl -Headers $headers -TimeoutSec 8 -ErrorAction Stop
        if ($null -ne $vxResp -and -not [string]::IsNullOrWhiteSpace([string]$vxResp.user_name)) {
            $cleaned = Clean-XDisplayName ([string]$vxResp.user_name)
            if (-not [string]::IsNullOrWhiteSpace($cleaned)) {
                return $cleaned
            }
        }
    } catch {}

    # 4. Direct HTML title / og:title fallback
    try {
        $pageUrl = "https://x.com/$id"
        $webResp = Invoke-WebRequest -Uri $pageUrl -Headers $headers -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        $html = [string]$webResp.Content
        if ($html -match '<meta[^>]+property=["'']og:title["''][^>]+content=["'']([^"'']+)["'']') {
            $cleaned = Clean-XDisplayName $Matches[1]
            if (-not [string]::IsNullOrWhiteSpace($cleaned) -and $cleaned -ne "X") {
                return $cleaned
            }
        }
        if ($html -match '<title[^>]*>([^<]+)</title>') {
            $cleaned = Clean-XDisplayName $Matches[1]
            if (-not [string]::IsNullOrWhiteSpace($cleaned) -and $cleaned -ne "X") {
                return $cleaned
            }
        }
    } catch {}

    if (-not [string]::IsNullOrWhiteSpace($fallbackName)) {
        return $fallbackName
    }
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
        if ($Config.ContainsKey("RootDir") -and -not [string]::IsNullOrWhiteSpace([string]$Config["RootDir"])) {
            return (Join-Path ([string]$Config["RootDir"]) "x_history.json")
        }
    }
    return "D:\PhotoTools\x_history.json"
}

function Read-XHistoryList {
    param([string]$HistoryPath)
    $list = New-Object System.Collections.Generic.List[hashtable]
    if ([string]::IsNullOrWhiteSpace($HistoryPath) -or -not (Test-Path -LiteralPath $HistoryPath)) {
        return $list
    }
    try {
        $raw = Get-Content -LiteralPath $HistoryPath -Encoding UTF8 -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return $list }
        $parsed = $raw | ConvertFrom-Json
        if ($null -eq $parsed) { return $list }

        $items = if ($parsed -is [System.Array]) { $parsed }
                 elseif ($null -ne $parsed.items) { $parsed.items }
                 elseif ($null -ne $parsed.history) { $parsed.history }
                 else { @($parsed) }

        foreach ($it in $items) {
            if ($null -eq $it) { continue }
            $acc = ""
            $nm  = ""
            $dt  = ""
            $upd = ""
            if ($it -is [hashtable]) {
                $acc = [string]$it["account"]
                $nm  = [string]$it["name"]
                $dt  = [string]$it["date"]
                $upd = [string]$it["updatedAt"]
            } else {
                if ($null -ne $it.account) { $acc = [string]$it.account }
                elseif ($null -ne $it.XAccount) { $acc = [string]$it.XAccount }
                if ($null -ne $it.name) { $nm = [string]$it.name }
                elseif ($null -ne $it.Name) { $nm = [string]$it.Name }
                if ($null -ne $it.date) { $dt = [string]$it.date }
                elseif ($null -ne $it.DateStr) { $dt = [string]$it.DateStr }
                if ($null -ne $it.updatedAt) { $upd = [string]$it.updatedAt }
            }
            $normAcc = Normalize-XAccount $acc
            if (-not [string]::IsNullOrWhiteSpace($normAcc) -or -not [string]::IsNullOrWhiteSpace($nm)) {
                $list.Add(@{
                    account   = $normAcc
                    name      = (Clean-XDisplayName $nm)
                    date      = $dt.Trim()
                    updatedAt = $upd
                })
            }
        }
    } catch {}
    return $list
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

    $normAcc = Normalize-XAccount $Account
    $cleanNm = Clean-XDisplayName $Name
    if ([string]::IsNullOrWhiteSpace($normAcc) -and [string]::IsNullOrWhiteSpace($cleanNm)) { return }

    $histPath = Get-XHistoryFilePath -Config $Config
    $dir = [System.IO.Path]::GetDirectoryName($histPath)
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $list = Read-XHistoryList -HistoryPath $histPath
    $nowStr = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $dateVal = if ($null -eq $DateStr) { "" } else { $DateStr.Trim() }

    $newList = New-Object System.Collections.Generic.List[hashtable]
    $newList.Add(@{
        account   = $normAcc
        name      = $cleanNm
        date      = $dateVal
        updatedAt = $nowStr
    })

    foreach ($item in $list) {
        $sameAcc = (-not [string]::IsNullOrWhiteSpace($normAcc)) -and ($item["account"].Equals($normAcc, [System.StringComparison]::OrdinalIgnoreCase))
        $sameNm  = ([string]::IsNullOrWhiteSpace($normAcc)) -and ($item["name"].Equals($cleanNm, [System.StringComparison]::OrdinalIgnoreCase))
        if ($sameAcc -or $sameNm) {
            if ([string]::IsNullOrWhiteSpace($dateVal) -and -not [string]::IsNullOrWhiteSpace($item["date"])) {
                $newList[0]["date"] = $item["date"]
            }
            continue
        }
        $newList.Add($item)
    }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $json = ConvertTo-Json -InputObject @($newList) -Depth 4
    [System.IO.File]::WriteAllText($histPath, $json, $utf8Bom)
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
    $allItems = Read-XHistoryList -HistoryPath $histPath

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
                $nm  = [string]$it["name"]
                $acc = [string]$it["account"]
                $dt  = [string]$it["date"]
                $upd = [string]$it["updatedAt"]

                if ($onlyDate) {
                    if ([string]::IsNullOrWhiteSpace($dt) -or ($dt -ne $FilterDate)) { continue }
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
            $lblCount.Text = "表示件数: $shown 件 / 全 $($allItems.Count) 件"
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
