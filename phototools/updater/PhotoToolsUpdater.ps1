#requires -Version 5.1
# ==============================================================================
# PhotoToolsUpdater.ps1
# 単独動作する PhotoTools 自動更新支援ツール (WinForms GUI / 完全自己完結)
# - ローカルダウンロードフォルダからの最新ZIP自動選択 (ブラウザ連番 (1)(2)... 同一視)
# - GitHub リポジトリからの最新ブランチZIP自動ダウンロード (公開 / PAT非公開対応)
# - ZIP階層自動判定 (PhotoTools.zip / GitHub archive-main\phototools 両対応)
# - 更新前自動バックアップ (backup\YYYYMMDD_HHMMSS、直近5世代保持)
# - settings.ini 保護 (既存値維持＋新規キー追記マージ / 完全スキップ切替)
# - data\・backup\・updater_settings.json 完全保護
# - 展開・コピー後の Unblock-File 自動実行
# - 不要ファイルのチェックリスト確認ダイアログによる安全削除
# ==============================================================================
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.Windows.Forms.Application]::EnableVisualStyles()

$Script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:SettingsPath = Join-Path $Script:ScriptDir 'updater_settings.json'
$Script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)

function Write-Utf8BomText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $normalized = ($Content -replace "`r`n", "`n" -replace "`r", "`n") -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText($Path, $normalized, $Script:Utf8Bom)
}

function Get-DefaultTargetDir {
    $parentDir = Split-Path -Parent $Script:ScriptDir
    if (-not [string]::IsNullOrWhiteSpace($parentDir)) {
        if (Test-Path -LiteralPath (Join-Path $parentDir 'PhotoToolsMaster.ps1')) {
            return $parentDir
        }
    }
    if (Test-Path -LiteralPath (Join-Path $Script:ScriptDir 'PhotoToolsMaster.ps1')) {
        return $Script:ScriptDir
    }
    return 'D:\PhotoTools'
}

function Get-DefaultDownloadDir {
    $dl = Join-Path $env:USERPROFILE 'Downloads'
    if (Test-Path -LiteralPath $dl) { return $dl }
    return $env:USERPROFILE
}

function Load-UpdaterSettings {
    $defaults = [ordered]@{
        DownloadDir           = Get-DefaultDownloadDir
        BaseFileName          = 'PhotoTools.zip'
        TargetDir             = Get-DefaultTargetDir
        GitHubRepo            = ''
        GitHubBranch          = 'main'
        SettingsIniMode       = 'Merge'
        EnableBackup          = $true
        KeepBackupCount       = 5
        AutoUnblock           = $true
        ConfirmDeleteObsolete = $true
    }
    if (-not (Test-Path -LiteralPath $Script:SettingsPath)) {
        return [PSCustomObject]$defaults
    }
    try {
        $raw = [System.IO.File]::ReadAllText($Script:SettingsPath, [System.Text.Encoding]::UTF8)
        $loaded = $raw | ConvertFrom-Json
        foreach ($key in @($defaults.Keys)) {
            $prop = $loaded.PSObject.Properties[$key]
            if ($null -ne $prop -and $null -ne $prop.Value) {
                $defaults[$key] = $prop.Value
            }
        }
    } catch {
        # 破損時はデフォルトへフォールバック
    }
    return [PSCustomObject]$defaults
}

function Save-UpdaterSettings {
    param([Parameter(Mandatory = $true)]$SettingsObj)
    $json = $SettingsObj | ConvertTo-Json -Depth 4
    Write-Utf8BomText -Path $Script:SettingsPath -Content $json
}

function Get-BaseStemFromInput {
    param([string]$InputName)
    $s = if ($null -eq $InputName) { '' } else { $InputName.Trim() }
    if ($s -match '(?i)\.zip$') {
        $s = $s.Substring(0, $s.Length - 4)
    }
    # 誤って "PhotoTools (1)" のように連番付きで入力された場合もベース名へ正規化
    $s = $s -replace '\s*\(\d+\)\s*$', ''
    return $s.Trim()
}

function Find-MatchingZipFiles {
    param(
        [Parameter(Mandatory = $true)][string]$DownloadDir,
        [Parameter(Mandatory = $true)][string]$BaseFileName
    )
    if ([string]::IsNullOrWhiteSpace($DownloadDir) -or -not (Test-Path -LiteralPath $DownloadDir)) {
        return ,@()
    }
    $stem = Get-BaseStemFromInput -InputName $BaseFileName
    if ([string]::IsNullOrWhiteSpace($stem)) {
        return ,@()
    }

    # ワイルドカード (*) 指定にも対応しつつ、ブラウザ連番 " (1)" / "(2)" 等を同一視
    $escaped = [regex]::Escape($stem) -replace '\\\*', '.*'
    $pattern = '(?i)^' + $escaped + '(?:\s*\(\d+\))?\.zip$'

    $allZips = @(Get-ChildItem -LiteralPath $DownloadDir -File -Filter '*.zip' -ErrorAction SilentlyContinue)
    $matched = New-Object System.Collections.ArrayList
    foreach ($f in $allZips) {
        if ($f.Name -match $pattern) {
            [void]$matched.Add($f)
        }
    }
    if ($matched.Count -eq 0) {
        return ,@()
    }

    # 更新日時が最新のものを先頭にする (同秒の場合は連番が大きいものを優先)
    $sorted = @($matched | Sort-Object -Property @(
            @{ Expression = { $_.LastWriteTime }; Descending = $true },
            @{ Expression = { $_.CreationTime }; Descending = $true },
            @{ Expression = {
                if ($_.BaseName -match '\((\d+)\)\s*$') { [int]$Matches[1] } else { 0 }
            }; Descending = $true }
        ))
    return ,$sorted
}

function Parse-GitHubRepoSpec {
    param([string]$RepoInput)
    $raw = if ($null -eq $RepoInput) { '' } else { $RepoInput.Trim() }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    # https://github.com/owner/repo(.git)(/tree/...) または owner/repo を解析
    if ($raw -match '(?i)^https?://github\.com/([^/\s]+)/([^/\s]+)') {
        $owner = $Matches[1]
        $repo = $Matches[2] -replace '(?i)\.git$', ''
        return [PSCustomObject]@{ Owner = $owner; Repo = $repo }
    }
    if ($raw -match '^([^/\s]+)/([^/\s]+)$') {
        $owner = $Matches[1]
        $repo = $Matches[2] -replace '(?i)\.git$', ''
        return [PSCustomObject]@{ Owner = $owner; Repo = $repo }
    }
    return $null
}

