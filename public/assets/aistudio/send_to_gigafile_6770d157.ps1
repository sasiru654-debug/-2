#requires -Version 5.1
param(
    [string]$CallbackResultFile = "",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingPaths
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ErrorActionPreference = "Stop"

# ==================================================
# パス・ディレクトリ定義
# ==================================================
$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$HistoryDir = Join-Path $BaseDir "履歴"
$ErrorLogDir = Join-Path $BaseDir "エラーログ"
$ProcessLogPath = Join-Path $BaseDir "process_log.txt"

foreach ($dir in @($HistoryDir, $ErrorLogDir)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# ==================================================
# ログ出力関数
# ==================================================
function Write-ProcessLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $ts = (Get-Date).ToString("yyyy/MM/dd HH:mm:ss.fff")
    $line = "[$ts] [$Level] $Message"
    try {
        [System.IO.File]::AppendAllText($ProcessLogPath, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    } catch {}
}

function Write-NewErrorReport {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$ConditionText,
        [string[]]$TargetPaths
    )
    $tsFile = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $tsDisp = (Get-Date).ToString("yyyy/MM/dd HH:mm:ss")
    $errFile = Join-Path $ErrorLogDir "error_log_$tsFile.txt"

    $lineNum = if ($ErrorRecord.InvocationInfo) { $ErrorRecord.InvocationInfo.ScriptLineNumber } else { "不明" }
    $lineCode = if ($ErrorRecord.InvocationInfo) { $ErrorRecord.InvocationInfo.Line.Trim() } else { "不明" }
    $errMsg = $ErrorRecord.Exception.Message
    $stack = $ErrorRecord.ScriptStackTrace

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("==================================================")
    [void]$sb.AppendLine("ギガファイル便 自動アップロードツール エラーレポート")
    [void]$sb.AppendLine("==================================================")
    [void]$sb.AppendLine("発生日時      : $tsDisp")
    [void]$sb.AppendLine("発生行番号    : $lineNum 行目")
    [void]$sb.AppendLine("エラー内容    : $errMsg")
    [void]$sb.AppendLine("該当コード    : $lineCode")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("【実行条件・対象情報】")
    [void]$sb.AppendLine($ConditionText)
    [void]$sb.AppendLine("対象パス: " + ($TargetPaths -join ", "))
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("【スタックトレース】")
    [void]$sb.AppendLine($stack)
    [void]$sb.AppendLine("==================================================")

    [System.IO.File]::WriteAllText($errFile, $sb.ToString(), [System.Text.Encoding]::UTF8)
    Write-ProcessLog "単独エラーログを新規作成しました: $errFile" "ERROR"
    return $errFile
}

# ==================================================
# 引数受け取り・事前検証
# ==================================================
$rawCandidates = @()
if ($null -ne $RemainingPaths -and $RemainingPaths.Count -gt 0) {
    $rawCandidates += $RemainingPaths
}
if ($null -ne $args -and $args.Count -gt 0) {
    $rawCandidates += $args
}

$InputPaths = @($rawCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
Write-ProcessLog "=================================================="
Write-ProcessLog "GUIツール起動 (指定パス数: $($InputPaths.Count) 件)"
if (-not [string]::IsNullOrWhiteSpace($CallbackResultFile)) {
    Write-ProcessLog "コールバック結果出力先指定あり: $CallbackResultFile"
}
if ($InputPaths.Count -gt 0) {
    Write-ProcessLog ("指定パス: " + ($InputPaths -join " | "))
}

if ($InputPaths.Count -eq 0) {
    Write-ProcessLog "対象ファイルまたはフォルダが指定されていません。" "ERROR"
    [System.Windows.Forms.MessageBox]::Show(
        "アップロードするファイルまたはフォルダを右クリックし、「送る」＞「ギガファイル便に送る」から起動してください。",
        "ギガファイル便 自動アップロードツール",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit 1
}

$ValidPaths = @()
foreach ($p in $InputPaths) {
    $cleanP = $p.Trim().Trim('"')
    if (Test-Path -LiteralPath $cleanP) {
        $ValidPaths += (Get-Item -LiteralPath $cleanP).FullName
    } else {
        Write-ProcessLog "指定されたパスが存在しません: $cleanP" "ERROR"
    }
}

if ($ValidPaths.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show(
        "指定されたファイルまたはフォルダが見つかりませんでした。",
        "エラー",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

# ==================================================
# ヘルパー関数（サイズ計算・ZIP圧縮・サーバー通信）
# ==================================================
function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Add-TreeNodesRecursive {
    param(
        [System.Windows.Forms.TreeNodeCollection]$Nodes,
        [string]$Path,
        [int]$Depth = 0
    )
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer) {
        $node = New-Object System.Windows.Forms.TreeNode("📁 $($item.Name)")
        $Nodes.Add($node) | Out-Null
        if ($Depth -lt 4) {
            $children = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Sort-Object @{Expression={$_.PSIsContainer};Descending=$true}, Name
            $count = 0
            foreach ($child in $children) {
                $count++
                if ($count -gt 100) {
                    $node.Nodes.Add((New-Object System.Windows.Forms.TreeNode("... (他 $($children.Count - 100) 項目)"))) | Out-Null
                    break
                }
                Add-TreeNodesRecursive -Nodes $node.Nodes -Path $child.FullName -Depth ($Depth + 1)
            }
        }
    } else {
        $sizeStr = Format-FileSize -Bytes $item.Length
        $node = New-Object System.Windows.Forms.TreeNode("📄 $($item.Name) ($sizeStr)")
        $Nodes.Add($node) | Out-Null
    }
}

function Add-DirectoryToZip {
    param(
        [System.IO.Compression.ZipArchive]$Archive,
        [string]$SourceDir,
        [string]$EntryPrefix
    )
    $items = Get-ChildItem -LiteralPath $SourceDir -Force -ErrorAction Stop
    if ($items.Count -eq 0) {
        $emptyDirEntry = $EntryPrefix.TrimEnd('/') + "/"
        $Archive.CreateEntry($emptyDirEntry) | Out-Null
        return
    }
    foreach ($it in $items) {
        $entryName = "$EntryPrefix/$($it.Name)"
        if ($it.PSIsContainer) {
            Add-DirectoryToZip -Archive $Archive -SourceDir $it.FullName -EntryPrefix $entryName
        } else {
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $Archive,
                $it.FullName,
                $entryName,
                [System.IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    }
}

function Create-ArchiveFromPaths {
    param(
        [string[]]$Paths,
        [string]$DestZipPath,
        [scriptblock]$OnStatus
    )
    if (Test-Path -LiteralPath $DestZipPath) {
        Remove-Item -LiteralPath $DestZipPath -Force
    }
    $fs = [System.IO.File]::Open($DestZipPath, [System.IO.FileMode]::Create)
    try {
        $archive = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create, $false, [System.Text.Encoding]::UTF8)
        try {
            $usedRootNames = @{}
            foreach ($p in $Paths) {
                $item = Get-Item -LiteralPath $p
                $baseName = $item.Name
                $entryRoot = $baseName
                $idx = 2
                while ($usedRootNames.ContainsKey($entryRoot)) {
                    if ($item.PSIsContainer) {
                        $entryRoot = "${baseName}_$idx"
                    } else {
                        $stem = [System.IO.Path]::GetFileNameWithoutExtension($baseName)
                        $ext = [System.IO.Path]::GetExtension($baseName)
                        $entryRoot = "${stem}_$idx$ext"
                    }
                    $idx++
                }
                $usedRootNames[$entryRoot] = $true

                if ($OnStatus) { & $OnStatus "ZIP圧縮中: $entryRoot" }
                if ($item.PSIsContainer) {
                    Add-DirectoryToZip -Archive $archive -SourceDir $item.FullName -EntryPrefix $entryRoot
                } else {
                    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                        $Archive,
                        $item.FullName,
                        $entryRoot,
                        [System.IO.Compression.CompressionLevel]::Optimal
                    ) | Out-Null
                }
            }
        } finally {
            $archive.Dispose()
        }
    } finally {
        $fs.Dispose()
    }
}

function Get-GigaFileServer {
    param([string]$CookiePath)
    $curlArgs = @(
        "-s", "-L",
        "-c", $CookiePath,
        "-b", $CookiePath,
        "-A", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "https://gigafile.nu/"
    )
    $raw = & curl.exe @curlArgs
    $html = ($raw -join "`n")
    $m = [regex]::Match($html, 'var\s+server\s*=\s*"([^"]+)"')
    if (-not $m.Success) {
        $m = [regex]::Match($html, '([0-9]+\.gigafile\.nu)')
    }
    if (-not $m.Success) {
        throw "ギガファイル便のアップロードサーバー名を取得できませんでした。"
    }
    $server = $m.Groups[1].Value
    $subArgs = @(
        "-s", "-L",
        "-c", $CookiePath,
        "-b", $CookiePath,
        "-A", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "https://$server/"
    )
    & curl.exe @subArgs | Out-Null
    return $server
}

function Send-FileChunked {
    param(
        [string]$FilePath,
        [string]$Server,
        [int]$LifetimeDays,
        [string]$CookiePath,
        [string]$WorkDir,
        [scriptblock]$OnProgress
    )
    $fileInfo = Get-Item -LiteralPath $FilePath
    $fileName = $fileInfo.Name
    $totalSize = $fileInfo.Length
    if ($totalSize -le 0) {
        throw "ファイルサイズが 0 バイトのためアップロードできません: $fileName"
    }

    $chunkSize = 50MB
    $totalChunks = [int][Math]::Ceiling($totalSize / $chunkSize)
    $uploadId = [Guid]::NewGuid().ToString("N")
    $uploadUrl = "https://$Server/upload_chunk.php"

    Write-ProcessLog "アップロード準備: $fileName ($(Format-FileSize $totalSize)) / チャンク数: $totalChunks"

    $finalJson = $null
    $fs = [System.IO.File]::OpenRead($FilePath)
    try {
        $buffer = New-Object byte[] $chunkSize
        for ($chunkIdx = 0; $chunkIdx -lt $totalChunks; $chunkIdx++) {
            $bytesRead = $fs.Read($buffer, 0, $chunkSize)
            $chunkFile = Join-Path $WorkDir ("chunk_" + $uploadId + "_" + $chunkIdx + ".bin")

            $cfs = [System.IO.File]::Open($chunkFile, [System.IO.FileMode]::Create)
            try {
                $cfs.Write($buffer, 0, $bytesRead)
            } finally {
                $cfs.Dispose()
            }

            try {
                $pct = [int]((($chunkIdx + 1) / $totalChunks) * 100)
                if ($OnProgress) {
                    & $OnProgress ($chunkIdx + 1) $totalChunks $pct
                }
                Write-ProcessLog "チャンク送信中: $($chunkIdx + 1) / $totalChunks ($pct%)"

                $curlArgs = @(
                    "-s", "-S",
                    "-c", $CookiePath,
                    "-b", $CookiePath,
                    "-H", "Referer: https://$Server/",
                    "-H", "Origin: https://$Server",
                    "-A", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                    "-F", "id=$uploadId",
                    "-F", "name=$fileName",
                    "-F", "chunk=$chunkIdx",
                    "-F", "chunks=$totalChunks",
                    "-F", "lifetime=$LifetimeDays",
                    "-F", "file=@$chunkFile;filename=$fileName",
                    $uploadUrl
                )
                $resRaw = & curl.exe @curlArgs
                $resText = ($resRaw -join "").Trim()
                if ([string]::IsNullOrWhiteSpace($resText)) {
                    throw "チャンク $($chunkIdx + 1) のサーバー応答が空でした。"
                }
                $json = $resText | ConvertFrom-Json
                if ($null -ne $json.status -and [int]$json.status -ne 0) {
                    throw "サーバーエラー (status=$($json.status)): $resText"
                }
                if ($chunkIdx -eq ($totalChunks - 1)) {
                    $finalJson = $json
                }
            } finally {
                if (Test-Path -LiteralPath $chunkFile) {
                    Remove-Item -LiteralPath $chunkFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
    } finally {
        $fs.Dispose()
    }

    if ($null -eq $finalJson -or [string]::IsNullOrWhiteSpace($finalJson.url)) {
        throw "アップロード完了後のURLを取得できませんでした。"
    }

    $issuedUrl = [string]$finalJson.url
    $issuedDelKey = if ($null -ne $finalJson.delkey) { [string]$finalJson.delkey } else { "（取得なし）" }
    $fileId = ($issuedUrl -split "/")[-1]

    Write-ProcessLog "全チャンク送信完了・URL発行成功: $issuedUrl (削除キー: $issuedDelKey)"

    return [PSCustomObject]@{
        Url = $issuedUrl
        DelKey = $issuedDelKey
        FileId = $fileId
        FileName = $fileName
    }
}

function Set-GigaFileDownloadPassword {
    param(
        [string]$Server,
        [string]$FileId,
        [string]$Password,
        [string]$CookiePath
    )
    if ([string]::IsNullOrWhiteSpace($Password)) { return }
    $setPassUrl = "https://$Server/set_password.php"
    $curlArgs = @(
        "-s", "-S",
        "-c", $CookiePath,
        "-b", $CookiePath,
        "-H", "Referer: https://$Server/",
        "-H", "Origin: https://$Server",
        "-A", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "-d", "file=$FileId",
        "-d", "password=$Password",
        $setPassUrl
    )
    $res = (& curl.exe @curlArgs) -join ""
    Write-ProcessLog "DLパスワード設定完了 (fileId=$FileId, 応答=$res)"
}

# ==================================================
# GUI構築（確定・固定ベースラインレイアウト）
# ==================================================
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "ギガファイル便 自動アップロードツール"
$Form.Size = New-Object System.Drawing.Size(720, 720)
$Form.MinimumSize = New-Object System.Drawing.Size(680, 680)
$Form.StartPosition = "CenterScreen"
$Form.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5)
$Form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 250)

$MarginX = 16
$ContentW = 672

# --- 第1段：対象ファイル・フォルダ ツリー表示エリア ---
$GrpTarget = New-Object System.Windows.Forms.GroupBox
$GrpTarget.Text = "1. アップロード対象（選択されたファイル・フォルダ構成）"
$GrpTarget.Location = New-Object System.Drawing.Point($MarginX, 12)
$GrpTarget.Size = New-Object System.Drawing.Size($ContentW, 185)
$GrpTarget.Anchor = "Top,Left,Right"
$Form.Controls.Add($GrpTarget)

$TreeView = New-Object System.Windows.Forms.TreeView
$TreeView.Location = New-Object System.Drawing.Point(12, 24)
$TreeView.Size = New-Object System.Drawing.Size(($ContentW - 24), 148)
$TreeView.Anchor = "Top,Bottom,Left,Right"
$TreeView.BorderStyle = "FixedSingle"
$GrpTarget.Controls.Add($TreeView)

foreach ($vp in $ValidPaths) {
    Add-TreeNodesRecursive -Nodes $TreeView.Nodes -Path $vp
}
if ($TreeView.Nodes.Count -le 5) {
    $TreeView.ExpandAll()
}

# --- 第2段：アップロード設定エリア ---
$GrpConfig = New-Object System.Windows.Forms.GroupBox
$GrpConfig.Text = "2. アップロード設定（フォルダや複数選択時は自動で1つのZIPにまとめて送信します）"
$GrpConfig.Location = New-Object System.Drawing.Point($MarginX, 205)
$GrpConfig.Size = New-Object System.Drawing.Size($ContentW, 68)
$GrpConfig.Anchor = "Top,Left,Right"
$Form.Controls.Add($GrpConfig)

$LblDays = New-Object System.Windows.Forms.Label
$LblDays.Text = "保持期限："
$LblDays.Location = New-Object System.Drawing.Point(14, 30)
$LblDays.AutoSize = $true
$GrpConfig.Controls.Add($LblDays)

$CmbDays = New-Object System.Windows.Forms.ComboBox
$CmbDays.Location = New-Object System.Drawing.Point(86, 26)
$CmbDays.Size = New-Object System.Drawing.Size(110, 26)
$CmbDays.DropDownStyle = "DropDownList"
[void]$CmbDays.Items.AddRange(@("3日", "5日", "7日", "14日", "30日", "60日", "100日"))
$CmbDays.SelectedItem = "100日"
$GrpConfig.Controls.Add($CmbDays)

$LblPass = New-Object System.Windows.Forms.Label
$LblPass.Text = "ダウンロードパスワード（任意）："
$LblPass.Location = New-Object System.Drawing.Point(230, 30)
$LblPass.AutoSize = $true
$GrpConfig.Controls.Add($LblPass)

$TxtPass = New-Object System.Windows.Forms.TextBox
$TxtPass.Location = New-Object System.Drawing.Point(435, 26)
$TxtPass.Size = New-Object System.Drawing.Size(215, 26)
$TxtPass.MaxLength = 32
$GrpConfig.Controls.Add($TxtPass)

# --- 第3段：実行ボタン＆プログレスバーエリア ---
$BtnStart = New-Object System.Windows.Forms.Button
$BtnStart.Text = "アップロード開始"
$BtnStart.Location = New-Object System.Drawing.Point($MarginX, 284)
$BtnStart.Size = New-Object System.Drawing.Size(165, 38)
$BtnStart.BackColor = [System.Drawing.Color]::FromArgb(26, 115, 232)
$BtnStart.ForeColor = [System.Drawing.Color]::White
$BtnStart.FlatStyle = "Flat"
$BtnStart.Font = New-Object System.Drawing.Font("Yu Gothic UI", 10, [System.Drawing.FontStyle]::Bold)
$Form.Controls.Add($BtnStart)

$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Location = New-Object System.Drawing.Point(192, 284)
$ProgressBar.Size = New-Object System.Drawing.Size(($ContentW - 176), 20)
$ProgressBar.Anchor = "Top,Left,Right"
$ProgressBar.Minimum = 0
$ProgressBar.Maximum = 100
$Form.Controls.Add($ProgressBar)

$LblStatus = New-Object System.Windows.Forms.Label
$LblStatus.Text = "待機中：「アップロード開始」を押してください。"
$LblStatus.Location = New-Object System.Drawing.Point(192, 307)
$LblStatus.Size = New-Object System.Drawing.Size(($ContentW - 176), 18)
$LblStatus.Anchor = "Top,Left,Right"
$LblStatus.ForeColor = [System.Drawing.Color]::FromArgb(60, 64, 67)
$Form.Controls.Add($LblStatus)

# --- 第4段：リアルタイム処理状況履歴エリア ---
$GrpLog = New-Object System.Windows.Forms.GroupBox
$GrpLog.Text = "3. リアルタイム処理状況"
$GrpLog.Location = New-Object System.Drawing.Point($MarginX, 332)
$GrpLog.Size = New-Object System.Drawing.Size($ContentW, 185)
$GrpLog.Anchor = "Top,Bottom,Left,Right"
$Form.Controls.Add($GrpLog)

$TxtStatusLog = New-Object System.Windows.Forms.TextBox
$TxtStatusLog.Location = New-Object System.Drawing.Point(12, 22)
$TxtStatusLog.Size = New-Object System.Drawing.Size(($ContentW - 24), 152)
$TxtStatusLog.Anchor = "Top,Bottom,Left,Right"
$TxtStatusLog.Multiline = $true
$TxtStatusLog.ReadOnly = $true
$TxtStatusLog.ScrollBars = "Vertical"
$TxtStatusLog.BackColor = [System.Drawing.Color]::White
$TxtStatusLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$GrpLog.Controls.Add($TxtStatusLog)

# --- 第5段：完了結果＆ユーティリティ操作エリア ---
$GrpResult = New-Object System.Windows.Forms.GroupBox
$GrpResult.Text = "4. 発行結果（完了時に履歴メモ帳も自動で開きます）"
$GrpResult.Location = New-Object System.Drawing.Point($MarginX, 525)
$GrpResult.Size = New-Object System.Drawing.Size($ContentW, 102)
$GrpResult.Anchor = "Bottom,Left,Right"
$Form.Controls.Add($GrpResult)

$LblUrl = New-Object System.Windows.Forms.Label
$LblUrl.Text = "共有URL："
$LblUrl.Location = New-Object System.Drawing.Point(12, 28)
$LblUrl.AutoSize = $true
$GrpResult.Controls.Add($LblUrl)

$TxtResultUrl = New-Object System.Windows.Forms.TextBox
$TxtResultUrl.Location = New-Object System.Drawing.Point(82, 24)
$TxtResultUrl.Size = New-Object System.Drawing.Size(376, 26)
$TxtResultUrl.Anchor = "Top,Left,Right"
$TxtResultUrl.ReadOnly = $true
$TxtResultUrl.BackColor = [System.Drawing.Color]::White
$GrpResult.Controls.Add($TxtResultUrl)

$BtnCopyUrl = New-Object System.Windows.Forms.Button
$BtnCopyUrl.Text = "URLコピー"
$BtnCopyUrl.Location = New-Object System.Drawing.Point(466, 23)
$BtnCopyUrl.Size = New-Object System.Drawing.Size(92, 27)
$BtnCopyUrl.Anchor = "Top,Right"
$BtnCopyUrl.Enabled = $false
$GrpResult.Controls.Add($BtnCopyUrl)

$BtnOpenUrl = New-Object System.Windows.Forms.Button
$BtnOpenUrl.Text = "URLを開く"
$BtnOpenUrl.Location = New-Object System.Drawing.Point(564, 23)
$BtnOpenUrl.Size = New-Object System.Drawing.Size(94, 27)
$BtnOpenUrl.Anchor = "Top,Right"
$BtnOpenUrl.Enabled = $false
$GrpResult.Controls.Add($BtnOpenUrl)

$LblDelKeyTitle = New-Object System.Windows.Forms.Label
$LblDelKeyTitle.Text = "削除キー："
$LblDelKeyTitle.Location = New-Object System.Drawing.Point(12, 65)
$LblDelKeyTitle.AutoSize = $true
$GrpResult.Controls.Add($LblDelKeyTitle)

$TxtDelKey = New-Object System.Windows.Forms.TextBox
$TxtDelKey.Location = New-Object System.Drawing.Point(82, 61)
$TxtDelKey.Size = New-Object System.Drawing.Size(140, 26)
$TxtDelKey.ReadOnly = $true
$TxtDelKey.BackColor = [System.Drawing.Color]::White
$GrpResult.Controls.Add($TxtDelKey)

$BtnCopyDelKey = New-Object System.Windows.Forms.Button
$BtnCopyDelKey.Text = "削除キーコピー"
$BtnCopyDelKey.Location = New-Object System.Drawing.Point(230, 60)
$BtnCopyDelKey.Size = New-Object System.Drawing.Size(120, 27)
$BtnCopyDelKey.Enabled = $false
$GrpResult.Controls.Add($BtnCopyDelKey)

# --- 最下部フッター操作行 ---
$BtnOpenHistory = New-Object System.Windows.Forms.Button
$BtnOpenHistory.Text = "履歴フォルダを開く"
$BtnOpenHistory.Location = New-Object System.Drawing.Point($MarginX, 636)
$BtnOpenHistory.Size = New-Object System.Drawing.Size(150, 32)
$BtnOpenHistory.Anchor = "Bottom,Left"
$Form.Controls.Add($BtnOpenHistory)

$BtnOpenErrorLog = New-Object System.Windows.Forms.Button
$BtnOpenErrorLog.Text = "エラーログフォルダを開く"
$BtnOpenErrorLog.Location = New-Object System.Drawing.Point(174, 636)
$BtnOpenErrorLog.Size = New-Object System.Drawing.Size(175, 32)
$BtnOpenErrorLog.Anchor = "Bottom,Left"
$Form.Controls.Add($BtnOpenErrorLog)

$BtnClose = New-Object System.Windows.Forms.Button
$BtnClose.Text = "閉じる"
$BtnClose.Location = New-Object System.Drawing.Point(($MarginX + $ContentW - 105), 636)
$BtnClose.Size = New-Object System.Drawing.Size(105, 32)
$BtnClose.Anchor = "Bottom,Right"
$Form.Controls.Add($BtnClose)

# ==================================================
# UI更新＆ボタンイベント処理
# ==================================================
function Append-UiLog {
    param([string]$Msg)
    $ts = (Get-Date).ToString("HH:mm:ss")
    $TxtStatusLog.AppendText("[$ts] $Msg`r`n")
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-UiStatus {
    param([string]$Text, [int]$Percent = -1)
    $LblStatus.Text = $Text
    if ($Percent -ge 0 -and $Percent -le 100) {
        $ProgressBar.Value = $Percent
    }
    [System.Windows.Forms.Application]::DoEvents()
}

$BtnCopyUrl.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($TxtResultUrl.Text)) {
        [System.Windows.Forms.Clipboard]::SetText($TxtResultUrl.Text)
        Set-UiStatus "共有URLをクリップボードにコピーしました。"
    }
})

$BtnOpenUrl.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($TxtResultUrl.Text)) {
        Start-Process $TxtResultUrl.Text
    }
})

