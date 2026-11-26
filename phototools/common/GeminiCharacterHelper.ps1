#requires -Version 5.1
# ==============================================================================
# GeminiCharacterHelper.ps1 - 漏洩対策付き AIキャラ名判定ヘルパー (UTF-8 BOM / CRLF)
#   - APIキーは Windows DPAPI (CurrentUser) で data\gemini_api_key.dat に暗号化保存
#   - 画像はメモリ上のみで Exif完全除去・縮小・顔マスク適用（一時ファイル生成なし）
#   - モデル名・Xアカウント・日付・ファイル名等の個人情報はAPIへ一切送信しない
# ==============================================================================

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security

$script:GeminiKeyEntropy = [System.Text.Encoding]::UTF8.GetBytes("PhotoTools.GeminiCharacterHelper.DPAPI.v1")

function Get-GeminiDataDir {
    param(
        [string]$RootDir = "",
        [hashtable]$Config = @{}
    )
    if ($null -ne $Config -and $Config.ContainsKey("DataDir") -and -not [string]::IsNullOrWhiteSpace([string]$Config["DataDir"])) {
        return [string]$Config["DataDir"]
    }
    if ([string]::IsNullOrWhiteSpace($RootDir)) {
        $sd = $PSScriptRoot
        if ([string]::IsNullOrWhiteSpace($sd)) { $sd = "D:\PhotoTools\common" }
        $RootDir = Split-Path -Parent $sd
    }
    return (Join-Path $RootDir "data")
}

function Get-GeminiSettingsPath {
    param(
        [string]$RootDir = "",
        [hashtable]$Config = @{}
    )
    $dataDir = Get-GeminiDataDir -RootDir $RootDir -Config $Config
    return (Join-Path $dataDir "ai_character_settings.json")
}

function Get-GeminiKeyPath {
    param(
        [string]$RootDir = "",
        [hashtable]$Config = @{}
    )
    $dataDir = Get-GeminiDataDir -RootDir $RootDir -Config $Config
    return (Join-Path $dataDir "gemini_api_key.dat")
}

function Get-DefaultGeminiCharacterSettings {
    return [ordered]@{
        Version             = 1
        ModelName           = "gemini-2.5-flash"
        PaidTierConfirmed   = $false
        MaxImageEdgePx      = 640
        JpegQuality         = 75
        DefaultMaskStyle    = "Black"
        DefaultOutputFormat = "CharWithSeries"
    }
}

function Get-GeminiCharacterSettings {
    param(
        [string]$SettingsPath = "",
        [string]$RootDir = "",
        [hashtable]$Config = @{}
    )
    if ([string]::IsNullOrWhiteSpace($SettingsPath)) {
        $SettingsPath = Get-GeminiSettingsPath -RootDir $RootDir -Config $Config
    }
    $def = Get-DefaultGeminiCharacterSettings
    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        return $def
    }
    try {
        $raw = [System.IO.File]::ReadAllText($SettingsPath, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $def }
        $obj = $raw | ConvertFrom-Json
        if ($null -eq $obj) { return $def }
        $res = Get-DefaultGeminiCharacterSettings
        if ($null -ne $obj.PSObject.Properties["ModelName"] -and -not [string]::IsNullOrWhiteSpace([string]$obj.ModelName)) {
            $res["ModelName"] = ([string]$obj.ModelName).Trim()
        }
        if ($null -ne $obj.PSObject.Properties["PaidTierConfirmed"]) {
            $res["PaidTierConfirmed"] = [bool]$obj.PaidTierConfirmed
        }
        if ($null -ne $obj.PSObject.Properties["MaxImageEdgePx"]) {
            $px = 640
            if ([int]::TryParse([string]$obj.MaxImageEdgePx, [ref]$px)) {
                if ($px -ge 320 -and $px -le 1280) { $res["MaxImageEdgePx"] = $px }
            }
        }
        if ($null -ne $obj.PSObject.Properties["JpegQuality"]) {
            $q = 75
            if ([int]::TryParse([string]$obj.JpegQuality, [ref]$q)) {
                if ($q -ge 40 -and $q -le 95) { $res["JpegQuality"] = $q }
            }
        }
        if ($null -ne $obj.PSObject.Properties["DefaultMaskStyle"]) {
            $ms = ([string]$obj.DefaultMaskStyle).Trim()
            if ($ms -in @("Black", "Mosaic")) { $res["DefaultMaskStyle"] = $ms }
        }
        if ($null -ne $obj.PSObject.Properties["DefaultOutputFormat"]) {
            $of = ([string]$obj.DefaultOutputFormat).Trim()
            if ($of -in @("CharWithSeries", "CharOnly", "SeriesSlashChar")) { $res["DefaultOutputFormat"] = $of }
        }
        return $res
    } catch {
        return $def
    }
}