function Get-UniqueDownloadFilePath {
    param(
        [Parameter(Mandatory = $true)][string]$DownloadDir,
        [Parameter(Mandatory = $true)][string]$BaseStem
    )
    $safeStem = ($BaseStem -replace '[\\/:*?"<>|]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safeStem)) { $safeStem = 'PhotoTools' }

    $candidate = Join-Path $DownloadDir ($safeStem + '.zip')
    if (-not (Test-Path -LiteralPath $candidate)) {
        return $candidate
    }
    for ($i = 1; $i -le 999; $i++) {
        $candidate = Join-Path $DownloadDir ("{0} ({1}).zip" -f $safeStem, $i)
        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return Join-Path $DownloadDir ("{0}_{1}.zip" -f $safeStem, (Get-Date -Format 'yyyyMMdd_HHmmss'))
}

function Invoke-GitHubZipDownload {
    param(
        [Parameter(Mandatory = $true)][string]$RepoInput,
        [string]$Branch = 'main',
        [string]$Token = '',
        [Parameter(Mandatory = $true)][string]$DownloadDir,
        [string]$PreferredBaseName = '',
        [scriptblock]$LogCallback
    )
    $parsed = Parse-GitHubRepoSpec -RepoInput $RepoInput
    if ($null -eq $parsed) {
        throw "GitHubリポジトリの形式が正しくありません。「https://github.com/owner/repo」または「owner/repo」形式で指定してください。"
    }
    $br = if ([string]::IsNullOrWhiteSpace($Branch)) { 'main' } else { $Branch.Trim() }

    if (-not (Test-Path -LiteralPath $DownloadDir)) {
        New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
    }

    $stem = Get-BaseStemFromInput -InputName $PreferredBaseName
    if ([string]::IsNullOrWhiteSpace($stem) -or $stem.Contains('*')) {
        $stem = "{0}-{1}" -f $parsed.Repo, $br
    }
    $destZip = Get-UniqueDownloadFilePath -DownloadDir $DownloadDir -BaseStem $stem

    # TLS 1.2 を有効化
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    } catch { }

    $headers = @{ 'User-Agent' = 'PhotoToolsUpdater/1.0' }
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $url = "https://api.github.com/repos/{0}/{1}/zipball/{2}" -f $parsed.Owner, $parsed.Repo, [Uri]::EscapeDataString($br)
        $headers['Authorization'] = "Bearer $($Token.Trim())"
        $headers['Accept'] = 'application/vnd.github+json'
    } else {
        $url = "https://github.com/{0}/{1}/archive/refs/heads/{2}.zip" -f $parsed.Owner, $parsed.Repo, [Uri]::EscapeDataString($br)
    }

    if ($null -ne $LogCallback) {
        & $LogCallback ("GitHubから取得開始: {0}/{1} (ブランチ: {2})" -f $parsed.Owner, $parsed.Repo, $br)
        & $LogCallback ("保存先: {0}" -f $destZip)
    }

    try {
        Invoke-WebRequest -Uri $url -Headers $headers -OutFile $destZip -UseBasicParsing -MaximumRedirection 10
    } catch {
        if (Test-Path -LiteralPath $destZip) {
            Remove-Item -LiteralPath $destZip -Force -ErrorAction SilentlyContinue
        }
        $msg = $_.Exception.Message
        throw "GitHub からのダウンロードに失敗しました。リポジトリURL・ブランチ名・非公開リポジトリの場合はトークン(PAT)をご確認ください。`r`n詳細: $msg"
    }

    # ZIPマジックバイト (PK) 検証
    $bytes = [System.IO.File]::ReadAllBytes($destZip)
    if ($bytes.Length -lt 22 -or $bytes[0] -ne 0x50 -or $bytes[1] -ne 0x4B) {
        Remove-Item -LiteralPath $destZip -Force -ErrorAction SilentlyContinue
        throw "ダウンロードされたファイルが有効なZIP形式ではありません（認証エラーまたは存在しないブランチの可能性があります）。"
    }

    try { Unblock-File -LiteralPath $destZip -ErrorAction SilentlyContinue } catch { }
    return $destZip
}

function Resolve-PackageRootInExtractedDir {
    param([Parameter(Mandatory = $true)][string]$ExtractDir)

    # 1. 直下に PhotoToolsMaster.ps1 がある場合 (プレビュー出力 PhotoTools.zip)
    if (Test-Path -LiteralPath (Join-Path $ExtractDir 'PhotoToolsMaster.ps1')) {
        return [PSCustomObject]@{ RootPath = $ExtractDir; Confidence = 'Exact'; Reason = 'ZIP直下に PhotoToolsMaster.ps1 を検出' }
    }

    # 2. 配下のサブフォルダから PhotoToolsMaster.ps1 を検索 (GitHub repo-main\phototools 等)
    $masterHits = @(Get-ChildItem -LiteralPath $ExtractDir -Recurse -File -Filter 'PhotoToolsMaster.ps1' -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length })
    if ($masterHits.Count -gt 0) {
        $root = $masterHits[0].DirectoryName
        return [PSCustomObject]@{ RootPath = $root; Confidence = 'Exact'; Reason = "サブフォルダ内で PhotoToolsMaster.ps1 を検出 ($root)" }
    }

    # 3. 代替マーカー: common\ConfigHelper.ps1
    $cfgHits = @(Get-ChildItem -LiteralPath $ExtractDir -Recurse -File -Filter 'ConfigHelper.ps1' -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length })
    if ($cfgHits.Count -gt 0) {
        $commonDir = $cfgHits[0].DirectoryName
        if ((Split-Path -Leaf $commonDir) -ieq 'common') {
            $root = Split-Path -Parent $commonDir
            return [PSCustomObject]@{ RootPath = $root; Confidence = 'High'; Reason = "common\ConfigHelper.ps1 からルートを推定 ($root)" }
        }
    }

    # 4. トップレベルにフォルダが1つだけの場合 (一般的な GitHub ZIP)
    $topFiles = @(Get-ChildItem -LiteralPath $ExtractDir -File -ErrorAction SilentlyContinue)
    $topDirs = @(Get-ChildItem -LiteralPath $ExtractDir -Directory -ErrorAction SilentlyContinue)
    if ($topFiles.Count -eq 0 -and $topDirs.Count -eq 1) {
        return [PSCustomObject]@{ RootPath = $topDirs[0].FullName; Confidence = 'Fallback'; Reason = 'マーカー未検出のため単一トップフォルダを採用' }
    }

    return [PSCustomObject]@{ RootPath = $ExtractDir; Confidence = 'Fallback'; Reason = 'マーカー未検出のためZIP直下を採用' }
}

function Test-IsProtectedRelPath {
    param([Parameter(Mandatory = $true)][string]$RelPath)
    $norm = ($RelPath -replace '/', '\').TrimStart('\')
    if ($norm -match '(?i)^data(\\|$)') { return $true }
    if ($norm -match '(?i)^backup(\\|$)') { return $true }
    if ($norm -match '(?i)^settings\.ini\.bak') { return $true }
    if ($norm -match '(?i)(^|\\)updater_settings\.json$') { return $true }
    return $false
}

function Merge-SettingsIniFile {
    param(
        [Parameter(Mandatory = $true)][string]$ExistingPath,
        [Parameter(Mandatory = $true)][string]$IncomingPath
    )
    $existingText = [System.IO.File]::ReadAllText($ExistingPath, [System.Text.Encoding]::UTF8)
    $incomingText = [System.IO.File]::ReadAllText($IncomingPath, [System.Text.Encoding]::UTF8)

    $existingLines = New-Object System.Collections.ArrayList
    foreach ($line in (($existingText -replace "`r`n", "`n" -replace "`r", "`n") -split "`n")) {
        [void]$existingLines.Add($line)
    }

    # 既存の [Section] と Key を収集
    $existingKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $curSec = ''
    for ($i = 0; $i -lt $existingLines.Count; $i++) {
        $t = ([string]$existingLines[$i]).Trim()
        if ($t -match '^\[(.+)\]$') {
            $curSec = $Matches[1].Trim()
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($curSec)) {
            if ($t -match '^([^;=#][^=]*)=(.*)$') {
                $k = $Matches[1].Trim()
                [void]$existingKeys.Add("$curSec|$k")
            }
        }
    }

    # 新規ZIP側の settings.ini から不足している [Section] / Key=Value を抽出
    $missingBySection = [ordered]@{}
    $inSec = ''
    foreach ($rawLine in (($incomingText -replace "`r`n", "`n" -replace "`r", "`n") -split "`n")) {
        $t = $rawLine.Trim()
        if ($t -match '^\[(.+)\]$') {
            $inSec = $Matches[1].Trim()
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($inSec) -and $t -match '^([^;=#][^=]*)=(.*)$') {
            $k = $Matches[1].Trim()
            if (-not $existingKeys.Contains("$inSec|$k")) {
                if (-not $missingBySection.Contains($inSec)) {
                    $missingBySection[$inSec] = New-Object System.Collections.ArrayList
                }
                [void]$missingBySection[$inSec].Add([PSCustomObject]@{ Key = $k; Line = $rawLine.TrimEnd() })
            }
        }
    }

    $addedKeys = New-Object System.Collections.ArrayList
    if ($missingBySection.Count -eq 0) {
        return ,@()
    }

    # 既存セクション末尾へ挿入 (インデックスずれを防ぐため毎回セクション終端を再検索)
    foreach ($secName in @($missingBySection.Keys)) {
        $items = @($missingBySection[$secName])
        $insertAt = -1
        $inTarget = $false
        for ($i = 0; $i -lt $existingLines.Count; $i++) {
            $t = ([string]$existingLines[$i]).Trim()
            if ($t -match '^\[(.+)\]$') {
                if ($inTarget) { break }
                if ($Matches[1].Trim() -ieq $secName) {
                    $inTarget = $true
                    $insertAt = $i
                }
                continue
            }
            if ($inTarget -and -not [string]::IsNullOrWhiteSpace($t)) {
                $insertAt = $i
            }
        }

        if ($insertAt -ge 0) {
            $offset = 1
            foreach ($item in $items) {
                $existingLines.Insert($insertAt + $offset, $item.Line)
                $offset++
                [void]$addedKeys.Add("[$secName] $($item.Key)")
            }
        } else {
            if ($existingLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$existingLines[$existingLines.Count - 1])) {
                [void]$existingLines.Add('')
            }
            [void]$existingLines.Add("[$secName]")
            foreach ($item in $items) {
                [void]$existingLines.Add($item.Line)
                [void]$addedKeys.Add("[$secName] $($item.Key)")
            }
        }
    }

    $mergedContent = ($existingLines -join "`r`n").TrimEnd("`r", "`n") + "`r`n"
    Write-Utf8BomText -Path $ExistingPath -Content $mergedContent
    return ,@($addedKeys)
}

