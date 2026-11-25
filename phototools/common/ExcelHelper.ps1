#requires -Version 5.1
# ==============================================================================
# ExcelHelper.ps1 - OpenXML直接読み書きによる Excel 管理台帳更新・アーカイブ追従 (UTF-8 BOM / CRLF)
# ==============================================================================
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-PhotoLedgerHeaders {
    return @(
        "撮影日",
        "撮影区分",
        "催事・場所名",
        "衣装・キャラ名",
        "モデル名",
        "Xアカウント",
        "X_URL",
        "複数フォルダ",
        "データ送付状況",
        "コメント",
        "MEGAリンク",
        "ギガファイル便リンク",
        "相対パス",
        "フォルダ名",
        "取込フォルダ",
        "現像後フォルダ",
        "人物連番",
        "最終更新日時"
    )
}

function ConvertTo-ExcelColName {
    param([int]$ColIndex1Based)
    $name = ""
    $n = $ColIndex1Based
    while ($n -gt 0) {
        $mod = ($n - 1) % 26
        $name = [char](65 + $mod) + $name
        $n = [Math]::Floor(($n - 1) / 26)
    }
    return $name
}

function ConvertFrom-ExcelColName {
    param([string]$CellRef)
    $letters = ($CellRef -replace '[^A-Z]', '')
    $sum = 0
    foreach ($ch in $letters.ToCharArray()) {
        $sum = $sum * 26 + ([int][char]$ch - 64)
    }
    return $sum
}

function Escape-XmlText {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    $clean = [System.Text.RegularExpressions.Regex]::Replace($Text, '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
    return [System.Security.SecurityElement]::Escape($clean)
}

function Read-XlsxRows {
    param([string]$XlsxPath)
    $rows = New-Object System.Collections.ArrayList
    if ([string]::IsNullOrWhiteSpace($XlsxPath) -or -not (Test-Path -LiteralPath $XlsxPath)) { return @() }

    $fs = [System.IO.File]::OpenRead($XlsxPath)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Read)
        try {
            $sharedStrings = New-Object System.Collections.Generic.List[string]
            $ssEntry = $zip.GetEntry("xl/sharedStrings.xml")
            if ($null -ne $ssEntry) {
                $sr = New-Object System.IO.StreamReader($ssEntry.Open(), [System.Text.Encoding]::UTF8)
                $ssXml = [xml]$sr.ReadToEnd()
                $sr.Dispose()
                foreach ($si in $ssXml.sst.si) {
                    if ($null -ne $si.t) {
                        if ($si.t -is [string]) { $sharedStrings.Add($si.t) }
                        else { $sharedStrings.Add([string]$si.t.InnerText) }
                    } elseif ($null -ne $si.r) {
                        $sb = New-Object System.Text.StringBuilder
                        foreach ($run in $si.r) {
                            if ($null -ne $run.t) {
                                if ($run.t -is [string]) { [void]$sb.Append($run.t) }
                                else { [void]$sb.Append([string]$run.t.InnerText) }
                            }
                        }
                        $sharedStrings.Add($sb.ToString())
                    } else {
                        $sharedStrings.Add("")
                    }
                }
            }

            $sheetEntry = $zip.GetEntry("xl/worksheets/sheet1.xml")
            if ($null -eq $sheetEntry) { return @() }
            $sr2 = New-Object System.IO.StreamReader($sheetEntry.Open(), [System.Text.Encoding]::UTF8)
            $sheetXml = [xml]$sr2.ReadToEnd()
            $sr2.Dispose()

            $nsMgr = New-Object System.Xml.XmlNamespaceManager($sheetXml.NameTable)
            $nsMgr.AddNamespace("x", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")
            $rowNodes = $sheetXml.SelectNodes("//x:sheetData/x:row", $nsMgr)

            foreach ($rNode in $rowNodes) {
                $rowMap = @{}
                $maxCol = 0
                $cNodes = $rNode.SelectNodes("x:c", $nsMgr)
                foreach ($cNode in $cNodes) {
                    $ref = $cNode.GetAttribute("r")
                    $colIdx = ConvertFrom-ExcelColName $ref
                    if ($colIdx -gt $maxCol) { $maxCol = $colIdx }
                    $tAttr = $cNode.GetAttribute("t")
                    $val = ""
                    if ($tAttr -eq "s") {
                        $vNode = $cNode.SelectSingleNode("x:v", $nsMgr)
                        if ($null -ne $vNode) {
                            $idx = [int]$vNode.InnerText
                            if ($idx -ge 0 -and $idx -lt $sharedStrings.Count) {
                                $val = $sharedStrings[$idx]
                            }
                        }
                    } elseif ($tAttr -eq "inlineStr") {
                        $tNode = $cNode.SelectSingleNode("x:is/x:t", $nsMgr)
                        if ($null -ne $tNode) { $val = $tNode.InnerText }
                    } else {
                        $vNode = $cNode.SelectSingleNode("x:v", $nsMgr)
                        if ($null -ne $vNode) { $val = $vNode.InnerText }
                    }
                    $rowMap[$colIdx] = $val
                }
                $arr = New-Object string[] $maxCol
                for ($c = 1; $c -le $maxCol; $c++) {
                    if ($rowMap.ContainsKey($c)) { $arr[$c - 1] = $rowMap[$c] }
                    else { $arr[$c - 1] = "" }
                }
                [void]$rows.Add($arr)
            }
        } finally {
            $zip.Dispose()
        }
    } finally {
        $fs.Dispose()
    }
    return ([object[]]$rows.ToArray())
}