function Save-GeminiCharacterSettings {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Settings,
        [string]$SettingsPath = "",
        [string]$RootDir = "",
        [hashtable]$Config = @{}
    )
    if ([string]::IsNullOrWhiteSpace($SettingsPath)) {
        $SettingsPath = Get-GeminiSettingsPath -RootDir $RootDir -Config $Config
    }
    $dir = Split-Path -Parent $SettingsPath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $payload = [ordered]@{
        Version             = 1
        ModelName           = if ($Settings.Contains("ModelName") -and -not [string]::IsNullOrWhiteSpace([string]$Settings["ModelName"])) { ([string]$Settings["ModelName"]).Trim() } else { "gemini-2.5-flash" }
        PaidTierConfirmed   = if ($Settings.Contains("PaidTierConfirmed")) { [bool]$Settings["PaidTierConfirmed"] } else { $false }
        MaxImageEdgePx      = if ($Settings.Contains("MaxImageEdgePx")) { [int]$Settings["MaxImageEdgePx"] } else { 640 }
        JpegQuality         = if ($Settings.Contains("JpegQuality")) { [int]$Settings["JpegQuality"] } else { 75 }
        DefaultMaskStyle    = if ($Settings.Contains("DefaultMaskStyle") -and ([string]$Settings["DefaultMaskStyle"]) -in @("Black", "Mosaic")) { [string]$Settings["DefaultMaskStyle"] } else { "Black" }
        DefaultOutputFormat = if ($Settings.Contains("DefaultOutputFormat") -and ([string]$Settings["DefaultOutputFormat"]) -in @("CharWithSeries", "CharOnly", "SeriesSlashChar")) { [string]$Settings["DefaultOutputFormat"] } else { "CharWithSeries" }
    }
    $json = ($payload | ConvertTo-Json -Depth 4) -replace "`r?`n", "`r`n"
    [System.IO.File]::WriteAllText($SettingsPath, $json + "`r`n", (New-Object System.Text.UTF8Encoding($true)))
    return $SettingsPath
}

function Test-GeminiApiKeyStored {
    param(
        [string]$KeyPath = "",
        [string]$RootDir = "",
        [hashtable]$Config = @{}
    )
    if ([string]::IsNullOrWhiteSpace($KeyPath)) {
        $KeyPath = Get-GeminiKeyPath -RootDir $RootDir -Config $Config
    }
    if (-not (Test-Path -LiteralPath $KeyPath)) { return $false }
    try {
        $fi = Get-Item -LiteralPath $KeyPath -ErrorAction Stop
        return ($fi.Length -gt 0)
    } catch {
        return $false
    }
}

function Save-GeminiApiKeyProtected {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PlainApiKey,
        [string]$KeyPath = "",
        [string]$RootDir = "",
        [hashtable]$Config = @{}
    )
    $trimmed = $PlainApiKey.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw "APIキーが空です。"
    }
    if ([string]::IsNullOrWhiteSpace($KeyPath)) {
        $KeyPath = Get-GeminiKeyPath -RootDir $RootDir -Config $Config
    }
    $dir = Split-Path -Parent $KeyPath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($trimmed)
    try {
        $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
            $plainBytes,
            $script:GeminiKeyEntropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        [System.IO.File]::WriteAllBytes($KeyPath, $protectedBytes)
        return $KeyPath
    } finally {
        [Array]::Clear($plainBytes, 0, $plainBytes.Length)
    }
}

function Get-GeminiApiKeyDecrypted {
    param(
        [string]$KeyPath = "",
        [string]$RootDir = "",
        [hashtable]$Config = @{}
    )
    if ([string]::IsNullOrWhiteSpace($KeyPath)) {
        $KeyPath = Get-GeminiKeyPath -RootDir $RootDir -Config $Config
    }
    if (-not (Test-Path -LiteralPath $KeyPath)) {
        return ""
    }
    $protectedBytes = [System.IO.File]::ReadAllBytes($KeyPath)
    if ($null -eq $protectedBytes -or $protectedBytes.Length -eq 0) {
        return ""
    }
    $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $protectedBytes,
        $script:GeminiKeyEntropy,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    try {
        return [System.Text.Encoding]::UTF8.GetString($plainBytes).Trim()
    } finally {
        [Array]::Clear($plainBytes, 0, $plainBytes.Length)
    }
}