function Invoke-TargetBackup {
    param(
        [Parameter(Mandatory = $true)][string]$TargetDir,
        [int]$KeepCount = 5,
        [scriptblock]$LogCallback
    )
    if (-not (Test-Path -LiteralPath $TargetDir)) {
        return $null
    }

    $existingFiles = @(Get-ChildItem -LiteralPath $TargetDir -Recurse -File -ErrorAction SilentlyContinue)
    if ($existingFiles.Count -eq 0) {
        return $null
    }

    $backupBase = Join-Path $TargetDir 'backup'
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir = Join-Path $backupBase $stamp
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    $rootPrefix = $TargetDir.TrimEnd('\') + '\'
    $copiedCount = 0
    foreach ($f in $existingFiles) {
        $rel = $f.FullName.Substring($rootPrefix.Length)
        # backup\ 自身および大容量になりやすい data\logs\ はバックアップ対象から除外
        if ($rel -match '(?i)^backup(\\|$)') { continue }
        if ($rel -match '(?i)^data\\logs(\\|$)') { continue }

        $dest = Join-Path $backupDir $rel
        $destParent = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $destParent)) {
            New-Item -ItemType Directory -Path $destParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        $copiedCount++
    }

    if ($null -ne $LogCallback) {
        & $LogCallback ("自動バックアップ作成完了: {0} ({1} ファイル)" -f $backupDir, $copiedCount)
    }

    # 古いバックアップ世代の整理 (YYYYMMDD_HHMMSS 形式のみ対象)
    if ($KeepCount -gt 0 -and (Test-Path -LiteralPath $backupBase)) {
        $genDirs = @(Get-ChildItem -LiteralPath $backupBase -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{8}_\d{6}$' } |
            Sort-Object Name -Descending)
        if ($genDirs.Count -gt $KeepCount) {
            for ($i = $KeepCount; $i -lt $genDirs.Count; $i++) {
                try {
                    Remove-Item -LiteralPath $genDirs[$i].FullName -Recurse -Force -ErrorAction Stop
                    if ($null -ne $LogCallback) {
                        & $LogCallback ("古いバックアップを整理: {0}" -f $genDirs[$i].Name)
                    }
                } catch {
                    if ($null -ne $LogCallback) {
                        & $LogCallback ("[警告] 古いバックアップ削除スキップ: {0} ({1})" -f $genDirs[$i].Name, $_.Exception.Message)
                    }
                }
            }
        }
    }

    return $backupDir
}

function Show-ObsoleteFileDeleteDialog {
    param(
        [Parameter(Mandatory = $true)][object[]]$ObsoleteItems,
        [Parameter(Mandatory = $true)][System.Windows.Forms.IWin32Window]$Owner
    )
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = '不要ファイルの削除確認'
    $dlg.Size = New-Object System.Drawing.Size(700, 480)
    $dlg.MinimumSize = New-Object System.Drawing.Size(600, 380)
    $dlg.StartPosition = 'CenterParent'
    $dlg.Font = New-Object System.Drawing.Font('Meiryo UI', 9)
    $dlg.MaximizeBox = $false

    $lblGuide = New-Object System.Windows.Forms.Label
    $lblGuide.Location = New-Object System.Drawing.Point(14, 12)
    $lblGuide.Size = New-Object System.Drawing.Size(656, 38)
    $lblGuide.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $lblGuide.Text = "更新先フォルダに存在しますが、今回のZIPには含まれていないファイルが見つかりました（全 $($ObsoleteItems.Count) 件）。`r`n削除してよいファイルにチェックを入れて「選択したファイルを削除」を押してください（settings.ini や data\ は保護対象のため一覧に含まれません）。"
    $dlg.Controls.Add($lblGuide)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Location = New-Object System.Drawing.Point(14, 56)
    $lv.Size = New-Object System.Drawing.Size(656, 326)
    $lv.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $lv.View = [System.Windows.Forms.View]::Details
    $lv.CheckBoxes = $true
    $lv.FullRowSelect = $true
    $lv.GridLines = $true
    [void]$lv.Columns.Add('相対パス', 400)
    [void]$lv.Columns.Add('更新日時', 140)
    [void]$lv.Columns.Add('サイズ', 90)

    foreach ($item in $ObsoleteItems) {
        $lvi = New-Object System.Windows.Forms.ListViewItem($item.RelPath)
        $lvi.Checked = $true
        $lvi.Tag = $item
        [void]$lvi.SubItems.Add($item.LastWriteTime.ToString('yyyy/MM/dd HH:mm'))
        $kb = [math]::Ceiling($item.Length / 1024.0)
        [void]$lvi.SubItems.Add(("{0:N0} KB" -f $kb))
        [void]$lv.Items.Add($lvi)
    }
    $dlg.Controls.Add($lv)

    $btnAll = New-Object System.Windows.Forms.Button
    $btnAll.Text = 'すべて選択'
    $btnAll.Location = New-Object System.Drawing.Point(14, 394)
    $btnAll.Size = New-Object System.Drawing.Size(96, 30)
    $btnAll.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $btnAll.Add_Click({
        foreach ($it in $lv.Items) { $it.Checked = $true }
    })
    $dlg.Controls.Add($btnAll)

    $btnNone = New-Object System.Windows.Forms.Button
    $btnNone.Text = 'すべて解除'
    $btnNone.Location = New-Object System.Drawing.Point(118, 394)
    $btnNone.Size = New-Object System.Drawing.Size(96, 30)
    $btnNone.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $btnNone.Add_Click({
        foreach ($it in $lv.Items) { $it.Checked = $false }
    })
    $dlg.Controls.Add($btnNone)

    $btnDelete = New-Object System.Windows.Forms.Button
    $btnDelete.Text = '選択したファイルを削除'
    $btnDelete.Location = New-Object System.Drawing.Point(378, 394)
    $btnDelete.Size = New-Object System.Drawing.Size(172, 30)
    $btnDelete.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnDelete.BackColor = [System.Drawing.Color]::FromArgb(185, 28, 28)
    $btnDelete.ForeColor = [System.Drawing.Color]::White
    $btnDelete.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnDelete.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($btnDelete)

    $btnSkip = New-Object System.Windows.Forms.Button
    $btnSkip.Text = '削除せず閉じる'
    $btnSkip.Location = New-Object System.Drawing.Point(558, 394)
    $btnSkip.Size = New-Object System.Drawing.Size(112, 30)
    $btnSkip.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnSkip.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnSkip)

    $dlg.CancelButton = $btnSkip

    $res = $dlg.ShowDialog($Owner)
    $selectedToDelete = New-Object System.Collections.ArrayList
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        foreach ($it in $lv.Items) {
            if ($it.Checked) {
                [void]$selectedToDelete.Add($it.Tag)
            }
        }
    }
    $dlg.Dispose()
    return ,@($selectedToDelete)
}