$BtnCopyDelKey.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($TxtDelKey.Text)) {
        [System.Windows.Forms.Clipboard]::SetText($TxtDelKey.Text)
        Set-UiStatus "削除キーをクリップボードにコピーしました。"
    }
})

$BtnOpenHistory.Add_Click({
    Start-Process "explorer.exe" -ArgumentList "`"$HistoryDir`""
})

$BtnOpenErrorLog.Add_Click({
    Start-Process "explorer.exe" -ArgumentList "`"$ErrorLogDir`""
})

$BtnClose.Add_Click({
    $Form.Close()
})

$BtnStart.Add_Click({
    $BtnStart.Enabled = $false
    $CmbDays.Enabled = $false
    $TxtPass.Enabled = $false
    $BtnCopyUrl.Enabled = $false
    $BtnOpenUrl.Enabled = $false
    $BtnCopyDelKey.Enabled = $false
    $TxtResultUrl.Text = ""
    $TxtDelKey.Text = ""

    $daysStr = [string]$CmbDays.SelectedItem
    $lifetimeDays = [int]($daysStr -replace "[^0-9]", "")
    $dlPass = $TxtPass.Text.Trim()
    $condText = "保持期間: ${lifetimeDays}日 / DLパスワード: " + $(if ($dlPass) { "あり" } else { "なし" })

    Write-ProcessLog "処理開始指示: $condText"
    Append-UiLog "処理を開始します（$condText）"

    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("GigaWork_" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    Write-ProcessLog "一時作業フォルダ作成: $workDir"

    try {
        $uploadTargetFile = $null
        $targetDisplayNames = @()
        foreach ($vp in $ValidPaths) {
            $targetDisplayNames += (Get-Item -LiteralPath $vp).Name
        }

        $firstItem = Get-Item -LiteralPath $ValidPaths[0]
        if ($ValidPaths.Count -eq 1 -and (-not $firstItem.PSIsContainer)) {
            $uploadTargetFile = $firstItem.FullName
            Append-UiLog "単体ファイルをそのままアップロードします: $($firstItem.Name)"
            Set-UiStatus "アップロード準備完了..." 10
        } else {
            $zipBaseName = if ($ValidPaths.Count -eq 1) {
                $firstItem.Name
            } else {
                $parentName = Split-Path -Leaf (Split-Path -Parent $firstItem.FullName)
                if ([string]::IsNullOrWhiteSpace($parentName)) { "archive" } else { $parentName }
            }
            $zipName = "${zipBaseName}_" + (Get-Date).ToString("yyyyMMdd_HHmmss") + ".zip"
            $uploadTargetFile = Join-Path $workDir $zipName

            Append-UiLog "ZIPファイルを作成しています: $zipName"
            Set-UiStatus "ZIPファイル作成中..." 5
            Write-ProcessLog "ZIP圧縮開始: $uploadTargetFile"

            Create-ArchiveFromPaths -Paths $ValidPaths -DestZipPath $uploadTargetFile -OnStatus {
                param($s)
                Set-UiStatus $s 10
            }

            $zipSize = (Get-Item -LiteralPath $uploadTargetFile).Length
            Append-UiLog "ZIP作成完了 ($(Format-FileSize $zipSize))"
            Write-ProcessLog "ZIP圧縮完了: $uploadTargetFile ($(Format-FileSize $zipSize))"
        }

        Append-UiLog "ギガファイル便サーバーに接続中..."
        Set-UiStatus "アップロードサーバーを取得中..." 15
        $cookiePath = Join-Path $workDir "session_cookies.txt"
        $server = Get-GigaFileServer -CookiePath $cookiePath
        Append-UiLog "アップロードサーバー確定: $server"
        Write-ProcessLog "アップロードサーバー確定: $server"

        $res = Send-FileChunked -FilePath $uploadTargetFile -Server $server -LifetimeDays $lifetimeDays -CookiePath $cookiePath -WorkDir $workDir -OnProgress {
            param($cur, $tot, $pct)
            $barVal = 15 + [int]($pct * 0.75)
            Set-UiStatus "アップロード中 ($cur / $tot チャンク - $pct%)" $barVal
        }

        if (-not [string]::IsNullOrWhiteSpace($dlPass)) {
            Append-UiLog "ダウンロードパスワードを設定中..."
            Set-UiStatus "ダウンロードパスワードを設定中..." 93
            Set-GigaFileDownloadPassword -Server $server -FileId $res.FileId -Password $dlPass -CookiePath $cookiePath
        }

        Set-UiStatus "履歴ファイルを保存中..." 97
        $nowDisp = (Get-Date).ToString("yyyy/MM/dd HH:mm:ss")
        $histFileName = "gigafile_" + (Get-Date).ToString("yyyyMMdd_HHmmss") + ".txt"
        $histFilePath = Join-Path $HistoryDir $histFileName
        $passDisp = if ([string]::IsNullOrWhiteSpace($dlPass)) { "なし" } else { $dlPass }

        $hsb = New-Object System.Text.StringBuilder
        [void]$hsb.AppendLine("==================================================")
        [void]$hsb.AppendLine("【メール送信用（コピーしてそのまま相手にお送りください）】")
        [void]$hsb.AppendLine("==================================================")
        [void]$hsb.AppendLine("ダウンロードURL：")
        [void]$hsb.AppendLine($res.Url)
        [void]$hsb.AppendLine("")
        [void]$hsb.AppendLine("ダウンロードパスワード：$passDisp")
        [void]$hsb.AppendLine("保持期限：${lifetimeDays}日")
        [void]$hsb.AppendLine("")
        [void]$hsb.AppendLine("対象ファイル：")
        foreach ($dn in $targetDisplayNames) {
            [void]$hsb.AppendLine("・$dn")
        }
        [void]$hsb.AppendLine("==================================================")
        [void]$hsb.AppendLine("")
        [void]$hsb.AppendLine("--------------------------------------------------")
        [void]$hsb.AppendLine("【自分用 管理メモ（相手には送らないでください）】")
        [void]$hsb.AppendLine("--------------------------------------------------")
        [void]$hsb.AppendLine("アップロード日時：$nowDisp")
        [void]$hsb.AppendLine("削除パスワード  ：$($res.DelKey)")
        [void]$hsb.AppendLine("--------------------------------------------------")

        [System.IO.File]::WriteAllText($histFilePath, $hsb.ToString(), [System.Text.Encoding]::UTF8)
        Write-ProcessLog "履歴ファイルを保存しました: $histFilePath"

        if (-not [string]::IsNullOrWhiteSpace($CallbackResultFile)) {
            try {
                $cbObj = [ordered]@{
                    Url          = $res.Url
                    DelKey       = $res.DelKey
                    Password     = $dlPass
                    LifetimeDays = $lifetimeDays
                    UploadedAt   = $nowDisp
                }
                $cbJson = $cbObj | ConvertTo-Json -Depth 3
                $utf8Bom = New-Object System.Text.UTF8Encoding($true)
                [System.IO.File]::WriteAllText($CallbackResultFile, $cbJson, $utf8Bom)
                Write-ProcessLog "コールバック結果JSONを出力しました: $CallbackResultFile"
            } catch {
                Write-ProcessLog ("コールバック結果JSON出力エラー: " + $_.Exception.Message) "ERROR"
            }
        }

        [System.Windows.Forms.Clipboard]::SetText($res.Url)
        $TxtResultUrl.Text = $res.Url
        $TxtDelKey.Text = $res.DelKey
        $BtnCopyUrl.Enabled = $true
        $BtnOpenUrl.Enabled = $true
        $BtnCopyDelKey.Enabled = $true

        Set-UiStatus "アップロード完了！（URLをクリップボードへ自動コピーしました）" 100
        Append-UiLog "すべての処理が正常に完了しました！"
        Append-UiLog "共有URL: $($res.Url)"
        Append-UiLog "削除キー: $($res.DelKey)"

        if ([string]::IsNullOrWhiteSpace($CallbackResultFile)) {
            Start-Process "notepad.exe" -ArgumentList "`"$histFilePath`""
        }

    } catch {
        $errRec = $_
        Write-ProcessLog ("エラー発生: " + $errRec.Exception.Message) "ERROR"
        $errFile = Write-NewErrorReport -ErrorRecord $errRec -ConditionText $condText -TargetPaths $ValidPaths
        Set-UiStatus "エラーが発生しました。詳細はエラーログを確認してください。" 0
        Append-UiLog "[エラー] $($errRec.Exception.Message)"
        Append-UiLog "エラーレポート保存先: $errFile"

        [System.Windows.Forms.MessageBox]::Show(
            "アップロード処理中にエラーが発生しました。`r`n`r`n内容: $($errRec.Exception.Message)`r`n`r`n新規エラーログを保存しました:`r`n$errFile",
            "アップロードエラー",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } finally {
        if (Test-Path -LiteralPath $workDir) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-ProcessLog "一時作業フォルダを削除しました。"
        }
        $BtnStart.Enabled = $true
        $CmbDays.Enabled = $true
        $TxtPass.Enabled = $true
    }
})

$Form.Add_FormClosing({
    Write-ProcessLog "GUI画面を閉じました。"
})

Write-ProcessLog "画面の準備が完了しました。"
[void]$Form.ShowDialog()