function Remove-GeminiApiKeyProtected {
    param(
        [string]$KeyPath = "",
        [string]$RootDir = "",
        [hashtable]$Config = @{}
    )
    if ([string]::IsNullOrWhiteSpace($KeyPath)) {
        $KeyPath = Get-GeminiKeyPath -RootDir $RootDir -Config $Config
    }
    if (Test-Path -LiteralPath $KeyPath) {
        Remove-Item -LiteralPath $KeyPath -Force
        return $true
    }
    return $false
}

function Format-CharacterResultText {
    param(
        [string]$CharacterName = "",
        [string]$SeriesName = "",
        [string]$FormatType = "CharWithSeries"
    )
    $c = if ($null -eq $CharacterName) { "" } else { $CharacterName.Trim() }
    $s = if ($null -eq $SeriesName) { "" } else { $SeriesName.Trim() }

    switch ($FormatType) {
        "CharOnly" {
            if (-not [string]::IsNullOrWhiteSpace($c)) { return $c }
            return $s
        }
        "SeriesSlashChar" {
            if (-not [string]::IsNullOrWhiteSpace($s) -and -not [string]::IsNullOrWhiteSpace($c)) {
                return "${s} / ${c}"
            }
            if (-not [string]::IsNullOrWhiteSpace($c)) { return $c }
            return $s
        }
        default {
            # CharWithSeries: キャラ名（作品名）
            if (-not [string]::IsNullOrWhiteSpace($c) -and -not [string]::IsNullOrWhiteSpace($s)) {
                return "${c}（${s}）"
            }
            if (-not [string]::IsNullOrWhiteSpace($c)) { return $c }
            return $s
        }
    }
}

function Get-FolderCandidateImages {
    param(
        [string[]]$FolderPaths = @()
    )
    $exts = @(".jpg", ".jpeg", ".png", ".bmp")
    $seenNames = @{}
    $results = New-Object System.Collections.ArrayList

    foreach ($fp in @($FolderPaths)) {
        if ([string]::IsNullOrWhiteSpace($fp)) { continue }
        $norm = $fp.Trim().TrimEnd('\')
        if (-not (Test-Path -LiteralPath $norm -PathType Container)) { continue }
        $files = @(Get-ChildItem -LiteralPath $norm -File -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($fi in $files) {
            $extLower = $fi.Extension.ToLowerInvariant()
            if ($exts -notcontains $extLower) { continue }
            $key = $fi.Name.ToLowerInvariant()
            if ($seenNames.ContainsKey($key)) { continue }
            $seenNames[$key] = $true
            [void]$results.Add([PSCustomObject]@{
                Name     = $fi.Name
                FullName = $fi.FullName
                DirName  = Split-Path -Leaf $norm
                SizeKB   = [Math]::Round($fi.Length / 1024.0, 1)
            })
        }
    }
    return @($results.ToArray())
}

function Apply-ExifOrientationInPlace {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Image]$Image
    )
    try {
        $propIds = @($Image.PropertyIdList)
        if ($propIds -contains 0x0112) {
            $prop = $Image.GetPropertyItem(0x0112)
            if ($null -ne $prop -and $null -ne $prop.Value -and $prop.Value.Length -ge 2) {
                $orient = [BitConverter]::ToUInt16($prop.Value, 0)
                switch ($orient) {
                    2 { $Image.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX) }
                    3 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone) }
                    4 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipX) }
                    5 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipX) }
                    6 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone) }
                    7 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipX) }
                    8 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipNone) }
                }
            }
        }
    } catch {}
}

function New-DisplayBitmapWithoutLock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath
    )
    $bytes = [System.IO.File]::ReadAllBytes($ImagePath)
    $ms = New-Object System.IO.MemoryStream(,$bytes)
    $src = $null
    try {
        $src = [System.Drawing.Image]::FromStream($ms)
        Apply-ExifOrientationInPlace -Image $src
        $bmp = New-Object System.Drawing.Bitmap($src.Width, $src.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.DrawImage($src, 0, 0, $src.Width, $src.Height)
        } finally {
            $g.Dispose()
        }
        return $bmp
    } finally {
        if ($null -ne $src) { $src.Dispose() }
        $ms.Dispose()
    }
}

