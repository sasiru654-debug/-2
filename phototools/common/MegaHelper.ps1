#requires -Version 5.1
# ==============================================================================
# MegaHelper.ps1 - MEGA共有リンク取得・非同期バックグラウンドジョブ＆リアルタイム処理ログポップアップ (UTF-8 BOM / CRLF)
# ==============================================================================

function Write-MegaDiagLog {
    param([string]$Message, [hashtable]$Config = @{}, [string]$Level = "INFO")
    if (Get-Command Write-PhotoLog -ErrorAction SilentlyContinue) {
        Write-PhotoLog -Message $Message -ModuleName "MegaHelper" -Level $Level | Out-Null
    }
    if ($null -ne $Config -and $Config.ContainsKey("MegaLogPath") -and -not [string]::IsNullOrWhiteSpace([string]$Config["MegaLogPath"])) {
        try {
            $lp = [string]$Config["MegaLogPath"]
            $dir = Split-Path -Parent $lp
            if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $ts = (Get-Date).ToString("yyyy/MM/dd HH:mm:ss")
            $enc = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::AppendAllText($lp, "[$ts] [$Level] $Message`r`n", $enc)
        } catch {}
    }
}

function Get-MegaFolderLinkAsync {
    param(
        [Parameter(Position = 0)][string]$FolderPath,
        [Parameter(Position = 1)][hashtable]$Config = @{}
    )
    Write-MegaDiagLog -Message "MEGA共有リンク非同期取得開始: $FolderPath" -Config $Config
    if ([string]::IsNullOrWhiteSpace($FolderPath) -or -not (Test-Path -LiteralPath $FolderPath)) {
        $errMsg = "対象フォルダが存在しません: $FolderPath"
        Write-MegaDiagLog -Message $errMsg -Config $Config -Level "ERROR"
        return @{ Success = $false; Url = ""; Message = $errMsg }
    }

    $resObj = [ordered]@{
        Success = $false
        Url     = ""
        Message = ""
    }

    $liveLogPath = Join-Path ([System.IO.Path]::GetTempPath()) ("phototools_mega_live_" + [Guid]::NewGuid().ToString("N") + ".log")
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($liveLogPath, "", $utf8NoBom)

    # リアルタイム進捗＆処理ログポップアップ
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "MEGA共有リンク取得・診断 (非同期・リアルタイムログ)"
    $dlg.Size = New-Object System.Drawing.Size(580, 400)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.TopMost = $true
    $dlg.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5)
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = "MEGAサーバーとの非同期通信を準備しています..."
    $lblInfo.Location = New-Object System.Drawing.Point(18, 14)
    $lblInfo.Size = New-Object System.Drawing.Size(530, 38)
    $lblInfo.AutoEllipsis = $true
    $dlg.Controls.Add($lblInfo)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(18, 56)
    $progressBar.Size = New-Object System.Drawing.Size(530, 20)
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $progressBar.MarqueeAnimationSpeed = 25
    $dlg.Controls.Add($progressBar)

    $lblLogHeader = New-Object System.Windows.Forms.Label
    $lblLogHeader.Text = "実行処理ログ:"
    $lblLogHeader.Location = New-Object System.Drawing.Point(18, 84)
    $lblLogHeader.AutoSize = $true
    $lblLogHeader.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $dlg.Controls.Add($lblLogHeader)

    $txtLiveLog = New-Object System.Windows.Forms.TextBox
    $txtLiveLog.Location = New-Object System.Drawing.Point(18, 106)
    $txtLiveLog.Size = New-Object System.Drawing.Size(530, 200)
    $txtLiveLog.Multiline = $true
    $txtLiveLog.ReadOnly = $true
    $txtLiveLog.ScrollBars = "Vertical"
    $txtLiveLog.WordWrap = $true
    $txtLiveLog.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
    $txtLiveLog.ForeColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $txtLiveLog.Font = New-Object System.Drawing.Font("Consolas", 9)
    $dlg.Controls.Add($txtLiveLog)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "キャンセル"
    $btnCancel.Location = New-Object System.Drawing.Point(448, 316)
    $btnCancel.Size = New-Object System.Drawing.Size(100, 32)
    $dlg.Controls.Add($btnCancel)

    $state = @{
        JobCancelled = $false
        JobFinished  = $false
        ReadOffset   = [long]0
    }

    $syncLiveLog = {
        if (-not (Test-Path -LiteralPath $liveLogPath)) { return }
        try {
            $fs = New-Object System.IO.FileStream($liveLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                if ($fs.Length -gt $state.ReadOffset) {
                    [void]$fs.Seek($state.ReadOffset, [System.IO.SeekOrigin]::Begin)
                    $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $false, 1024, $true)
                    $chunk = $sr.ReadToEnd()
                    $state.ReadOffset = $fs.Position
                    $sr.Dispose()
                    if (-not [string]::IsNullOrEmpty($chunk)) {
                        $txtLiveLog.AppendText($chunk)
                        $txtLiveLog.SelectionStart = $txtLiveLog.TextLength
                        $txtLiveLog.ScrollToCaret()
                        $lines = @($chunk -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                        foreach ($ln in $lines) {
                            Write-MegaDiagLog -Message $ln -Config $Config
                        }
                        if ($lines.Count -gt 0) {
                            $lastLn = $lines[$lines.Count - 1] -replace '^\[\d{2}:\d{2}:\d{2}\]\s*', ''
                            $lblInfo.Text = "処理中: $lastLn`r`n対象: $FolderPath"
                        }
                    }
                }
            } finally {
                $fs.Dispose()
            }
        } catch {}
    }

    # バックグラウンドジョブの開始
    $job = Start-Job -ScriptBlock {
        param($fPath, $cfgHash, $logFile)

        function Add-StepLog {
            param([string]$Text)
            try {
                $line = "[{0}] {1}`r`n" -f (Get-Date).ToString("HH:mm:ss"), $Text
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
                $fsOut = New-Object System.IO.FileStream($logFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
                try {
                    $fsOut.Write($bytes, 0, $bytes.Length)
                    $fsOut.Flush()
                } finally {
                    $fsOut.Dispose()
                }
            } catch {}
        }

        Add-StepLog "MEGA共有リンク取得ジョブを開始しました。"
        Add-StepLog "対象ローカルフォルダ: $fPath"
        Add-StepLog "MEGAcmd (mega-export) 実行ファイルを確認中..."

        $megaCmd = if ($null -ne $cfgHash -and $cfgHash.ContainsKey("MegaCmdPath") -and -not [string]::IsNullOrWhiteSpace([string]$cfgHash["MegaCmdPath"])) {
            [string]$cfgHash["MegaCmdPath"]
        } else {
            Join-Path $env:LOCALAPPDATA "MEGAcmd\mega-export.bat"
        }
        if (-not (Test-Path -LiteralPath $megaCmd)) {
            $cmdFound = Get-Command "mega-export" -ErrorAction SilentlyContinue
            if ($cmdFound) { $megaCmd = $cmdFound.Source }
        }
        if (-not (Test-Path -LiteralPath $megaCmd)) {
            $msg = "MEGAcmd (mega-export) が見つかりません。settings.ini の MegaCmdPath を確認してください。 (探索パス: $megaCmd)"
            Add-StepLog "[エラー] $msg"
            return @{ Success = $false; Url = ""; Message = $msg }
        }
        Add-StepLog "MEGAcmd 検出OK: $megaCmd"

        $targets = New-Object System.Collections.Generic.List[string]
        [void]$targets.Add($fPath)
        $devRoot = if ($null -ne $cfgHash -and $cfgHash.ContainsKey("DevRoot")) { [string]$cfgHash["DevRoot"] } else { "" }
        $remoteRoot = if ($null -ne $cfgHash -and $cfgHash.ContainsKey("MegaRemoteRoot")) { [string]$cfgHash["MegaRemoteRoot"] } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($devRoot) -and -not [string]::IsNullOrWhiteSpace($remoteRoot)) {
            if ($fPath.StartsWith($devRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                $rel = $fPath.Substring($devRoot.Length).TrimStart('\') -replace '\\', '/'
                if (-not [string]::IsNullOrWhiteSpace($rel)) {
                    $remoteCand = $remoteRoot.TrimEnd('/') + "/" + $rel
                    [void]$targets.Add($remoteCand)
                    Add-StepLog "MEGAリモートパス候補を追加: $remoteCand"
                }
            }
        }

        $lastOutput = ""
        $idx = 0
        $total = $targets.Count
        foreach ($tgt in $targets) {
            $idx++
            Add-StepLog "[$idx/$total] 共有リンク発行を実行中: mega-export -a `"$tgt`""
            $output = (& $megaCmd -a $tgt 2>&1 | Out-String).Trim()
            $lastOutput = $output
            if (-not [string]::IsNullOrWhiteSpace($output)) {
                Add-StepLog "  -> 応答: $output"
            } else {
                Add-StepLog "  -> 応答なし (空出力)"
            }
            if ($output -match "(https://mega\.nz/[^\s\r\n]+)") {
                $foundUrl = $Matches[1]
                Add-StepLog "[成功] MEGA共有リンクを取得しました: $foundUrl"
                return @{ Success = $true; Url = $foundUrl; Message = "MEGAリンク取得成功" }
            }

            Add-StepLog "[$idx/$total] 既存共有リンクを照会中: mega-export `"$tgt`""
            $listOut = (& $megaCmd $tgt 2>&1 | Out-String).Trim()
            if (-not [string]::IsNullOrWhiteSpace($listOut)) {
                Add-StepLog "  -> 照会応答: $listOut"
            }
            if ($listOut -match "(https://mega\.nz/[^\s\r\n]+)") {
                $foundUrl = $Matches[1]
                Add-StepLog "[成功] 既存のMEGA共有リンクを取得しました: $foundUrl"
                return @{ Success = $true; Url = $foundUrl; Message = "既存MEGAリンク取得" }
            }
        }

        $failMsg = "MEGAリンクを取得できませんでした（同期対象外または未ログインの可能性があります）: $lastOutput"
        Add-StepLog "[失敗] $failMsg"
        return @{ Success = $false; Url = ""; Message = $failMsg }
    } -ArgumentList $FolderPath, $Config, $liveLogPath

    $closeDelayTimer = New-Object System.Windows.Forms.Timer
    $closeDelayTimer.Interval = 550
    $closeDelayTimer.Add_Tick({
        $closeDelayTimer.Stop()
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    })

    $btnCancel.Add_Click({
        if ($state.JobFinished) {
            $closeDelayTimer.Stop()
            $dlg.DialogResult = if ($resObj.Success) { [System.Windows.Forms.DialogResult]::OK } else { [System.Windows.Forms.DialogResult]::Cancel }
            $dlg.Close()
        } else {
            $state.JobCancelled = $true
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $dlg.Close()
        }
    })

    $dlg.Add_FormClosing({
        param($sender, $e)
        if (-not $state.JobFinished -and -not $state.JobCancelled) {
            $ans = [System.Windows.Forms.MessageBox]::Show(
                $dlg,
                "MEGAサーバーとの通信処理を実行中です。`n処理を強制終了して閉じますか？",
                "処理中クローズ確認",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
                $e.Cancel = $true
                return
            }
            $state.JobCancelled = $true
        }
    })

    $dlg.Add_Shown({ $dlg.Activate() })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 120
    $timer.Add_Tick({
        & $syncLiveLog

        if ($state.JobCancelled) {
            $timer.Stop()
            $state.JobFinished = $true
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            $resObj.Message = "ユーザーによってキャンセルされました。"
            if ($dlg.Visible) {
                $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
                $dlg.Close()
            }
            return
        }

        if ($job.State -eq "Completed") {
            $timer.Stop()
            & $syncLiveLog
            $jobOut = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            $state.JobFinished = $true

            $jobResult = if ($jobOut.Count -gt 0) { $jobOut[$jobOut.Count - 1] } else { $null }
            if ($null -ne $jobResult -and ($jobResult -is [System.Collections.IDictionary])) {
                $resObj.Success = [bool]$jobResult["Success"]
                $resObj.Url     = [string]$jobResult["Url"]
                $resObj.Message = [string]$jobResult["Message"]
            } else {
                $resObj.Message = "ジョブ結果を受信できませんでした。"
            }

            $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
            if ($resObj.Success) {
                $progressBar.Value = 100
                $lblInfo.Text = "完了: MEGA共有リンクを取得しました。`r`n$($resObj.Url)"
                $btnCancel.Text = "完了"
                $closeDelayTimer.Start()
            } else {
                $progressBar.Value = 0
                $lblInfo.Text = "MEGA共有リンクを取得できませんでした。下の実行処理ログを確認してください。"
                $btnCancel.Text = "閉じる"
            }
        } elseif ($job.State -eq "Failed" -or $job.State -eq "Stopped") {
            $timer.Stop()
            & $syncLiveLog
            $errInfo = ""
            try {
                if ($job.ChildJobs.Count -gt 0 -and $job.ChildJobs[0].JobStateInfo.Reason) {
                    $errInfo = [string]$job.ChildJobs[0].JobStateInfo.Reason.Message
                }
            } catch {}
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            $state.JobFinished = $true
            $resObj.Message = if (-not [string]::IsNullOrWhiteSpace($errInfo)) { "MEGA取得ジョブ異常終了: $errInfo" } else { "MEGA取得ジョブが異常終了しました。" }
            $txtLiveLog.AppendText(("[{0}] [エラー] {1}`r`n" -f (Get-Date).ToString("HH:mm:ss"), $resObj.Message))
            $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
            $progressBar.Value = 0
            $lblInfo.Text = "エラーが発生しました。実行処理ログを確認してください。"
            $btnCancel.Text = "閉じる"
        }
    })
    $timer.Start()

    try {
        [void]$dlg.ShowDialog()
    } finally {
        $timer.Stop()
        $timer.Dispose()
        $closeDelayTimer.Stop()
        $closeDelayTimer.Dispose()
        if (-not $state.JobFinished) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        $dlg.Dispose()
        if (Test-Path -LiteralPath $liveLogPath) {
            Remove-Item -LiteralPath $liveLogPath -Force -ErrorAction SilentlyContinue
        }
    }

    if ($resObj.Success) {
        Write-MegaDiagLog -Message "MEGAリンク取得成功: $($resObj.Url)" -Config $Config
    } else {
        Write-MegaDiagLog -Message $resObj.Message -Config $Config -Level "ERROR"
    }
    return $resObj
}

function Get-MegaFolderLink {
    param(
        [Parameter(Position = 0)][string]$FolderPath,
        [Parameter(Position = 1)][hashtable]$Config = @{}
    )
    return Get-MegaFolderLinkAsync -FolderPath $FolderPath -Config $Config
}

function Get-MegaShareLink {
    param(
        [string]$FolderPath,
        [hashtable]$Config = @{}
    )
    $res = Get-MegaFolderLinkAsync -FolderPath $FolderPath -Config $Config
    if ($res.Success) { return $res.Url }
    throw $res.Message
}
