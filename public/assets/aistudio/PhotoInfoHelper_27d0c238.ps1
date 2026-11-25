# PhotoInfoHelper.ps1 - 写真情報.txt 読込/書込・キャラ名移行・複数人対応 (UTF-8 BOM)
Set-StrictMode -Version Latest

function New-EmptyPhotoInfo {
    param([string]$FolderPath = "")
    $dateStr = ""
    if ($FolderPath -ne "") {
        $curr = $FolderPath
        while ($curr -and (Split-Path $curr -Leaf) -ne "") {
            $leaf = Split-Path $curr -Leaf
            if ($leaf -match '(\d{4})[-._]?(\d{2})[-._]?(\d{2})') {
                $dateStr = "$($Matches[1])-$($Matches[2])-$($Matches[3])"
                break
            }
            $curr = Split-Path $curr -Parent
        }
    }
    return [ordered]@{
        ShootDate     = $dateStr
        Category      = "イベント"
        EventName     = ""
        CostumeOrChar = ""
        Models        = @()
        ShareUrl      = ""
        DlPassword    = ""
        IsSent        = $false
        Status        = "未登録"
        Comment       = ""
        UpdatedAt     = ""
    }
}

function Read-PhotoInfoTxt {
    param([Parameter(Mandatory=$true)][string]$FolderPath)
    $txtPath = Join-Path $FolderPath "写真情報.txt"
    $info = New-EmptyPhotoInfo -FolderPath $FolderPath
    if (-not (Test-Path -LiteralPath $txtPath)) {
        return $info
    }
    $lines = [System.IO.File]::ReadAllLines($txtPath, [System.Text.Encoding]::UTF8)
    $hasCostumeField = $false
    foreach ($rawLine in $lines) {
        $line = $rawLine.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { continue }
        if ($line -match '^([^:：=]+)[:：=](.*)$') {
            $key = $Matches[1].Trim()
            $val = $Matches[2].Trim()
            switch -Regex ($key) {
                '^(撮影日|ShootDate)$' { $info.ShootDate = $val }
                '^(撮影区分|区分|Category)$' { if ($val -ne "") { $info.Category = $val } }
                '^(イベント名|スタジオ名|併せ名|場所|EventName)$' { $info.EventName = $val }
                '^(衣装名ORキャラ名|キャラ名|衣装|CostumeOrChar)$' {
                    $info.CostumeOrChar = $val
                    $hasCostumeField = $true
                }
                '^(モデル|モデル情報|Model\d*|Models)$' {
                    if ($val -ne "") {
                        $parts = $val -split '\|'
                        $mName = $parts[0].Trim()
                        $mX = if ($parts.Count -ge 2) { ($parts[1].Trim() -replace '^[@＠]+','') } else { "" }
                        $mChar = if ($parts.Count -ge 3) { $parts[2].Trim() } else { "" }
                        $info.Models += [pscustomobject]@{ Name = $mName; XId = $mX; CharName = $mChar }
                    }
                }
                '^(共有URL|MEGAリンク|URL|ShareUrl)$' { $info.ShareUrl = $val }
                '^(DLパスワード|パスワード|DlPassword)$' { $info.DlPassword = $val }
                '^(送付状況|送付済|IsSent)$' {
                    $info.IsSent = ($val -eq "True" -or $val -eq "送付済" -or $val -eq "1" -or $val -eq "●")
                }
                '^(状態|ステータス|Status)$' { if ($val -ne "") { $info.Status = $val } }
                '^(コメント|メモ|Comment)$' { $info.Comment = $val }
                '^(最終更新日時|UpdatedAt)$' { $info.UpdatedAt = $val }
            }
        }
    }
    # 旧形式互換：衣装名ORキャラ名欄が無くコメント欄に値が入っている場合は自動移行
    if (-not $hasCostumeField -and $info.CostumeOrChar -eq "" -and $info.Comment -ne "") {
        $info.CostumeOrChar = $info.Comment
        $info.Comment = ""
    }
    if ($info.Status -eq "未登録" -and ($info.EventName -ne "" -or $info.Models.Count -gt 0 -or $info.CostumeOrChar -ne "")) {
        $info.Status = "登録済"
    }
    return $info
}

function Write-PhotoInfoTxt {
    param(
        [Parameter(Mandatory=$true)][string]$FolderPath,
        [Parameter(Mandatory=$true)]$Info
    )
    if (-not (Test-Path -LiteralPath $FolderPath)) {
        throw "対象フォルダが存在しません: $FolderPath"
    }
    $txtPath = Join-Path $FolderPath "写真情報.txt"
    $nowStr = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $Info.UpdatedAt = $nowStr
    if ($Info.Status -eq "未登録") { $Info.Status = "登録済" }

    $out = New-Object System.Collections.Generic.List[string]
    $out.Add("# PhotoTools 写真情報ファイル")
    $out.Add("撮影日: $($Info.ShootDate)")
    $out.Add("撮影区分: $($Info.Category)")
    $out.Add("イベント名: $($Info.EventName)")
    $out.Add("衣装名ORキャラ名: $($Info.CostumeOrChar)")
    foreach ($m in $Info.Models) {
        $xClean = ($m.XId -replace '^[@＠]+','').Trim()
        $cClean = if ($null -ne $m.CharName) { $m.CharName.Trim() } else { "" }
        $out.Add("モデル: $($m.Name.Trim())|$xClean|$cClean")
    }
    $out.Add("共有URL: $($Info.ShareUrl)")
    $out.Add("DLパスワード: $($Info.DlPassword)")
    $sentText = if ($Info.IsSent) { "送付済" } else { "未送付" }
    $out.Add("送付状況: $sentText")
    $out.Add("状態: $($Info.Status)")
    $out.Add("コメント: $($Info.Comment)")
    $out.Add("最終更新日時: $nowStr")

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllLines($txtPath, $out, $utf8Bom)
    return $txtPath
}