function Apply-MosaicBlockToBitmap {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Bitmap]$Bitmap,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height
    )
    $x0 = [Math]::Max(0, $X)
    $y0 = [Math]::Max(0, $Y)
    $x1 = [Math]::Min($Bitmap.Width, $X + $Width)
    $y1 = [Math]::Min($Bitmap.Height, $Y + $Height)
    if ($x1 -le $x0 -or $y1 -le $y0) { return }

    $blockSize = [Math]::Max(10, [int][Math]::Floor([Math]::Min(($x1 - $x0), ($y1 - $y0)) / 5.0))
    if ($blockSize -lt 10) { $blockSize = 10 }
    if ($blockSize -gt 24) { $blockSize = 24 }

    $g = [System.Drawing.Graphics]::FromImage($Bitmap)
    try {
        for ($by = $y0; $by -lt $y1; $by += $blockSize) {
            for ($bx = $x0; $bx -lt $x1; $bx += $blockSize) {
                $bw = [Math]::Min($blockSize, $x1 - $bx)
                $bh = [Math]::Min($blockSize, $y1 - $by)
                $sampleX = [Math]::Min($Bitmap.Width - 1, $bx + [int]($bw / 2))
                $sampleY = [Math]::Min($Bitmap.Height - 1, $by + [int]($bh / 2))
                $c = $Bitmap.GetPixel($sampleX, $sampleY)
                $br = New-Object System.Drawing.SolidBrush($c)
                try {
                    $g.FillRectangle($br, $bx, $by, $bw, $bh)
                } finally {
                    $br.Dispose()
                }
            }
        }
    } finally {
        $g.Dispose()
    }
}

function New-SanitizedImagePayload {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath,
        [object[]]$MaskRectsNormalized = @(),
        [string]$MaskStyle = "Black",
        [int]$MaxEdgePx = 640,
        [int]$JpegQuality = 75
    )
    if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
        throw "画像ファイルが見つかりません: $ImagePath"
    }
    if ($MaxEdgePx -lt 256) { $MaxEdgePx = 256 }
    if ($MaxEdgePx -gt 1280) { $MaxEdgePx = 1280 }
    if ($JpegQuality -lt 40) { $JpegQuality = 40 }
    if ($JpegQuality -gt 95) { $JpegQuality = 95 }

    $srcBmp = $null
    $dstBmp = $null
    $outMs = $null
    try {
        $srcBmp = New-DisplayBitmapWithoutLock -ImagePath $ImagePath
        $origW = $srcBmp.Width
        $origH = $srcBmp.Height
        $scale = 1.0
        $maxDim = [Math]::Max($origW, $origH)
        if ($maxDim -gt $MaxEdgePx) {
            $scale = [double]$MaxEdgePx / [double]$maxDim
        }
        $dstW = [Math]::Max(1, [int][Math]::Round($origW * $scale))
        $dstH = [Math]::Max(1, [int][Math]::Round($origH * $scale))

        # 新規Bitmapへ描画することでExif/IPTC/XMPメタデータを100%除去
        $dstBmp = New-Object System.Drawing.Bitmap($dstW, $dstH, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $g = [System.Drawing.Graphics]::FromImage($dstBmp)
        try {
            $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.DrawImage($srcBmp, 0, 0, $dstW, $dstH)
        } finally {
            $g.Dispose()
        }

        $appliedMasks = 0
        foreach ($rect in @($MaskRectsNormalized)) {
            if ($null -eq $rect) { continue }
            $rx = [int][Math]::Round([double]$rect.X * $dstW)
            $ry = [int][Math]::Round([double]$rect.Y * $dstH)
            $rw = [int][Math]::Round([double]$rect.W * $dstW)
            $rh = [int][Math]::Round([double]$rect.H * $dstH)
            if ($rw -lt 2 -or $rh -lt 2) { continue }
            if ($MaskStyle -eq "Mosaic") {
                Apply-MosaicBlockToBitmap -Bitmap $dstBmp -X $rx -Y $ry -Width $rw -Height $rh
            } else {
                $gm = [System.Drawing.Graphics]::FromImage($dstBmp)
                $br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(20, 20, 20))
                try {
                    $gm.FillRectangle($br, $rx, $ry, $rw, $rh)
                } finally {
                    $br.Dispose()
                    $gm.Dispose()
                }
            }
            $appliedMasks++
        }

        $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" } | Select-Object -First 1
        $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$JpegQuality)

        $outMs = New-Object System.IO.MemoryStream
        try {
            if ($null -ne $jpegCodec) {
                $dstBmp.Save($outMs, $jpegCodec, $encParams)
            } else {
                $dstBmp.Save($outMs, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            }
        } finally {
            $encParams.Dispose()
        }

        $jpegBytes = $outMs.ToArray()
        $b64 = [Convert]::ToBase64String($jpegBytes)
        return @{
            Base64       = $b64
            MimeType     = "image/jpeg"
            Width        = $dstW
            Height       = $dstH
            OrigWidth    = $origW
            OrigHeight   = $origH
            ByteLength   = $jpegBytes.Length
            MaskCount    = $appliedMasks
            PreviewBytes = $jpegBytes
        }
    } finally {
        if ($null -ne $outMs) { $outMs.Dispose() }
        if ($null -ne $dstBmp) { $dstBmp.Dispose() }
        if ($null -ne $srcBmp) { $srcBmp.Dispose() }
    }
}