function Write-XlsxRows {
    param(
        [string]$XlsxPath,
        [object]$Rows
    )
    $rowItems = New-Object System.Collections.ArrayList
    if ($null -ne $Rows) {
        foreach ($rItem in $Rows) {
            [void]$rowItems.Add($rItem)
        }
    }
    $parentDir = Split-Path -Parent $XlsxPath
    if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    $tempPath = $XlsxPath + ".tmp_" + [Guid]::NewGuid().ToString("N")
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    $contentTypes = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
'@

    $rootRels = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
'@

    $workbook = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="写真管理一覧" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>
'@

    $wbRels = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
'@

    $styles = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><name val="Yu Gothic UI"/></font>
    <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Yu Gothic UI"/></font>
  </fonts>
  <fills count="3">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF2B579A"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border>
      <left style="thin"><color rgb="FFD9D9D9"/></left>
      <right style="thin"><color rgb="FFD9D9D9"/></right>
      <top style="thin"><color rgb="FFD9D9D9"/></top>
      <bottom style="thin"><color rgb="FFD9D9D9"/></bottom>
      <diagonal/>
    </border>
  </borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="3">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf>
  </cellXfs>
</styleSheet>
'@

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    [void]$sb.AppendLine('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    [void]$sb.AppendLine('  <cols>')
    $widths = @(13, 10, 24, 22, 18, 18, 28, 14, 14, 34, 32, 32, 26, 20, 30, 30, 10, 20)
    for ($w = 0; $w -lt $widths.Count; $w++) {
        $colNum = $w + 1
        [void]$sb.AppendLine("    <col min=`"$colNum`" max=`"$colNum`" width=`"$($widths[$w])`" customWidth=`"1`"/>")
    }
    [void]$sb.AppendLine('  </cols>')
    [void]$sb.AppendLine('  <sheetData>')

    for ($r = 0; $r -lt $rowItems.Count; $r++) {
        $rowNum = $r + 1
        $styleId = if ($r -eq 0) { "1" } else { "2" }
        [void]$sb.AppendLine("    <row r=`"$rowNum`">")
        $vals = $rowItems[$r]
        for ($c = 0; $c -lt $vals.Count; $c++) {
            $colRef = (ConvertTo-ExcelColName ($c + 1)) + $rowNum
            $valStr = [string]$vals[$c]
            $escaped = Escape-XmlText $valStr
            [void]$sb.AppendLine("      <c r=`"$colRef`" s=`"$styleId`" t=`"inlineStr`"><is><t xml:space=`"preserve`">$escaped</t></is></c>")
        }
        [void]$sb.AppendLine('    </row>')
    }

    [void]$sb.AppendLine('  </sheetData>')
    [void]$sb.AppendLine('</worksheet>')

    $fs = [System.IO.File]::Open($tempPath, [System.IO.FileMode]::Create)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $entries = @{
                "[Content_Types].xml"        = $contentTypes
                "_rels/.rels"                = $rootRels
                "xl/workbook.xml"            = $workbook
                "xl/_rels/workbook.xml.rels" = $wbRels
                "xl/styles.xml"              = $styles
                "xl/worksheets/sheet1.xml"   = $sb.ToString()
            }
            foreach ($k in $entries.Keys) {
                $ent = $zip.CreateEntry($k, [System.IO.Compression.CompressionLevel]::Optimal)
                $sw = New-Object System.IO.StreamWriter($ent.Open(), $utf8NoBom)
                $sw.Write($entries[$k])
                $sw.Dispose()
            }
        } finally {
            $zip.Dispose()
        }
    } finally {
        $fs.Dispose()
    }

    try {
        if (Test-Path -LiteralPath $XlsxPath) {
            Copy-Item -LiteralPath $XlsxPath -Destination ($XlsxPath + ".bak") -Force -ErrorAction SilentlyContinue
        }
        Move-Item -LiteralPath $tempPath -Destination $XlsxPath -Force -ErrorAction Stop
    } catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw "Excel台帳ファイルの更新に失敗しました（Excelで開かれている可能性があります）。ファイルを閉じてから再実行してください: $XlsxPath ($($_.Exception.Message))"
    }
}

function Get-ExcelLedgerPathFromConfig {
    param([hashtable]$Config = @{})
    if ($null -ne $Config) {
        if ($Config.ContainsKey("ExcelPath") -and -not [string]::IsNullOrWhiteSpace([string]$Config["ExcelPath"])) {
            return [string]$Config["ExcelPath"]
        }
        if ($Config.ContainsKey("Paths") -and $Config["Paths"] -is [hashtable]) {
            if ($Config["Paths"].ContainsKey("ExcelPath") -and -not [string]::IsNullOrWhiteSpace([string]$Config["Paths"]["ExcelPath"])) {
                return [string]$Config["Paths"]["ExcelPath"]
            }
            $dev = [string]$Config["Paths"]["DevelopedRoot"]
            $fn  = [string]$Config["Paths"]["LedgerFileName"]
            if (-not [string]::IsNullOrWhiteSpace($dev) -and -not [string]::IsNullOrWhiteSpace($fn)) {
                return (Join-Path $dev $fn)
            }
        }
    }
    return "G:\写真\現像後\写真管理一覧.xlsx"
}

function Get-ExcelRecVal {
    param([object]$Obj, [string]$Key, [string]$Fallback = "")
    if ($null -eq $Obj) { return $Fallback }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Key) -and $null -ne $Obj[$Key]) { return [string]$Obj[$Key] }
    } else {
        $prop = $Obj.PSObject.Properties[$Key]
        if ($null -ne $prop -and $null -ne $prop.Value) { return [string]$prop.Value }
    }
    return $Fallback
}

function Update-PhotoExcelLedger {
    param(
        [object]$Records,
        [hashtable]$Config = @{}
    )
    if ($null -eq $Records) { return }
    $recList = @($Records)
    if ($recList.Count -eq 0) { return }

    $excelPath = Get-ExcelLedgerPathFromConfig -Config $Config
    $headers = Get-PhotoLedgerHeaders
    $colCount = $headers.Count

    $existingRows = @(Read-XlsxRows -XlsxPath $excelPath)
    $dataRows = New-Object System.Collections.ArrayList

    if ($existingRows.Count -gt 1) {
        $oldHeader = $existingRows[0]
        for ($r = 1; $r -lt $existingRows.Count; $r++) {
            $oldRow = $existingRows[$r]
            $newRow = New-Object string[] $colCount
            for ($c = 0; $c -lt $colCount; $c++) {
                $hName = $headers[$c]
                $oldIdx = [Array]::IndexOf($oldHeader, $hName)
                if ($oldIdx -lt 0 -and $hName -eq "催事・場所名") { $oldIdx = [Array]::IndexOf($oldHeader, "イベント名") }
                if ($oldIdx -lt 0 -and $hName -eq "催事・場所名") { $oldIdx = [Array]::IndexOf($oldHeader, "イベント・場所") }
                if ($oldIdx -lt 0 -and $hName -eq "モデル名")     { $oldIdx = [Array]::IndexOf($oldHeader, "名前") }
                if ($oldIdx -lt 0 -and $hName -eq "衣装・キャラ名") { $oldIdx = [Array]::IndexOf($oldHeader, "衣装・キャラ") }
                if ($oldIdx -lt 0 -and $hName -eq "人物連番")     { $oldIdx = [Array]::IndexOf($oldHeader, "枠番号") }
                if ($oldIdx -lt 0 -and $hName -eq "コメント")     { $oldIdx = [Array]::IndexOf($oldHeader, "メモ") }
                if ($oldIdx -lt 0 -and $hName -eq "ギガファイル便リンク") { $oldIdx = [Array]::IndexOf($oldHeader, "ギガファイル便URL") }
                if ($oldIdx -lt 0 -and $hName -eq "MEGAリンク")   { $oldIdx = [Array]::IndexOf($oldHeader, "MEGA共有URL") }
                if ($oldIdx -lt 0 -and $hName -eq "データ送付状況") {
                    foreach ($alias in @("送付状況", "送付済み", "送付済", "データ送付済み", "データ送付済", "データ送付")) {
                        $oldIdx = [Array]::IndexOf($oldHeader, $alias)
                        if ($oldIdx -ge 0) { break }
                    }
                }
                if ($oldIdx -ge 0 -and $oldIdx -lt $oldRow.Count) {
                    $cellVal = [string]$oldRow[$oldIdx]
                    if ($hName -eq "データ送付状況" -and $cellVal -eq "送付済") { $cellVal = "送付済み" }
                    $newRow[$c] = $cellVal
                } else {
                    $newRow[$c] = ""
                }
            }
            [void]$dataRows.Add($newRow)
        }
    }

    $nowStr = (Get-Date).ToString("yyyy/MM/dd HH:mm:ss")

    foreach ($rec in $recList) {
        $dateStr      = Get-ExcelRecVal $rec "DateStr" (Get-ExcelRecVal $rec "ShootDate")
        $category     = Get-ExcelRecVal $rec "Category" "イベント"
        $eventName    = Get-ExcelRecVal $rec "EventName"
        $costume      = Get-ExcelRecVal $rec "CostumeOrChar" (Get-ExcelRecVal $rec "Costume")
        $name         = Get-ExcelRecVal $rec "Name"
        $xAccount     = Get-ExcelRecVal $rec "XAccount"
        $xUrl         = Get-ExcelRecVal $rec "XUrl"
        if ([string]::IsNullOrWhiteSpace($xUrl) -and -not [string]::IsNullOrWhiteSpace($xAccount)) {
            $xUrl = "https://x.com/" + $xAccount.TrimStart('@')
        }
        $multiFlag    = Get-ExcelRecVal $rec "MultiFolder" (Get-ExcelRecVal $rec "MultiFolderFlag" (Get-ExcelRecVal $rec "MultipleFolders"))
        $sentStatus   = Get-ExcelRecVal $rec "SentStatus"
        if ($sentStatus -eq "送付済") { $sentStatus = "送付済み" }
        $comment      = Get-ExcelRecVal $rec "Comment" (Get-ExcelRecVal $rec "Notes")
        $megaLink     = Get-ExcelRecVal $rec "MegaLink"
        $gigaLink     = Get-ExcelRecVal $rec "GigaFileLink" (Get-ExcelRecVal $rec "ShareUrl")
        if ([string]::IsNullOrWhiteSpace($sentStatus)) {
            $sentStatus = if (-not [string]::IsNullOrWhiteSpace($gigaLink)) { "送付済み" } else { "未送付" }
        }
        $relPath      = Get-ExcelRecVal $rec "RelPath"
        $folderName   = Get-ExcelRecVal $rec "FolderName"
        $importFolder = Get-ExcelRecVal $rec "ImportFolder"
        $devFolder    = Get-ExcelRecVal $rec "DevFolder"
        $personIdx    = Get-ExcelRecVal $rec "PersonIndex" "1"

        $rowArr = [string[]]@(
            $dateStr,
            $category,
            $eventName,
            $costume,
            $name,
            $xAccount,
            $xUrl,
            $multiFlag,
            $sentStatus,
            $comment,
            $megaLink,
            $gigaLink,
            $relPath,
            $folderName,
            $importFolder,
            $devFolder,
            $personIdx,
            $nowStr
        )

        $matchedIndex = -1
        for ($i = 0; $i -lt $dataRows.Count; $i++) {
            $ex = $dataRows[$i]
            $exDate = $ex[0]
            $exRel  = $ex[12]
            $exFld  = $ex[13]
            $exDev  = $ex[15]
            $exIdx  = if ([string]::IsNullOrWhiteSpace($ex[16])) { "1" } else { $ex[16] }

            $sameFolder = $false
            if (-not [string]::IsNullOrWhiteSpace($relPath) -and $exRel -eq $relPath) {
                $sameFolder = $true
            } elseif (-not [string]::IsNullOrWhiteSpace($devFolder) -and ($exDev -ieq $devFolder)) {
                $sameFolder = $true
            } elseif (-not [string]::IsNullOrWhiteSpace($dateStr) -and -not [string]::IsNullOrWhiteSpace($folderName) -and $exDate -eq $dateStr -and $exFld -eq $folderName) {
                $sameFolder = $true
            }

            if ($sameFolder -and $exIdx -eq $personIdx) {
                $matchedIndex = $i
                break
            }
        }

        if ($matchedIndex -ge 0) {
            $dataRows[$matchedIndex] = $rowArr
        } else {
            [void]$dataRows.Add($rowArr)
        }
    }

    $outRows = New-Object System.Collections.ArrayList
    [void]$outRows.Add([string[]]$headers)
    foreach ($dr in $dataRows) {
        [void]$outRows.Add($dr)
    }

    Write-XlsxRows -XlsxPath $excelPath -Rows ([object[]]$outRows.ToArray())
}

function Sync-RecordsToExcelLedger {
    param(
        [hashtable]$Config = @{},
        [object]$Records
    )
    if ($null -eq $Records) { return }
    $flatRecords = New-Object System.Collections.Generic.List[hashtable]

    foreach ($item in @($Records)) {
        if ($null -eq $item) { continue }
        $folderPath = Get-ExcelRecVal $item "FolderPath"
        $devFolder  = Get-ExcelRecVal $item "DevFolder"
        $impFolder  = Get-ExcelRecVal $item "ImportFolder"
        if ([string]::IsNullOrWhiteSpace($devFolder) -and -not [string]::IsNullOrWhiteSpace($folderPath)) {
            $devFolder = $folderPath
        }
        $folderName = Get-ExcelRecVal $item "FolderName"
        if ([string]::IsNullOrWhiteSpace($folderName) -and -not [string]::IsNullOrWhiteSpace($folderPath)) {
            $folderName = Split-Path -Leaf $folderPath
        }

        $relPath = Get-ExcelRecVal $item "RelPath"
        if ([string]::IsNullOrWhiteSpace($relPath) -and -not [string]::IsNullOrWhiteSpace($folderPath)) {
            $devRoot = if ($Config.ContainsKey("DevRoot")) { [string]$Config["DevRoot"] } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($devRoot) -and $folderPath.StartsWith($devRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                $relPath = $folderPath.Substring($devRoot.Length).TrimStart('\')
            } else {
                $dt = Get-ExcelRecVal $item "DateStr" (Get-ExcelRecVal $item "ShootDate")
                $dtNorm = $dt.Replace('-', '_')
                $fnNorm = $folderName.Replace('-', '_')
                if (-not [string]::IsNullOrWhiteSpace($dt) -and -not ($fnNorm -ieq $dtNorm)) {
                    $relPath = "$dt\$folderName"
                } else {
                    $relPath = $folderName
                }
            }
        }

        $persons = $null
        if ($item -is [System.Collections.IDictionary] -and $item.Contains("Persons")) { $persons = $item["Persons"] }
        elseif ($null -ne $item.PSObject.Properties["Persons"]) { $persons = $item.Persons }

        if ($null -ne $persons -and @($persons).Count -gt 0) {
            $idx = 1
            foreach ($p in @($persons)) {
                $pX = Get-ExcelRecVal $p "XAccount"
                $pCom = Get-ExcelRecVal $p "Comment"
                if ([string]::IsNullOrWhiteSpace($pCom)) {
                    $pCom = Get-ExcelRecVal $item "Notes" (Get-ExcelRecVal $item "Comment")
                }
                $flatRecords.Add(@{
                    DateStr       = Get-ExcelRecVal $item "DateStr" (Get-ExcelRecVal $item "ShootDate")
                    Category      = Get-ExcelRecVal $item "Category" "イベント"
                    EventName     = Get-ExcelRecVal $item "EventName"
                    CostumeOrChar = Get-ExcelRecVal $p "CostumeOrChar" (Get-ExcelRecVal $item "CostumeOrChar")
                    Name          = Get-ExcelRecVal $p "Name"
                    XAccount      = $pX
                    XUrl          = if ([string]::IsNullOrWhiteSpace($pX)) { "" } else { "https://x.com/" + $pX.TrimStart('@') }
                    MultiFolder   = Get-ExcelRecVal $item "MultiFolder"
                    SentStatus    = Get-ExcelRecVal $item "SentStatus"
                    Comment       = $pCom
                    MegaLink      = Get-ExcelRecVal $item "MegaLink"
                    GigaFileLink  = Get-ExcelRecVal $item "GigaFileLink" (Get-ExcelRecVal $item "ShareUrl")
                    RelPath       = $relPath
                    FolderName    = $folderName
                    ImportFolder  = $impFolder
                    DevFolder     = $devFolder
                    PersonIndex   = [string]$idx
                })
                $idx++
            }
        } else {
            $flatRecords.Add(@{
                DateStr       = Get-ExcelRecVal $item "DateStr" (Get-ExcelRecVal $item "ShootDate")
                Category      = Get-ExcelRecVal $item "Category" "イベント"
                EventName     = Get-ExcelRecVal $item "EventName"
                CostumeOrChar = Get-ExcelRecVal $item "CostumeOrChar"
                Name          = Get-ExcelRecVal $item "Name"
                XAccount      = Get-ExcelRecVal $item "XAccount"
                XUrl          = Get-ExcelRecVal $item "XUrl"
                MultiFolder   = Get-ExcelRecVal $item "MultiFolder"
                SentStatus    = Get-ExcelRecVal $item "SentStatus"
                Comment       = Get-ExcelRecVal $item "Comment" (Get-ExcelRecVal $item "Notes")
                MegaLink      = Get-ExcelRecVal $item "MegaLink"
                GigaFileLink  = Get-ExcelRecVal $item "GigaFileLink" (Get-ExcelRecVal $item "ShareUrl")
                RelPath       = $relPath
                FolderName    = $folderName
                ImportFolder  = $impFolder
                DevFolder     = $devFolder
                PersonIndex   = Get-ExcelRecVal $item "PersonIndex" "1"
            })
        }
    }

    if ($flatRecords.Count -gt 0) {
        Update-PhotoExcelLedger -Records $flatRecords -Config $Config
    }
}

function Update-PhotoLedgerPathsAfterMove {
    param(
        [Parameter(Mandatory=$true)][string]$OldBasePath,
        [Parameter(Mandatory=$true)][string]$NewBasePath,
        [Parameter(Mandatory=$true)][ValidateSet("Developed", "RAW", "Import")][string]$ColumnType,
        [hashtable]$Config = @{}
    )
    $excelPath = Get-ExcelLedgerPathFromConfig -Config $Config
    if (-not (Test-Path -LiteralPath $excelPath)) { return 0 }

    $rows = @(Read-XlsxRows -XlsxPath $excelPath)
    if ($rows.Count -le 1) { return 0 }

    $header = $rows[0]
    $targetColNames = if ($ColumnType -eq "Developed") { @("現像後フォルダ", "現像後フォルダパス") }
                      elseif ($ColumnType -eq "Import") { @("取込フォルダ", "取込フォルダパス", "カメラ取り込み元", "取込元フォルダ") }
                      else { @("RAWフォルダ", "RAWフォルダパス") }
    $colIdx = -1
    foreach ($cn in $targetColNames) {
        $colIdx = [Array]::IndexOf($header, $cn)
        if ($colIdx -ge 0) { break }
    }
    if ($colIdx -lt 0) { return 0 }

    $updIdx = [Array]::IndexOf($header, "最終更新日時")
    $oldNorm = $OldBasePath.TrimEnd('\')
    $newNorm = $NewBasePath.TrimEnd('\')
    $nowStr  = (Get-Date).ToString("yyyy/MM/dd HH:mm:ss")
    $updated = 0

    for ($r = 1; $r -lt $rows.Count; $r++) {
        $row = $rows[$r]
        if ($colIdx -lt $row.Count) {
            $curVal = [string]$row[$colIdx]
            if (-not [string]::IsNullOrWhiteSpace($curVal) -and (($curVal -ieq $oldNorm) -or $curVal.StartsWith(($oldNorm + "\"), [System.StringComparison]::OrdinalIgnoreCase))) {
                $suffix = $curVal.Substring($oldNorm.Length)
                $row[$colIdx] = $newNorm + $suffix
                if ($updIdx -ge 0 -and $updIdx -lt $row.Count) {
                    $row[$updIdx] = $nowStr
                }
                $updated++
            }
        }
    }

    if ($updated -gt 0) {
        Write-XlsxRows -XlsxPath $excelPath -Rows $rows
    }
    return $updated
}

function Update-PhotoLedgerAfterSubFolderRename {
    param(
        [Parameter(Mandatory=$true)][string]$DateName,
        [Parameter(Mandatory=$true)][string]$OldRelSubPath,
        [Parameter(Mandatory=$true)][string]$NewRelSubPath,
        [string]$OldImportPath = "",
        [string]$NewImportPath = "",
        [string]$OldDevPath = "",
        [string]$NewDevPath = "",
        [hashtable]$Config = @{}
    )
    $excelPath = Get-ExcelLedgerPathFromConfig -Config $Config
    if (-not (Test-Path -LiteralPath $excelPath)) { return 0 }

    $rows = @(Read-XlsxRows -XlsxPath $excelPath)
    if ($rows.Count -le 1) { return 0 }

    $header    = $rows[0]
    $relIdx    = [Array]::IndexOf($header, "相対パス")
    $fnIdx     = [Array]::IndexOf($header, "フォルダ名")
    $impIdx    = [Array]::IndexOf($header, "取込フォルダ")
    $devIdx    = [Array]::IndexOf($header, "現像後フォルダ")
    $updIdx    = [Array]::IndexOf($header, "最終更新日時")

    $oldFullRel = (Join-Path $DateName $OldRelSubPath).TrimEnd('\')
    $newFullRel = (Join-Path $DateName $NewRelSubPath).TrimEnd('\')
    $oldImpNorm = if (-not [string]::IsNullOrWhiteSpace($OldImportPath)) { $OldImportPath.TrimEnd('\') } else { "" }
    $newImpNorm = if (-not [string]::IsNullOrWhiteSpace($NewImportPath)) { $NewImportPath.TrimEnd('\') } else { "" }
    $oldDevNorm = if (-not [string]::IsNullOrWhiteSpace($OldDevPath))    { $OldDevPath.TrimEnd('\') }    else { "" }
    $newDevNorm = if (-not [string]::IsNullOrWhiteSpace($NewDevPath))    { $NewDevPath.TrimEnd('\') }    else { "" }
    $nowStr     = (Get-Date).ToString("yyyy/MM/dd HH:mm:ss")
    $updated    = 0

    for ($r = 1; $r -lt $rows.Count; $r++) {
        $row = $rows[$r]
        $rowChanged = $false

        if ($relIdx -ge 0 -and $relIdx -lt $row.Count) {
            $curRel = [string]$row[$relIdx]
            if (-not [string]::IsNullOrWhiteSpace($curRel) -and (($curRel -ieq $oldFullRel) -or $curRel.StartsWith(($oldFullRel + "\"), [System.StringComparison]::OrdinalIgnoreCase))) {
                $newRelVal = $newFullRel + $curRel.Substring($oldFullRel.Length)
                $row[$relIdx] = $newRelVal
                if ($fnIdx -ge 0 -and $fnIdx -lt $row.Count) {
                    $row[$fnIdx] = [System.IO.Path]::GetFileName($newRelVal)
                }
                $rowChanged = $true
            }
        }
        if ($impIdx -ge 0 -and $impIdx -lt $row.Count -and -not [string]::IsNullOrWhiteSpace($oldImpNorm) -and -not [string]::IsNullOrWhiteSpace($newImpNorm)) {
            $curImp = [string]$row[$impIdx]
            if (-not [string]::IsNullOrWhiteSpace($curImp) -and (($curImp -ieq $oldImpNorm) -or $curImp.StartsWith(($oldImpNorm + "\"), [System.StringComparison]::OrdinalIgnoreCase))) {
                $row[$impIdx] = $newImpNorm + $curImp.Substring($oldImpNorm.Length)
                $rowChanged = $true
            }
        }
        if ($devIdx -ge 0 -and $devIdx -lt $row.Count -and -not [string]::IsNullOrWhiteSpace($oldDevNorm) -and -not [string]::IsNullOrWhiteSpace($newDevNorm)) {
            $curDev = [string]$row[$devIdx]
            if (-not [string]::IsNullOrWhiteSpace($curDev) -and (($curDev -ieq $oldDevNorm) -or $curDev.StartsWith(($oldDevNorm + "\"), [System.StringComparison]::OrdinalIgnoreCase))) {
                $row[$devIdx] = $newDevNorm + $curDev.Substring($oldDevNorm.Length)
                $rowChanged = $true
            }
        }

        if ($rowChanged) {
            if ($updIdx -ge 0 -and $updIdx -lt $row.Count) {
                $row[$updIdx] = $nowStr
            }
            $updated++
        }
    }

    if ($updated -gt 0) {
        Write-XlsxRows -XlsxPath $excelPath -Rows $rows
    }
    return $updated
}