function Show-PhotoToolsUpdaterGui {
    $cfg = Load-UpdaterSettings

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'PhotoTools 更新支援ツール (単独版)'
    $form.ClientSize = New-Object System.Drawing.Size(804, 704)
    $form.MinimumSize = New-Object System.Drawing.Size(760, 660)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object System.Drawing.Font('Meiryo UI', 9)
    $form.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
    $form.AllowDrop = $true

    # --------------------------------------------------------------------------
    # GroupBox 1: ローカルZIP選択
    # --------------------------------------------------------------------------
    $gbZip = New-Object System.Windows.Forms.GroupBox
    $gbZip.Text = '1. ダウンロード済みZIP選択（ブラウザ連番 (1)(2)... を同一ファイル名として自動認識）'
    $gbZip.Location = New-Object System.Drawing.Point(14, 12)
    $gbZip.Size = New-Object System.Drawing.Size(776, 136)
    $gbZip.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($gbZip)

    $lblDlDir = New-Object System.Windows.Forms.Label
    $lblDlDir.Text = 'ZIP保存フォルダ:'
    $lblDlDir.Location = New-Object System.Drawing.Point(14, 27)
    $lblDlDir.Size = New-Object System.Drawing.Size(118, 20)
    $gbZip.Controls.Add($lblDlDir)

    $txtDownloadDir = New-Object System.Windows.Forms.TextBox
    $txtDownloadDir.Location = New-Object System.Drawing.Point(136, 24)
    $txtDownloadDir.Size = New-Object System.Drawing.Size(524, 24)
    $txtDownloadDir.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $txtDownloadDir.Text = [string]$cfg.DownloadDir
    $gbZip.Controls.Add($txtDownloadDir)

    $btnBrowseDownload = New-Object System.Windows.Forms.Button
    $btnBrowseDownload.Text = '参照...'
    $btnBrowseDownload.Location = New-Object System.Drawing.Point(668, 23)
    $btnBrowseDownload.Size = New-Object System.Drawing.Size(94, 26)
    $btnBrowseDownload.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $gbZip.Controls.Add($btnBrowseDownload)

    $lblBaseName = New-Object System.Windows.Forms.Label
    $lblBaseName.Text = '対象ファイル名:'
    $lblBaseName.Location = New-Object System.Drawing.Point(14, 59)
    $lblBaseName.Size = New-Object System.Drawing.Size(118, 20)
    $gbZip.Controls.Add($lblBaseName)

    $txtBaseFileName = New-Object System.Windows.Forms.TextBox
    $txtBaseFileName.Location = New-Object System.Drawing.Point(136, 56)
    $txtBaseFileName.Size = New-Object System.Drawing.Size(250, 24)
    $txtBaseFileName.Text = [string]$cfg.BaseFileName
    $gbZip.Controls.Add($txtBaseFileName)

    $btnAutoSelect = New-Object System.Windows.Forms.Button
    $btnAutoSelect.Text = '選択 (最新を自動選択)'
    $btnAutoSelect.Location = New-Object System.Drawing.Point(394, 55)
    $btnAutoSelect.Size = New-Object System.Drawing.Size(180, 26)
    $btnAutoSelect.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
    $btnAutoSelect.ForeColor = [System.Drawing.Color]::White
    $btnAutoSelect.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $gbZip.Controls.Add($btnAutoSelect)

    $btnBrowseZip = New-Object System.Windows.Forms.Button
    $btnBrowseZip.Text = '手動でZIP参照...'
    $btnBrowseZip.Location = New-Object System.Drawing.Point(582, 55)
    $btnBrowseZip.Size = New-Object System.Drawing.Size(180, 26)
    $gbZip.Controls.Add($btnBrowseZip)

    $lblSelectedZip = New-Object System.Windows.Forms.Label
    $lblSelectedZip.Text = '選択中のZIP:'
    $lblSelectedZip.Location = New-Object System.Drawing.Point(14, 91)
    $lblSelectedZip.Size = New-Object System.Drawing.Size(118, 20)
    $gbZip.Controls.Add($lblSelectedZip)

    $txtSelectedZip = New-Object System.Windows.Forms.TextBox
    $txtSelectedZip.Location = New-Object System.Drawing.Point(136, 88)
    $txtSelectedZip.Size = New-Object System.Drawing.Size(626, 24)
    $txtSelectedZip.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $txtSelectedZip.ReadOnly = $true
    $txtSelectedZip.BackColor = [System.Drawing.Color]::White
    $gbZip.Controls.Add($txtSelectedZip)

    $lblZipInfo = New-Object System.Windows.Forms.Label
    $lblZipInfo.Text = '「選択 (最新を自動選択)」または「GitHubから最新ZIPを取得」を押してください。'
    $lblZipInfo.Location = New-Object System.Drawing.Point(136, 114)
    $lblZipInfo.Size = New-Object System.Drawing.Size(626, 18)
    $lblZipInfo.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $lblZipInfo.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $gbZip.Controls.Add($lblZipInfo)

    # --------------------------------------------------------------------------
    # GroupBox 2: GitHub 自動ダウンロード
    # --------------------------------------------------------------------------
    $gbGitHub = New-Object System.Windows.Forms.GroupBox
    $gbGitHub.Text = '2. GitHub から最新ZIPを自動ダウンロード（任意）'
    $gbGitHub.Location = New-Object System.Drawing.Point(14, 156)
    $gbGitHub.Size = New-Object System.Drawing.Size(776, 96)
    $gbGitHub.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($gbGitHub)

    $lblGhRepo = New-Object System.Windows.Forms.Label
    $lblGhRepo.Text = 'リポジトリURL:'
    $lblGhRepo.Location = New-Object System.Drawing.Point(14, 27)
    $lblGhRepo.Size = New-Object System.Drawing.Size(118, 20)
    $gbGitHub.Controls.Add($lblGhRepo)

    $txtGitHubRepo = New-Object System.Windows.Forms.TextBox
    $txtGitHubRepo.Location = New-Object System.Drawing.Point(136, 24)
    $txtGitHubRepo.Size = New-Object System.Drawing.Size(376, 24)
    $txtGitHubRepo.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $txtGitHubRepo.Text = [string]$cfg.GitHubRepo
    $gbGitHub.Controls.Add($txtGitHubRepo)

    $lblGhBranch = New-Object System.Windows.Forms.Label
    $lblGhBranch.Text = 'ブランチ:'
    $lblGhBranch.Location = New-Object System.Drawing.Point(520, 27)
    $lblGhBranch.Size = New-Object System.Drawing.Size(58, 20)
    $lblGhBranch.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $gbGitHub.Controls.Add($lblGhBranch)

    $txtGitHubBranch = New-Object System.Windows.Forms.TextBox
    $txtGitHubBranch.Location = New-Object System.Drawing.Point(582, 24)
    $txtGitHubBranch.Size = New-Object System.Drawing.Size(180, 24)
    $txtGitHubBranch.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $txtGitHubBranch.Text = [string]$cfg.GitHubBranch
    $gbGitHub.Controls.Add($txtGitHubBranch)

    $lblGhToken = New-Object System.Windows.Forms.Label
    $lblGhToken.Text = 'PAT(非公開のみ):'
    $lblGhToken.Location = New-Object System.Drawing.Point(14, 59)
    $lblGhToken.Size = New-Object System.Drawing.Size(118, 20)
    $gbGitHub.Controls.Add($lblGhToken)

    $txtGitHubToken = New-Object System.Windows.Forms.TextBox
    $txtGitHubToken.Location = New-Object System.Drawing.Point(136, 56)
    $txtGitHubToken.Size = New-Object System.Drawing.Size(376, 24)
    $txtGitHubToken.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $txtGitHubToken.UseSystemPasswordChar = $true
    $gbGitHub.Controls.Add($txtGitHubToken)

    $btnDownloadGitHub = New-Object System.Windows.Forms.Button
    $btnDownloadGitHub.Text = 'GitHubから最新ZIPを取得'
    $btnDownloadGitHub.Location = New-Object System.Drawing.Point(520, 55)
    $btnDownloadGitHub.Size = New-Object System.Drawing.Size(242, 26)
    $btnDownloadGitHub.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $gbGitHub.Controls.Add($btnDownloadGitHub)

    # --------------------------------------------------------------------------
    # GroupBox 3: 更新先フォルダ・安全オプション
    # --------------------------------------------------------------------------
    $gbTarget = New-Object System.Windows.Forms.GroupBox
    $gbTarget.Text = '3. 更新先フォルダ・保護オプション（data\ および backup\ は常に完全保護されます）'
    $gbTarget.Location = New-Object System.Drawing.Point(14, 260)
    $gbTarget.Size = New-Object System.Drawing.Size(776, 122)
    $gbTarget.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($gbTarget)

    $lblTargetDir = New-Object System.Windows.Forms.Label
    $lblTargetDir.Text = '更新先フォルダ:'
    $lblTargetDir.Location = New-Object System.Drawing.Point(14, 27)
    $lblTargetDir.Size = New-Object System.Drawing.Size(118, 20)
    $gbTarget.Controls.Add($lblTargetDir)

    $txtTargetDir = New-Object System.Windows.Forms.TextBox
    $txtTargetDir.Location = New-Object System.Drawing.Point(136, 24)
    $txtTargetDir.Size = New-Object System.Drawing.Size(524, 24)
    $txtTargetDir.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $txtTargetDir.Text = [string]$cfg.TargetDir
    $gbTarget.Controls.Add($txtTargetDir)

    $btnBrowseTarget = New-Object System.Windows.Forms.Button
    $btnBrowseTarget.Text = '参照...'
    $btnBrowseTarget.Location = New-Object System.Drawing.Point(668, 23)
    $btnBrowseTarget.Size = New-Object System.Drawing.Size(94, 26)
    $btnBrowseTarget.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $gbTarget.Controls.Add($btnBrowseTarget)

    $lblIniMode = New-Object System.Windows.Forms.Label
    $lblIniMode.Text = 'settings.ini 扱い:'
    $lblIniMode.Location = New-Object System.Drawing.Point(14, 59)
    $lblIniMode.Size = New-Object System.Drawing.Size(118, 20)
    $gbTarget.Controls.Add($lblIniMode)

    $radMergeIni = New-Object System.Windows.Forms.RadioButton
    $radMergeIni.Text = '既存値を維持し新規キーのみ追記 (推奨)'
    $radMergeIni.Location = New-Object System.Drawing.Point(136, 57)
    $radMergeIni.Size = New-Object System.Drawing.Size(290, 22)
    $radMergeIni.Checked = ([string]$cfg.SettingsIniMode -ne 'Skip')
    $gbTarget.Controls.Add($radMergeIni)

    $radSkipIni = New-Object System.Windows.Forms.RadioButton
    $radSkipIni.Text = '完全に変更しない (スキップ)'
    $radSkipIni.Location = New-Object System.Drawing.Point(434, 57)
    $radSkipIni.Size = New-Object System.Drawing.Size(220, 22)
    $radSkipIni.Checked = ([string]$cfg.SettingsIniMode -eq 'Skip')
    $gbTarget.Controls.Add($radSkipIni)

    $chkBackup = New-Object System.Windows.Forms.CheckBox
    $chkBackup.Text = '更新前に自動バックアップ (backup\ 直近5世代)'
    $chkBackup.Location = New-Object System.Drawing.Point(136, 86)
    $chkBackup.Size = New-Object System.Drawing.Size(310, 22)
    $chkBackup.Checked = [bool]$cfg.EnableBackup
    $gbTarget.Controls.Add($chkBackup)

    $chkUnblock = New-Object System.Windows.Forms.CheckBox
    $chkUnblock.Text = '自動ブロック解除 (Unblock)'
    $chkUnblock.Location = New-Object System.Drawing.Point(452, 86)
    $chkUnblock.Size = New-Object System.Drawing.Size(184, 22)
    $chkUnblock.Checked = [bool]$cfg.AutoUnblock
    $gbTarget.Controls.Add($chkUnblock)

    $chkDeleteObsolete = New-Object System.Windows.Forms.CheckBox
    $chkDeleteObsolete.Text = '不要ファイル確認'
    $chkDeleteObsolete.Location = New-Object System.Drawing.Point(640, 86)
    $chkDeleteObsolete.Size = New-Object System.Drawing.Size(128, 22)
    $chkDeleteObsolete.Checked = [bool]$cfg.ConfirmDeleteObsolete
    $gbTarget.Controls.Add($chkDeleteObsolete)

    # --------------------------------------------------------------------------
    # アクションバー
    # --------------------------------------------------------------------------
    $btnRunUpdate = New-Object System.Windows.Forms.Button
    $btnRunUpdate.Text = '指定フォルダへ更新を実行'
    $btnRunUpdate.Location = New-Object System.Drawing.Point(14, 392)
    $btnRunUpdate.Size = New-Object System.Drawing.Size(236, 36)
    $btnRunUpdate.Font = New-Object System.Drawing.Font('Meiryo UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $btnRunUpdate.BackColor = [System.Drawing.Color]::FromArgb(15, 118, 110)
    $btnRunUpdate.ForeColor = [System.Drawing.Color]::White
    $btnRunUpdate.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $form.Controls.Add($btnRunUpdate)

    $btnOpenTarget = New-Object System.Windows.Forms.Button
    $btnOpenTarget.Text = '更新先を開く'
    $btnOpenTarget.Location = New-Object System.Drawing.Point(260, 392)
    $btnOpenTarget.Size = New-Object System.Drawing.Size(112, 36)
    $form.Controls.Add($btnOpenTarget)

    $btnOpenBackup = New-Object System.Windows.Forms.Button
    $btnOpenBackup.Text = 'バックアップを開く'
    $btnOpenBackup.Location = New-Object System.Drawing.Point(380, 392)
    $btnOpenBackup.Size = New-Object System.Drawing.Size(134, 36)
    $form.Controls.Add($btnOpenBackup)

    $btnSaveSettings = New-Object System.Windows.Forms.Button
    $btnSaveSettings.Text = '入力設定を保存'
    $btnSaveSettings.Location = New-Object System.Drawing.Point(522, 392)
    $btnSaveSettings.Size = New-Object System.Drawing.Size(124, 36)
    $form.Controls.Add($btnSaveSettings)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = '閉じる'
    $btnClose.Location = New-Object System.Drawing.Point(696, 392)
    $btnClose.Size = New-Object System.Drawing.Size(94, 36)
    $btnClose.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($btnClose)

    # 進捗バー & ログ欄
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(14, 436)
    $progressBar.Size = New-Object System.Drawing.Size(776, 16)
    $progressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $form.Controls.Add($progressBar)

    $lblLog = New-Object System.Windows.Forms.Label
    $lblLog.Text = '実行ログ:'
    $lblLog.Location = New-Object System.Drawing.Point(14, 458)
    $lblLog.Size = New-Object System.Drawing.Size(120, 18)
    $form.Controls.Add($lblLog)

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Location = New-Object System.Drawing.Point(14, 478)
    $txtLog.Size = New-Object System.Drawing.Size(776, 212)
    $txtLog.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $txtLog.Multiline = $true
    $txtLog.ReadOnly = $true
    $txtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $txtLog.BackColor = [System.Drawing.Color]::White
    $txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
    $form.Controls.Add($txtLog)

    # --------------------------------------------------------------------------
    # ヘルパー（UIログ・設定収集・ZIP表示更新）
    # --------------------------------------------------------------------------
    $appendLog = {
        param([string]$Message)
        $line = "[{0}] {1}`r`n" -f (Get-Date -Format 'HH:mm:ss'), $Message
        $txtLog.AppendText($line)
        $txtLog.SelectionStart = $txtLog.TextLength
        $txtLog.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }

    $collectCurrentSettings = {
        return [PSCustomObject]@{
            DownloadDir           = $txtDownloadDir.Text.Trim()
            BaseFileName          = $txtBaseFileName.Text.Trim()
            TargetDir             = $txtTargetDir.Text.Trim()
            GitHubRepo            = $txtGitHubRepo.Text.Trim()
            GitHubBranch          = if ([string]::IsNullOrWhiteSpace($txtGitHubBranch.Text)) { 'main' } else { $txtGitHubBranch.Text.Trim() }
            SettingsIniMode       = if ($radSkipIni.Checked) { 'Skip' } else { 'Merge' }
            EnableBackup          = $chkBackup.Checked
            KeepBackupCount       = 5
            AutoUnblock           = $chkUnblock.Checked
            ConfirmDeleteObsolete = $chkDeleteObsolete.Checked
        }
    }

    $setSelectedZipDisplay = {
        param([string]$ZipPath, [string]$Note = '')
        $txtSelectedZip.Text = $ZipPath
        if (-not [string]::IsNullOrWhiteSpace($ZipPath) -and (Test-Path -LiteralPath $ZipPath)) {
            $fi = Get-Item -LiteralPath $ZipPath
            $kb = [math]::Ceiling($fi.Length / 1024.0)
            $info = "更新日時: {0}  /  サイズ: {1:N0} KB" -f $fi.LastWriteTime.ToString('yyyy/MM/dd HH:mm:ss'), $kb
            if (-not [string]::IsNullOrWhiteSpace($Note)) {
                $info = "$Note  ($info)"
            }
            $lblZipInfo.Text = $info
            $lblZipInfo.ForeColor = [System.Drawing.Color]::FromArgb(15, 118, 110)
        } else {
            $lblZipInfo.Text = '有効なZIPファイルが選択されていません。'
            $lblZipInfo.ForeColor = [System.Drawing.Color]::FromArgb(185, 28, 28)
        }
    }

    $setBusy = {
        param([bool]$Busy)
        $btnAutoSelect.Enabled = -not $Busy
        $btnBrowseZip.Enabled = -not $Busy
        $btnDownloadGitHub.Enabled = -not $Busy
        $btnRunUpdate.Enabled = -not $Busy
        $btnBrowseDownload.Enabled = -not $Busy
        $btnBrowseTarget.Enabled = -not $Busy
        $btnSaveSettings.Enabled = -not $Busy
        $form.UseWaitCursor = $Busy
        [System.Windows.Forms.Application]::DoEvents()
    }

    # --------------------------------------------------------------------------
    # イベントハンドラ
    # --------------------------------------------------------------------------
    $btnBrowseDownload.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = 'ダウンロード済みZIPが保存されているフォルダを選択してください'
        if (Test-Path -LiteralPath $txtDownloadDir.Text.Trim()) {
            $fbd.SelectedPath = $txtDownloadDir.Text.Trim()
        }
        if ($fbd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtDownloadDir.Text = $fbd.SelectedPath
        }
        $fbd.Dispose()
    })

    $btnBrowseTarget.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = '更新先の PhotoTools フォルダを選択してください'
        if (Test-Path -LiteralPath $txtTargetDir.Text.Trim()) {
            $fbd.SelectedPath = $txtTargetDir.Text.Trim()
        }
        if ($fbd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtTargetDir.Text = $fbd.SelectedPath
        }
        $fbd.Dispose()
    })

    $btnBrowseZip.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Title = '更新に使用するZIPファイルを選択してください'
        $ofd.Filter = 'ZIPアーカイブ (*.zip)|*.zip|すべてのファイル (*.*)|*.*'
        if (Test-Path -LiteralPath $txtDownloadDir.Text.Trim()) {
            $ofd.InitialDirectory = $txtDownloadDir.Text.Trim()
        }
        if ($ofd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            & $setSelectedZipDisplay $ofd.FileName '手動選択'
            & $appendLog ("ZIPを手動選択しました: {0}" -f $ofd.FileName)
        }
        $ofd.Dispose()
    })

    $btnAutoSelect.Add_Click({
        $dlDir = $txtDownloadDir.Text.Trim()
        $baseName = $txtBaseFileName.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($dlDir) -or -not (Test-Path -LiteralPath $dlDir)) {
            [System.Windows.Forms.MessageBox]::Show($form, "ZIP保存フォルダが存在しません。`r`n$dlDir", 'フォルダ確認', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($baseName)) {
            [System.Windows.Forms.MessageBox]::Show($form, '対象ファイル名を入力してください（例: PhotoTools.zip）。', '入力確認', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }

        $matchedZips = @(Find-MatchingZipFiles -DownloadDir $dlDir -BaseFileName $baseName)
        if ($matchedZips.Count -eq 0) {
            & $setSelectedZipDisplay '' ''
            & $appendLog ("一致するZIPが見つかりませんでした: フォルダ={0} / 対象名={1}" -f $dlDir, $baseName)
            [System.Windows.Forms.MessageBox]::Show($form, "一致するZIPファイルが見つかりませんでした。`r`nフォルダ: $dlDir`r`n対象ファイル名: $baseName`r`n※「(1)」「(2)」等の連番付きも自動検索対象です。", '見つかりません', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }

        $latest = $matchedZips[0]
        & $setSelectedZipDisplay $latest.FullName ("一致 {0} 件中 最新を選択" -f $matchedZips.Count)
        & $appendLog ("最新ZIPを自動選択しました（候補 {0} 件）: {1}" -f $matchedZips.Count, $latest.Name)
        if ($matchedZips.Count -gt 1) {
            $previewCount = [math]::Min($matchedZips.Count, 5)
            for ($i = 0; $i -lt $previewCount; $i++) {
                $m = $matchedZips[$i]
                & $appendLog ("  候補#{0}: {1} ({2})" -f ($i + 1), $m.Name, $m.LastWriteTime.ToString('yyyy/MM/dd HH:mm:ss'))
            }
        }
        try { Save-UpdaterSettings -SettingsObj (& $collectCurrentSettings) } catch { }
    })

    $form.Add_DragEnter({
        param($s, $e)
        if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            $dropped = @($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))
            if ($dropped.Count -gt 0 -and ([string]$dropped[0]) -match '(?i)\.zip$') {
                $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
                return
            }
        }
        $e.Effect = [System.Windows.Forms.DragDropEffects]::None
    })

    $form.Add_DragDrop({
        param($s, $e)
        if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            $dropped = @($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))
            if ($dropped.Count -gt 0 -and ([string]$dropped[0]) -match '(?i)\.zip$') {
                $zipFile = [string]$dropped[0]
                & $setSelectedZipDisplay $zipFile 'ドラッグ＆ドロップ選択'
                & $appendLog ("ZIPをドラッグ＆ドロップで選択しました: {0}" -f $zipFile)
            }
        }
    })

    $btnDownloadGitHub.Add_Click({
        $repo = $txtGitHubRepo.Text.Trim()
        $branch = $txtGitHubBranch.Text.Trim()
        $dlDir = $txtDownloadDir.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($repo)) {
            [System.Windows.Forms.MessageBox]::Show($form, 'GitHubリポジトリURL（例: https://github.com/owner/repo）を入力してください。', '入力確認', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($dlDir)) {
            [System.Windows.Forms.MessageBox]::Show($form, 'ZIP保存フォルダを指定してください。', '入力確認', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }

        & $setBusy $true
        $progressBar.Value = 20
        try {
            $savedZip = Invoke-GitHubZipDownload `
                -RepoInput $repo `
                -Branch $branch `
                -Token $txtGitHubToken.Text `
                -DownloadDir $dlDir `
                -PreferredBaseName $txtBaseFileName.Text `
                -LogCallback $appendLog
            $progressBar.Value = 100
            & $setSelectedZipDisplay $savedZip 'GitHubから最新ZIPを取得'
            & $appendLog ("GitHub取得完了: {0}" -f $savedZip)
            try { Save-UpdaterSettings -SettingsObj (& $collectCurrentSettings) } catch { }
            [System.Windows.Forms.MessageBox]::Show($form, "GitHubから最新ZIPをダウンロードし、選択状態にしました。`r`n`r`n$savedZip`r`n`r`n続けて「指定フォルダへ更新を実行」を押して更新できます。", '取得完了', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } catch {
            $progressBar.Value = 0
            & $appendLog ("[エラー] " + $_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'GitHub取得エラー', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        } finally {
            & $setBusy $false
        }
    })

    $btnSaveSettings.Add_Click({
        try {
            Save-UpdaterSettings -SettingsObj (& $collectCurrentSettings)
            & $appendLog ("入力設定を保存しました: {0}" -f $Script:SettingsPath)
            [System.Windows.Forms.MessageBox]::Show($form, "設定を保存しました。`r`n$($Script:SettingsPath)", '保存完了', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show($form, "設定の保存に失敗しました。`r`n$($_.Exception.Message)", 'エラー', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $btnOpenTarget.Add_Click({
        $tDir = $txtTargetDir.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($tDir) -and (Test-Path -LiteralPath $tDir)) {
            Start-Process explorer.exe -ArgumentList "`"$tDir`""
        } else {
            [System.Windows.Forms.MessageBox]::Show($form, "更新先フォルダが見つかりません: $tDir", '情報', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
    })

    $btnOpenBackup.Add_Click({
        $bDir = Join-Path $txtTargetDir.Text.Trim() 'backup'
        if (Test-Path -LiteralPath $bDir) {
            Start-Process explorer.exe -ArgumentList "`"$bDir`""
        } else {
            [System.Windows.Forms.MessageBox]::Show($form, "バックアップフォルダはまだ作成されていません。`r`n$bDir", '情報', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
    })

    $btnClose.Add_Click({ $form.Close() })

    # --------------------------------------------------------------------------
    # 更新実行メイン処理
    # --------------------------------------------------------------------------
    $btnRunUpdate.Add_Click({
        $zipPath = $txtSelectedZip.Text.Trim()
        $targetDir = $txtTargetDir.Text.Trim()

        # 未選択なら自動で最新ZIP選択を試みる
        if ([string]::IsNullOrWhiteSpace($zipPath) -or -not (Test-Path -LiteralPath $zipPath)) {
            $autoMatches = @(Find-MatchingZipFiles -DownloadDir $txtDownloadDir.Text.Trim() -BaseFileName $txtBaseFileName.Text.Trim())
            if ($autoMatches.Count -gt 0) {
                $zipPath = $autoMatches[0].FullName
                & $setSelectedZipDisplay $zipPath ("一致 {0} 件中 最新を自動選択" -f $autoMatches.Count)
            }
        }

        if ([string]::IsNullOrWhiteSpace($zipPath) -or -not (Test-Path -LiteralPath $zipPath)) {
            [System.Windows.Forms.MessageBox]::Show($form, '更新に使用するZIPファイルが選択されていません。先に「選択 (最新を自動選択)」または「GitHubから最新ZIPを取得」を実行してください。', 'ZIP未選択', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($targetDir)) {
            [System.Windows.Forms.MessageBox]::Show($form, '更新先フォルダを指定してください。', '入力確認', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }

        $iniModeText = if ($radSkipIni.Checked) { '完全スキップ (変更なし)' } else { '既存値維持＋新規キーのみ追記' }
        $confirmMsg = "以下の内容で更新を実行します。よろしいですか？`r`n`r`n" +
                      "更新元ZIP : $zipPath`r`n" +
                      "更新先    : $targetDir`r`n" +
                      "settings.ini : $iniModeText`r`n" +
                      "data\ / backup\ : 完全保護`r`n" +
                      "事前バックアップ : $(if ($chkBackup.Checked) { '作成する (直近5世代)' } else { '作成しない' })"
        $ans = [System.Windows.Forms.MessageBox]::Show($form, $confirmMsg, '更新実行の確認', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        try { Save-UpdaterSettings -SettingsObj (& $collectCurrentSettings) } catch { }

        & $setBusy $true
        $progressBar.Value = 5
        $tempDir = Join-Path $env:TEMP ("PhotoToolsUpdate_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + "_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $backupDir = $null

        try {
            & $appendLog '============================================================'
            & $appendLog ("更新開始: {0}" -f $zipPath)
            & $appendLog ("更新先  : {0}" -f $targetDir)

            if ($chkUnblock.Checked) {
                try { Unblock-File -LiteralPath $zipPath -ErrorAction SilentlyContinue } catch { }
            }

            # 1. 一時フォルダへ展開
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            & $appendLog ("一時フォルダへ解凍中: {0}" -f $tempDir)
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $tempDir)
            $progressBar.Value = 25

            # 2. パッケージルート自動判定
            $rootInfo = Resolve-PackageRootInExtractedDir -ExtractDir $tempDir
            $packageRoot = $rootInfo.RootPath
            & $appendLog ("ZIPルート判定 [{0}]: {1}" -f $rootInfo.Confidence, $rootInfo.Reason)

            if ($rootInfo.Confidence -eq 'Fallback') {
                $fbAns = [System.Windows.Forms.MessageBox]::Show(
                    $form,
                    "ZIP内に PhotoToolsMaster.ps1 が見つかりませんでした。`r`n別のZIPファイルである可能性があります。`r`n`r`n検出ルート: $packageRoot`r`nこのまま更新を続行しますか？",
                    'ZIP構造の確認',
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                if ($fbAns -ne [System.Windows.Forms.DialogResult]::Yes) {
                    & $appendLog 'ユーザー操作により更新を中止しました。'
                    $progressBar.Value = 0
                    return
                }
            }

            if (-not (Test-Path -LiteralPath $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                & $appendLog ("更新先フォルダを新規作成しました: {0}" -f $targetDir)
            }

            # 3. 更新前自動バックアップ
            if ($chkBackup.Checked) {
                $backupDir = Invoke-TargetBackup -TargetDir $targetDir -KeepCount 5 -LogCallback $appendLog
            }
            $progressBar.Value = 45

            # 4. 上書きコピー + 保護制御 + Unblock
            $srcFiles = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File -ErrorAction SilentlyContinue)
            $srcPrefix = $packageRoot.TrimEnd('\') + '\'
            $incomingRelSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

            $updatedCount = 0
            $protectedSkippedCount = 0
            $mergedIniKeys = @()
            $errorCount = 0

            $totalFiles = [math]::Max($srcFiles.Count, 1)
            $idx = 0

            foreach ($sf in $srcFiles) {
                $idx++
                $rel = $sf.FullName.Substring($srcPrefix.Length)
                [void]$incomingRelSet.Add($rel)
                $destPath = Join-Path $targetDir $rel

                # data\ / backup\ / updater_settings.json 等の保護
                if (Test-IsProtectedRelPath -RelPath $rel) {
                    if (Test-Path -LiteralPath $destPath) {
                        $protectedSkippedCount++
                        & $appendLog ("[保護スキップ] {0}" -f $rel)
                        continue
                    } else {
                        # 初回未存在ファイルのみ配置 (x_history.json 等は誤作成防止のため配布側にも含まれない)
                        $dp = Split-Path -Parent $destPath
                        if (-not (Test-Path -LiteralPath $dp)) { New-Item -ItemType Directory -Path $dp -Force | Out-Null }
                        Copy-Item -LiteralPath $sf.FullName -Destination $destPath -Force
                        if ($chkUnblock.Checked) { try { Unblock-File -LiteralPath $destPath -ErrorAction SilentlyContinue } catch { } }
                        $updatedCount++
                        & $appendLog ("[新規配置] {0}" -f $rel)
                        continue
                    }
                }

                # settings.ini 特別扱い
                if ($rel -ieq 'settings.ini' -and (Test-Path -LiteralPath $destPath)) {
                    if ($radSkipIni.Checked) {
                        $protectedSkippedCount++
                        & $appendLog '[保護スキップ] settings.ini (変更なし)'
                    } else {
                        $mergedIniKeys = @(Merge-SettingsIniFile -ExistingPath $destPath -IncomingPath $sf.FullName)
                        if ($mergedIniKeys.Count -gt 0) {
                            & $appendLog ("[settings.ini マージ] 既存値を維持し新規キー {0} 件を追記: {1}" -f $mergedIniKeys.Count, ($mergedIniKeys -join ', '))
                        } else {
                            & $appendLog '[settings.ini 保護] 既存値をそのまま維持（追記キーなし）'
                        }
                        $protectedSkippedCount++
                    }
                    continue
                }

                try {
                    $dp = Split-Path -Parent $destPath
                    if (-not (Test-Path -LiteralPath $dp)) {
                        New-Item -ItemType Directory -Path $dp -Force | Out-Null
                    }
                    Copy-Item -LiteralPath $sf.FullName -Destination $destPath -Force
                    if ($chkUnblock.Checked) {
                        try { Unblock-File -LiteralPath $destPath -ErrorAction SilentlyContinue } catch { }
                    }
                    $updatedCount++
                } catch {
                    $errorCount++
                    & $appendLog ("[エラー] コピー失敗: {0} ({1})" -f $rel, $_.Exception.Message)
                }

                $pct = 45 + [int](($idx / $totalFiles) * 40)
                if ($pct -gt 85) { $pct = 85 }
                $progressBar.Value = $pct
                if (($idx % 10) -eq 0) { [System.Windows.Forms.Application]::DoEvents() }
            }

            & $appendLog ("上書き完了: 更新 {0} 件 / 保護スキップ・マージ {1} 件 / エラー {2} 件" -f $updatedCount, $protectedSkippedCount, $errorCount)
            $progressBar.Value = 90

            # 5. 不要ファイルの検出 & 確認後削除
            $deletedCount = 0
            if ($chkDeleteObsolete.Checked) {
                $targetPrefix = $targetDir.TrimEnd('\') + '\'
                $allTargetFiles = @(Get-ChildItem -LiteralPath $targetDir -Recurse -File -ErrorAction SilentlyContinue)
                $obsoleteList = New-Object System.Collections.ArrayList

                foreach ($tf in $allTargetFiles) {
                    $rel = $tf.FullName.Substring($targetPrefix.Length)
                    if (Test-IsProtectedRelPath -RelPath $rel) { continue }
                    if ($rel -ieq 'settings.ini') { continue }
                    if (-not $incomingRelSet.Contains($rel)) {
                        [void]$obsoleteList.Add([PSCustomObject]@{
                            RelPath       = $rel
                            FullPath      = $tf.FullName
                            Length        = $tf.Length
                            LastWriteTime = $tf.LastWriteTime
                        })
                    }
                }

                if ($obsoleteList.Count -gt 0) {
                    & $appendLog ("ZIPに含まれない不要候補ファイルを {0} 件検出しました。削除確認画面を表示します。" -f $obsoleteList.Count)
                    $toDelete = @(Show-ObsoleteFileDeleteDialog -ObsoleteItems @($obsoleteList) -Owner $form)
                    foreach ($delItem in $toDelete) {
                        try {
                            Remove-Item -LiteralPath $delItem.FullPath -Force -ErrorAction Stop
                            $deletedCount++
                            & $appendLog ("[不要ファイル削除] {0}" -f $delItem.RelPath)
                        } catch {
                            $errorCount++
                            & $appendLog ("[エラー] 削除失敗: {0} ({1})" -f $delItem.RelPath, $_.Exception.Message)
                        }
                    }

                    # 空になったサブフォルダを整理 (保護フォルダ除く)
                    if ($deletedCount -gt 0) {
                        $dirs = @(Get-ChildItem -LiteralPath $targetDir -Recurse -Directory -ErrorAction SilentlyContinue |
                            Sort-Object { $_.FullName.Length } -Descending)
                        foreach ($d in $dirs) {
                            $dRel = $d.FullName.Substring($targetPrefix.Length)
                            if (Test-IsProtectedRelPath -RelPath $dRel) { continue }
                            $rem = @(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)
                            if ($rem.Count -eq 0) {
                                try {
                                    Remove-Item -LiteralPath $d.FullName -Force -ErrorAction Stop
                                    & $appendLog ("[空フォルダ整理] {0}" -f $dRel)
                                } catch { }
                            }
                        }
                    }
                } else {
                    & $appendLog '不要ファイルは見つかりませんでした。'
                }
            }

            $progressBar.Value = 100
            & $appendLog '更新処理が正常に完了しました。'

            $summary = "PhotoTools の更新が完了しました。`r`n`r`n" +
                       "更新・配置ファイル : $updatedCount 件`r`n" +
                       "保護/マージ対象    : $protectedSkippedCount 件`r`n" +
                       "削除した不要ファイル : $deletedCount 件`r`n" +
                       "エラー件数         : $errorCount 件"
            if (-not [string]::IsNullOrWhiteSpace($backupDir)) {
                $summary += "`r`n`r`nバックアップ先:`r`n$backupDir"
            }
            if ($mergedIniKeys.Count -gt 0) {
                $summary += "`r`n`r`nsettings.ini 追記キー:`r`n" + ($mergedIniKeys -join "`r`n")
            }

            $icon = if ($errorCount -gt 0) { [System.Windows.Forms.MessageBoxIcon]::Warning } else { [System.Windows.Forms.MessageBoxIcon]::Information }
            [System.Windows.Forms.MessageBox]::Show($form, $summary, '更新完了', [System.Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
        } catch {
            $progressBar.Value = 0
            & $appendLog ("[致命的エラー] " + $_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show($form, "更新中にエラーが発生しました。`r`n`r`n$($_.Exception.Message)", '更新エラー', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        } finally {
            if (Test-Path -LiteralPath $tempDir) {
                try { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
            }
            & $setBusy $false
        }
    })

    # フォーム表示時に既存一致ZIPがあれば初期表示に反映 (サイレント検索)
    $form.Add_Shown({
        try {
            $initMatches = @(Find-MatchingZipFiles -DownloadDir $txtDownloadDir.Text.Trim() -BaseFileName $txtBaseFileName.Text.Trim())
            if ($initMatches.Count -gt 0) {
                & $setSelectedZipDisplay $initMatches[0].FullName ("起動時自動検出 (一致 {0} 件中 最新)" -f $initMatches.Count)
                & $appendLog ("起動時に最新ZIPを検出しました: {0}" -f $initMatches[0].Name)
            } else {
                & $appendLog '準備完了。ZIPを選択するか、GitHubから最新ZIPを取得して更新を実行してください。'
            }
        } catch { }
    })

    [void]$form.ShowDialog()
    $form.Dispose()
}

try {
    Show-PhotoToolsUpdaterGui
} catch {
    $errText = "PhotoTools 更新支援ツールで予期しないエラーが発生しました。`r`n`r`n$($_.Exception.Message)`r`n$($_.ScriptStackTrace)"
    [System.Windows.Forms.MessageBox]::Show($errText, 'PhotoToolsUpdater エラー', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}