function Convert-HttpWebErrorMessage {
    param(
        $ExceptionObj,
        [string]$ModelName = ""
    )
    $statusCode = 0
    $bodyText = ""
    try {
        $resp = $ExceptionObj.Response
        if ($null -ne $resp) {
            $statusCode = [int]$resp.StatusCode
            $stream = $resp.GetResponseStream()
            if ($null -ne $stream) {
                $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                $bodyText = $reader.ReadToEnd()
                $reader.Dispose()
            }
        }
    } catch {}

    if ($statusCode -eq 400) {
        return "APIリクエストエラー (400): APIキー形式またはリクエスト内容を確認してください。`n$bodyText"
    }
    if ($statusCode -eq 401 -or $statusCode -eq 403) {
        return "認証エラー ($statusCode): APIキーが無効か権限がありません。AI設定タブでAPIキーを確認してください。"
    }
    if ($statusCode -eq 404) {
        return "モデル未検出 (404): 指定モデル '$ModelName' が見つかりません。AI設定タブでモデル名（例: gemini-2.5-flash）を確認してください。"
    }
    if ($statusCode -eq 429) {
        return "レート制限/上限エラー (429): リクエスト上限に達しました。Google Cloud の請求先設定・クォータを確認のうえ少し待って再試行してください。"
    }
    if ($statusCode -gt 0) {
        return "Gemini API エラー (HTTP $statusCode): $bodyText"
    }
    return "通信エラー: $($ExceptionObj.Message)"
}

function Test-GeminiApiConnection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiKey,
        [string]$ModelName = "gemini-2.5-flash"
    )
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        throw "APIキーが入力されていません。"
    }
    if ([string]::IsNullOrWhiteSpace($ModelName)) {
        $ModelName = "gemini-2.5-flash"
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $url = "https://generativelanguage.googleapis.com/v1beta/models/$($ModelName.Trim())"
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Method = "GET"
    $req.Timeout = 15000
    $req.Headers.Add("x-goog-api-key", $ApiKey.Trim())

    try {
        $resp = $req.GetResponse()
        try {
            $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $raw = $sr.ReadToEnd()
            $sr.Dispose()
            $obj = $raw | ConvertFrom-Json
            $disp = if ($null -ne $obj -and $null -ne $obj.PSObject.Properties["displayName"]) { [string]$obj.displayName } else { $ModelName }
            return @{
                Success     = $true
                ModelName   = $ModelName
                DisplayName = $disp
            }
        } finally {
            $resp.Close()
        }
    } catch {
        $msg = Convert-HttpWebErrorMessage -ExceptionObj $_.Exception -ModelName $ModelName
        throw $msg
    }
}

