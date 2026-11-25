#requires -Version 5.1
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
    $rows = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $XlsxPath)) { return $rows }

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
            if ($null -eq $sheetEntry) { return $rows }
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
                $rows.Add($arr)
            }
        } finally {
            $zip.Dispose()
        }
    } finally {
        $fs.Dispose()
    }
    return $rows
}

function Write-XlsxRows {
    param(
        [string]$XlsxPath,
        [System.Collections.Generic.List[object]]$Rows
    )
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
    $widths = @(13, 10, 24, 22, 18, 18, 28, 14, 34, 32, 32, 26, 20, 30, 30, 10, 20)
    for ($w = 0; $w -lt $widths.Count; $w++) {
        $colNum = $w + 1
        [void]$sb.AppendLine("    <col min=`"$colNum`" max=`"$colNum`" width=`"$($widths[$w])`" customWidth=`"1`"/>")
    }
    [void]$sb.AppendLine('  </cols>')
    [void]$sb.AppendLine('  <sheetData>')

    for ($r = 0; $r -lt $Rows.Count; $r++) {
        $rowNum = $r + 1
        $styleId = if ($r -eq 0) { "1" } else { "2" }
        [void]$sb.AppendLine("    <row r=`"$rowNum`">")
        $vals = $Rows[$r]
        for ($c = 0; $c -lt $vals.Count; $c++) {
            $colRef = (ConvertTo-ExcelColName ($c + 1)) + $rowNum
            $escaped = Escape-XmlText ([string]$vals[$c])
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

    if (Test-Path -LiteralPath $XlsxPath) {
        Copy-Item -LiteralPath $XlsxPath -Destination ($XlsxPath + ".bak") -Force -ErrorAction SilentlyContinue
    }
    Move-Item -LiteralPath $tempPath -Destination $XlsxPath -Force
}

function Update-PhotoExcelLedger {
    param(
        [object]$Records,
        [hashtable]$Config = @{}
    )
    if ($null -eq $Records) { return }
    $recList = @($Records)
    if ($recList.Count -eq 0) { return }

    $excelPath = "G:\写真\現像後\写真管理一覧.xlsx"
    if ($null -ne $Config -and $Config.ContainsKey("ExcelPath") -and -not [string]::IsNullOrWhiteSpace([string]$Config["ExcelPath"])) {
        $excelPath = [string]$Config["ExcelPath"]
    }

    $headers = Get-PhotoLedgerHeaders
    $colCount = $headers.Count

    $existingRows = Read-XlsxRows -XlsxPath $excelPath
    $dataRows = New-Object System.Collections.Generic.List[object]

    if ($existingRows.Count -gt 1) {
        $oldHeader = $existingRows[0]
        for ($r = 1; $r -lt $existingRows.Count; $r++) {
            $oldRow = $existingRows[$r]
            $newRow = New-Object string[] $colCount
            for ($c = 0; $c -lt $colCount; $c++) {
                $hName = $headers[$c]
                $oldIdx = [Array]::IndexOf($oldHeader, $hName)
                if ($oldIdx -lt 0 -and $hName -eq "催事・場所名") {
                    $oldIdx = [Array]::IndexOf($oldHeader, "イベント名")
                }
                if ($oldIdx -lt 0 -and $hName -eq "モデル名") {
                    $oldIdx = [Array]::IndexOf($oldHeader, "名前")
                }
                if ($oldIdx -ge 0 -and $oldIdx -lt $oldRow.Count) {
                    $newRow[$c] = [string]$oldRow[$oldIdx]
                } else {
                    $newRow[$c] = ""
                }
            }
            $dataRows.Add($newRow)
        }
    }

    $nowStr = (Get-Date).ToString("yyyy/MM/dd HH:mm:ss")

    foreach ($rec in $recList) {
        function Get-RecVal([object]$Obj, [string]$Key, [string]$Fallback = "") {
            if ($Obj -is [hashtable]) {
                if ($Obj.ContainsKey($Key) -and $null -ne $Obj[$Key]) { return [string]$Obj[$Key] }
            } else {
                $prop = $Obj.PSObject.Properties[$Key]
                if ($null -ne $prop -and $null -ne $prop.Value) { return [string]$prop.Value }
            }
            return $Fallback
        }

        $dateStr      = Get-RecVal $rec "DateStr"
        $category     = Get-RecVal $rec "Category" "イベント"
        $eventName    = Get-RecVal $rec "EventName"
        $costume      = Get-RecVal $rec "CostumeOrChar" (Get-RecVal $rec "Costume")
        $name         = Get-RecVal $rec "Name"
        $xAccount     = Get-RecVal $rec "XAccount"
        $xUrl         = Get-RecVal $rec "XUrl"
        $multiFlag    = Get-RecVal $rec "MultiFolderFlag" (Get-RecVal $rec "MultipleFolders")
        $comment      = Get-RecVal $rec "Comment"
        $megaLink     = Get-RecVal $rec "MegaLink"
        $gigaLink     = Get-RecVal $rec "GigaFileLink"
        $relPath      = Get-RecVal $rec "RelPath"
        $folderName   = Get-RecVal $rec "FolderName"
        $importFolder = Get-RecVal $rec "ImportFolder"
        $devFolder    = Get-RecVal $rec "DevFolder"
        $personIdx    = Get-RecVal $rec "PersonIndex" "1"

        $rowArr = [string[]]@(
            $dateStr,
            $category,
            $eventName,
            $costume,
            $name,
            $xAccount,
            $xUrl,
            $multiFlag,
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
            $exRel = $ex[11]
            $exDev = $ex[14]
            $exIdx = if ([string]::IsNullOrWhiteSpace($ex[15])) { "1" } else { $ex[15] }

            $sameFolder = $false
            if (-not [string]::IsNullOrWhiteSpace($relPath) -and $exRel -eq $relPath) {
                $sameFolder = $true
            } elseif (-not [string]::IsNullOrWhiteSpace($devFolder) -and $exDev -eq $devFolder) {
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
            $dataRows.Add($rowArr)
        }
    }

    $outRows = New-Object System.Collections.Generic.List[object]
    $outRows.Add([string[]]$headers)
    foreach ($dr in $dataRows) {
        $outRows.Add($dr)
    }

    Write-XlsxRows -XlsxPath $excelPath -Rows $outRows
}