function Invoke-GeminiCharacterLookup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Base64Image,
        [string]$MimeType = "image/jpeg",
        [Parameter(Mandatory = $true)]
        [string]$ApiKey,
        [string]$ModelName = "gemini-2.5-flash",
        [string]$ExtraHint = ""
    )
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        throw "Gemini APIキーが未設定です。設定画面の「AIキャラ判定」タブから登録してください。"
    }
    if ([string]::IsNullOrWhiteSpace($Base64Image)) {
        throw "送信する画像データが空です。"
    }
    if ([string]::IsNullOrWhiteSpace($ModelName)) {
        $ModelName = "gemini-2.5-flash"
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $hintSection = ""
    if (-not [string]::IsNullOrWhiteSpace($ExtraHint)) {
        $hintSection = "`n補足ヒント（作品ジャンル等）: $($ExtraHint.Trim())"
    }

    $promptText = @"
このコスプレ写真の衣装・髪型・小物・配色から、元の作品名とキャラクター名を推定してください。
顔がマスク（黒塗り・モザイク）で隠されている場合は、衣装・髪型・アクセサリー・小物のみを手がかりにしてください。
実在人物の特定は行わず、フィクションのキャラクター名と作品名（または創作・オリジナル衣装である旨）のみを日本語で最大5件、確信度が高い順に返してください。$hintSection
"@

    $reqBodyObj = @{
        contents = @(
            @{
                parts = @(
                    @{
                        inline_data = @{
                            mime_type = $MimeType
                            data      = $Base64Image
                        }
                    },
                    @{
                        text = $promptText
                    }
                )
            }
        )
        generationConfig = @{
            responseMimeType = "application/json"
            responseSchema   = @{
                type       = "OBJECT"
                properties = @{
                    candidates = @{
                        type  = "ARRAY"
                        items = @{
                            type       = "OBJECT"
                            properties = @{
                                characterName = @{ type = "STRING" }
                                seriesName    = @{ type = "STRING" }
                                confidence    = @{ type = "STRING" }
                                reason        = @{ type = "STRING" }
                            }
                            required = @("characterName", "seriesName", "confidence", "reason")
                        }
                    }
                }
                required = @("candidates")
            }
        }
    }

    $jsonPayload = $reqBodyObj | ConvertTo-Json -Depth 12 -Compress
    $payloadBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)

    $url = "https://generativelanguage.googleapis.com/v1beta/models/$($ModelName.Trim()):generateContent"
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Method = "POST"
    $req.ContentType = "application/json; charset=utf-8"
    $req.Timeout = 45000
    $req.ContentLength = $payloadBytes.Length
    $req.Headers.Add("x-goog-api-key", $ApiKey.Trim())

    $reqStream = $req.GetRequestStream()
    try {
        $reqStream.Write($payloadBytes, 0, $payloadBytes.Length)
    } finally {
        $reqStream.Dispose()
    }

    try {
        $resp = $req.GetResponse()
        $rawText = ""
        try {
            $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $rawText = $sr.ReadToEnd()
            $sr.Dispose()
        } finally {
            $resp.Close()
        }

        $respObj = $rawText | ConvertFrom-Json
        $outText = ""
        if ($null -ne $respObj -and $null -ne $respObj.candidates -and @($respObj.candidates).Count -gt 0) {
            $parts = @($respObj.candidates[0].content.parts)
            foreach ($pt in $parts) {
                if ($null -ne $pt.PSObject.Properties["text"] -and -not [string]::IsNullOrWhiteSpace([string]$pt.text)) {
                    $outText += [string]$pt.text
                }
            }
        }
        $cleanJson = $outText.Trim()
        if ($cleanJson -match '(?s)^```(?:json)?\s*(.*?)\s*```$') {
            $cleanJson = $Matches[1].Trim()
        }
        if ([string]::IsNullOrWhiteSpace($cleanJson)) {
            throw "AIからの応答が空でした。"
        }

        $parsed = $cleanJson | ConvertFrom-Json
        $candList = New-Object System.Collections.ArrayList
        $rawCands = if ($null -ne $parsed -and $null -ne $parsed.PSObject.Properties["candidates"]) {
            @($parsed.candidates)
        } elseif ($parsed -is [System.Collections.IEnumerable]) {
            @($parsed)
        } else { @() }

        foreach ($c in $rawCands) {
            if ($null -eq $c) { continue }
            $cn = if ($null -ne $c.PSObject.Properties["characterName"]) { ([string]$c.characterName).Trim() } else { "" }
            $sn = if ($null -ne $c.PSObject.Properties["seriesName"])    { ([string]$c.seriesName).Trim() } else { "" }
            $cf = if ($null -ne $c.PSObject.Properties["confidence"])    { ([string]$c.confidence).Trim() } else { "中" }
            $rs = if ($null -ne $c.PSObject.Properties["reason"])        { ([string]$c.reason).Trim() } else { "" }
            if ([string]::IsNullOrWhiteSpace($cn) -and [string]::IsNullOrWhiteSpace($sn)) { continue }
            [void]$candList.Add([PSCustomObject]@{
                CharacterName = $cn
                SeriesName    = $sn
                Confidence    = $cf
                Reason        = $rs
            })
        }
        return @($candList.ToArray())
    } catch {
        if ($_.Exception -is [System.Net.WebException]) {
            $msg = Convert-HttpWebErrorMessage -ExceptionObj $_.Exception -ModelName $ModelName
            throw $msg
        }
        throw
    }
}
