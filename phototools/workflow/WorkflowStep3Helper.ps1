#requires -Version 5.1
# ==============================================================================
# WorkflowStep3Helper.ps1 - Step3: 現像済みJPEG自動振分・進捗リストGUI・1秒監視・保留管理 (UTF-8 BOM / CRLF)
# ==============================================================================

function Find-Step3DateDir {
    param(
        [string]$BaseRoot,
        [string]$DateFolderName
    )
    if ([string]::IsNullOrWhiteSpace($BaseRoot) -or [string]::IsNullOrWhiteSpace($DateFolderName)) { return "" }
    $normBase = $BaseRoot.Trim().TrimEnd('\')
    $exact = Join-Path $normBase $DateFolderName
    if (Test-Path -LiteralPath $exact) { return $exact }

    if ((Test-Path -LiteralPath $normBase) -and (Get-Command Resolve-DateFromFolderName -ErrorAction SilentlyContinue)) {
        $targetDt = Resolve-DateFromFolderName -FolderName $DateFolderName
        if ($null -ne $targetDt) {
            foreach ($sd in @(Get-ChildItem -LiteralPath $normBase -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
                $candDt = Resolve-DateFromFolderName -FolderName $sd.Name
                if ($null -ne $candDt -and $candDt.Date -eq $targetDt.Date) {
                    return $sd.FullName
                }
            }
        }
    }
    return ""
}

function Invoke-WorkflowStep3 {
    param(
        [Parameter(Mandatory=$true)][string]$DateFolderName,
        [Parameter(Mandatory=$true)][hashtable]$Config,
        [string]$RawDateFolder = "",
        [string]$ImportDateFolder = "",
        [string]$DevelopedDateFolder = "",
        [switch]$Overwrite = $false,
        [hashtable]$FileCache = $null,
        [scriptblock]$LogCallback = $null
    )
    $devRoot = "G:\写真\現像後"
    if ($null -ne $Config) {
        if ($Config.ContainsKey("DevelopedRoot")) {
            $devRoot = [string]$Config["DevelopedRoot"]
        } elseif ($Config.ContainsKey("Paths") -and $Config.Paths -is [hashtable] -and $Config.Paths.ContainsKey("DevelopedRoot")) {
            $devRoot = [string]$Config.Paths["DevelopedRoot"]
        }
    }

    $rawRoot = "G:\写真raw"
    if ($null -ne $Config) {
        if ($Config.ContainsKey("RawSaveRoot")) {
            $rawRoot = [string]$Config["RawSaveRoot"]
        } elseif ($Config.ContainsKey("Paths") -and $Config.Paths -is [hashtable] -and $Config.Paths.ContainsKey("RawSaveRoot")) {
            $rawRoot = [string]$Config.Paths["RawSaveRoot"]
        }
    }

    $devDateDir = ""
    if (-not [string]::IsNullOrWhiteSpace($DevelopedDateFolder) -and (Test-Path -LiteralPath $DevelopedDateFolder)) {
        $devDateDir = $DevelopedDateFolder.Trim().TrimEnd('\')
    } else {
        $devDateDir = Find-Step3DateDir -BaseRoot $devRoot -DateFolderName $DateFolderName
    }
    if ([string]::IsNullOrWhiteSpace($devDateDir)) { $devDateDir = Join-Path $devRoot $DateFolderName }

    $rawDateDir = ""
    if (-not [string]::IsNullOrWhiteSpace($RawDateFolder) -and (Test-Path -LiteralPath $RawDateFolder)) {
        $rawDateDir = $RawDateFolder.Trim().TrimEnd('\')
    } else {
        $rawDateDir = Find-Step3DateDir -BaseRoot $rawRoot -DateFolderName $DateFolderName
    }
    if ([string]::IsNullOrWhiteSpace($rawDateDir)) { $rawDateDir = Join-Path $rawRoot $DateFolderName }

    $impDateDir = if (-not [string]::IsNullOrWhiteSpace($ImportDateFolder) -and (Test-Path -LiteralPath $ImportDateFolder)) {
        $ImportDateFolder.Trim().TrimEnd('\')
    } else {
        $foundImp = ""
        $impRoots = New-Object System.Collections.Generic.List[string]
        foreach ($src in @($Config, $(if($Config.ContainsKey("Paths")){ $Config.Paths }))) {
            if ($null -ne $src -and $src -is [System.Collections.IDictionary]) {
                foreach ($k in @("ImportRoot1", "ImportRoot2", "ImportRoot")) {
                    if ($src.ContainsKey($k)) {
                        $val = [string]$src[$k]
                        if (-not [string]::IsNullOrWhiteSpace($val)) { [void]$impRoots.Add($val) }
                    }
                }
            }
        }
        foreach ($ir in $impRoots) {
            if ([string]::IsNullOrWhiteSpace([string]$ir)) { continue }
            $cand = Find-Step3DateDir -BaseRoot ([string]$ir) -DateFolderName $DateFolderName
            if (-not [string]::IsNullOrWhiteSpace($cand)) { $foundImp = $cand; break }
        }
        $foundImp
    }

    $rawExts = @()
    if ($Config.ContainsKey("Extensions") -and $Config.Extensions -is [System.Collections.IDictionary] -and $Config.Extensions.ContainsKey("RawExtensions")) {
        $rawExts = @($Config.Extensions["RawExtensions"] | ForEach-Object { ([string]$_).Trim().ToUpper() })
    } else {
        $rawExts = @(".ARW", ".CR2", ".CR3", ".NEF", ".RAF", ".ORF", ".RW2", ".DNG")
    }

    $imgExts = @()
    if ($Config.ContainsKey("Extensions") -and $Config.Extensions -is [System.Collections.IDictionary] -and $Config.Extensions.ContainsKey("ImageExtensions")) {
        $imgExts = @($Config.Extensions["ImageExtensions"] | ForEach-Object { ([string]$_).Trim().ToUpper() })
    } else {
        $imgExts = @(".JPG", ".JPEG", ".PNG", ".TIF", ".TIFF")
    }

    $refMap = @{}
    $refSource = ""

    if (-not [string]::IsNullOrWhiteSpace($rawDateDir) -and (Test-Path -LiteralPath $rawDateDir)) {
        Get-ChildItem -LiteralPath $rawDateDir -File -Recurse | Where-Object { $rawExts -contains $_.Extension.ToUpper() } | ForEach-Object {
            $relDir = $_.DirectoryName.Substring($rawDateDir.Length).TrimStart("\")
            if (-not [string]::IsNullOrEmpty($relDir)) {
                $refMap[$_.BaseName.ToUpper()] = $relDir
            }
        }
        if ($refMap.Count -gt 0) { $refSource = "RAW" }
    }

    if ($refMap.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($impDateDir) -and (Test-Path -LiteralPath $impDateDir)) {
        Get-ChildItem -LiteralPath $impDateDir -File -Recurse | Where-Object { ($rawExts -contains $_.Extension.ToUpper()) -or ($imgExts -contains $_.Extension.ToUpper()) } | ForEach-Object {
            $relDir = $_.DirectoryName.Substring($impDateDir.Length).TrimStart("\")
            if (-not [string]::IsNullOrEmpty($relDir)) {
                $refMap[$_.BaseName.ToUpper()] = $relDir
            }
        }
        if ($refMap.Count -gt 0) { $refSource = "Import" }
    }

    if ($refMap.Count -eq 0) {
        $skipMsg = "RAWデータおよび取り込みデータが存在しないため、自動振分をスキップしました [$DateFolderName]。"
        if ($null -ne $LogCallback) { & $LogCallback $skipMsg }
        if (Get-Command Write-PhotoLog -ErrorAction SilentlyContinue) {
            Write-PhotoLog -Message $skipMsg -ModuleName "WorkflowStep3" -Level "INFO" | Out-Null
        }
        return @{ SortedCount = 0; Skipped = $true; Message = $skipMsg; RefSource = "None"; PendingFiles = @() }
    }

    $sorted = 0
    $pendingList = New-Object System.Collections.Generic.List[PSCustomObject]

    Get-ChildItem -LiteralPath $devDateDir -File | ForEach-Object {
        if ($_.Name -ieq "写真情報.txt" -or $_.Name -ieq "scene.txt" -or $_.Name -ieq "event.txt") { return }
        $filePath = $_.FullName
        $lastWrite = $_.LastWriteTimeUtc.Ticks
        $key = $_.BaseName.ToUpper()
        $srcName = $_.Name
        $relSrc = $_.FullName.Substring($devDateDir.Length).TrimStart("\")
        if ([string]::IsNullOrWhiteSpace($relSrc)) { $relSrc = $srcName }

        if ($null -ne $FileCache -and $FileCache.ContainsKey($filePath)) {
            $cached = $FileCache[$filePath]
            if ($cached -is [hashtable] -and $cached.Ticks -eq $lastWrite) {
                if ($cached.Status -eq "Pending") {
                    [void]$pendingList.Add([PSCustomObject]@{ Path = $relSrc; Reason = $cached.Reason })
                    return
                } elseif ($cached.Status -eq "Sorted") {
                    return
                }
            } elseif ($cached -is [long] -and $cached -eq $lastWrite) {
                return
            }
        }

        if ($null -ne $LogCallback) { & $LogCallback "[チェック] $srcName のRAW参照を検索中..." }

        if ($refMap.ContainsKey($key)) {
            $subRel = $refMap[$key]
            if ($null -ne $LogCallback) { & $LogCallback "  ➔ RAW参照発見: $subRel (参照元:$refSource)" }

            $destDir = Join-Path $devDateDir $subRel
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            $destFile = Join-Path $destDir $_.Name
            $relDest = Join-Path $subRel $_.Name

            if ((-not (Test-Path -LiteralPath $destFile)) -or $Overwrite) {
                Move-Item -LiteralPath $_.FullName -Destination $destFile -Force
                $sorted++
                $note = if ($Overwrite -and (Test-Path -LiteralPath $destFile)) { " (上書き移動)" } else { "" }
                if ($null -ne $LogCallback) {
                    & $LogCallback "対象ファイル：（$srcName）　移動元：（$relSrc）→移送先：（$relDest）$note"
                }
                if ($null -ne $FileCache) {
                    $FileCache[$filePath] = @{ Ticks = $lastWrite; Status = "Sorted"; Reason = "" }
                }
            } else {
                $reason = "移送先に同名ファイルが存在するためスキップ（上書きオフ）"
                [void]$pendingList.Add([PSCustomObject]@{ Path = $relSrc; Reason = $reason })
                if ($null -ne $LogCallback) {
                    & $LogCallback "  ➔ $reason"
                    & $LogCallback "対象ファイル：（$srcName）　移動元：（$relSrc）→移送先：（スキップ：同名ファイル存在 ※保留）"
                }
                if ($null -ne $FileCache) {
                    $FileCache[$filePath] = @{ Ticks = $lastWrite; Status = "Pending"; Reason = $reason }
                }
            }
        } else {
            $reason = "RAW参照なし"
            [void]$pendingList.Add([PSCustomObject]@{ Path = $relSrc; Reason = $reason })
            if ($null -ne $LogCallback) {
                & $LogCallback "  ➔ RAW参照が見つからなかったため振分をスキップしました（保留）"
                & $LogCallback "対象ファイル：（$srcName）　移動元：（$relSrc）→移送先：（なし：RAW参照なし ※保留）"
            }
            if ($null -ne $FileCache) {
                $FileCache[$filePath] = @{ Ticks = $lastWrite; Status = "Pending"; Reason = $reason }
            }
        }
    }

    if ($sorted -gt 0) {
        $doneMsg = "Step3完了: 現像データ自動振分($sorted 件 / 参照元:$refSource) [$DateFolderName]"
        if ($null -ne $LogCallback) { & $LogCallback $doneMsg }
        if (Get-Command Write-PhotoLog -ErrorAction SilentlyContinue) {
            Write-PhotoLog -Message $doneMsg -ModuleName "WorkflowStep3" -Level "INFO" | Out-Null
        }
    }
    return @{ SortedCount = $sorted; Skipped = $false; Message = "自動振分完了 ($sorted 件)"; RefSource = $refSource; PendingFiles = @($pendingList) }
}

function Show-WorkflowStep3Dialog {
    param(
        [Parameter(Mandatory=$true)][string]$DateFolderName,
        [Parameter(Mandatory=$true)][hashtable]$Config,
        [string]$RawDateFolder = "",
        [string]$ImportDateFolder = "",
        [string]$DevelopedDateFolder = ""
    )
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Step 3: 現像済みJPEG自動振分・進捗リスト＆1秒監視モード"
    $dlg.Size = New-Object System.Drawing.Size(740, 560)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5)
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 250)

    $devRoot = "G:\写真\現像後"
    if ($null -ne $Config) {
        if ($Config.ContainsKey("DevelopedRoot")) {
            $devRoot = [string]$Config["DevelopedRoot"]
        } elseif ($Config.ContainsKey("Paths") -and $Config.Paths -is [hashtable] -and $Config.Paths.ContainsKey("DevelopedRoot")) {
            $devRoot = [string]$Config.Paths["DevelopedRoot"]
        }
    }

    $rawRoot = "G:\写真raw"
    if ($null -ne $Config) {
        if ($Config.ContainsKey("RawSaveRoot")) {
            $rawRoot = [string]$Config["RawSaveRoot"]
        } elseif ($Config.ContainsKey("Paths") -and $Config.Paths -is [hashtable] -and $Config.Paths.ContainsKey("RawSaveRoot")) {
            $rawRoot = [string]$Config.Paths["RawSaveRoot"]
        }
    }

    $devDateDir = ""
    if (-not [string]::IsNullOrWhiteSpace($DevelopedDateFolder) -and (Test-Path -LiteralPath $DevelopedDateFolder)) {
        $devDateDir = $DevelopedDateFolder.Trim().TrimEnd('\')
    } else {
        $devDateDir = Find-Step3DateDir -BaseRoot $devRoot -DateFolderName $DateFolderName
    }
    if ([string]::IsNullOrWhiteSpace($devDateDir)) { $devDateDir = Join-Path $devRoot $DateFolderName }

    $rawDateDir = ""
    if (-not [string]::IsNullOrWhiteSpace($RawDateFolder) -and (Test-Path -LiteralPath $RawDateFolder)) {
        $rawDateDir = $RawDateFolder.Trim().TrimEnd('\')
    } else {
        $rawDateDir = Find-Step3DateDir -BaseRoot $rawRoot -DateFolderName $DateFolderName
    }
    if ([string]::IsNullOrWhiteSpace($rawDateDir)) { $rawDateDir = Join-Path $rawRoot $DateFolderName }

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = "対象日付フォルダ: $DateFolderName"
    $lblInfo.Location = New-Object System.Drawing.Point(16, 12)
    $lblInfo.Size = New-Object System.Drawing.Size(700, 22)
    $lblInfo.Font = New-Object System.Drawing.Font("Yu Gothic UI", 10, [System.Drawing.FontStyle]::Bold)
    $dlg.Controls.Add($lblInfo)

    $lblDevPath = New-Object System.Windows.Forms.Label
    $lblDevPath.Text = "振分対象フォルダフルパス： $devDateDir"
    $lblDevPath.Location = New-Object System.Drawing.Point(16, 36)
    $lblDevPath.Size = New-Object System.Drawing.Size(700, 20)
    $lblDevPath.Font = New-Object System.Drawing.Font("Yu Gothic UI", 8.5)
    $dlg.Controls.Add($lblDevPath)

    $lblRawPath = New-Object System.Windows.Forms.Label
    $lblRawPath.Text = "比較先RAWフォルダフルパス： $rawDateDir"
    $lblRawPath.Location = New-Object System.Drawing.Point(16, 56)
    $lblRawPath.Size = New-Object System.Drawing.Size(700, 20)
    $lblRawPath.Font = New-Object System.Drawing.Font("Yu Gothic UI", 8.5)
    $dlg.Controls.Add($lblRawPath)

    $script:isWatchEnabled = $false
    $script:step3PendingFiles = New-Object System.Collections.Generic.List[PSCustomObject]
    $script:step3FileCache = @{}

    $btnOn = New-Object System.Windows.Forms.Button
    $btnOn.Text = "監視 ON"
    $btnOn.Location = New-Object System.Drawing.Point(16, 80)
    $btnOn.Size = New-Object System.Drawing.Size(110, 32)
    $btnOn.BackColor = [System.Drawing.Color]::FromArgb(15, 118, 110)
    $btnOn.ForeColor = [System.Drawing.Color]::White
    $btnOn.FlatStyle = "Flat"
    $btnOn.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $btnOn.Enabled = $true

    $btnOff = New-Object System.Windows.Forms.Button
    $btnOff.Text = "監視 OFF"
    $btnOff.Location = New-Object System.Drawing.Point(134, 80)
    $btnOff.Size = New-Object System.Drawing.Size(110, 32)
    $btnOff.BackColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
    $btnOff.ForeColor = [System.Drawing.Color]::White
    $btnOff.FlatStyle = "Flat"
    $btnOff.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $btnOff.Enabled = $false

    $chkOverwrite = New-Object System.Windows.Forms.CheckBox
    $chkOverwrite.Text = "移動先に同名ファイルがある場合上書きする"
    $chkOverwrite.Location = New-Object System.Drawing.Point(260, 84)
    $chkOverwrite.Size = New-Object System.Drawing.Size(320, 24)
    $chkOverwrite.Checked = $true
    $dlg.Controls.Add($chkOverwrite)

    $btnOn.Add_Click({
        $script:isWatchEnabled = $true
        $btnOn.Enabled = $false
        $btnOff.Enabled = $true
        & $script:AddLog "監視モードを ON にしました（1秒おきの自動振分を開始します）"
    })

    $btnOff.Add_Click({
        $script:isWatchEnabled = $false
        $btnOn.Enabled = $true
        $btnOff.Enabled = $false
        & $script:AddLog "監視モードを OFF にしました"
        if ($script:step3PendingFiles.Count -gt 0) {
            & $script:AddLog "■ 保留ファイル一覧（監視OFFによる解除 / 全 $($script:step3PendingFiles.Count) 件）:"
            foreach ($pf in ($script:step3PendingFiles | Sort-Object { $_.Path })) {
                & $script:AddLog "・$($pf.Path) （理由: $($pf.Reason)）"
            }
            [void]$script:step3PendingFiles.Clear()
            [void]$script:step3FileCache.Clear()
        } else {
            & $script:AddLog "（解除時点での保留ファイルはありません）"
        }
    })

    $dlg.Controls.Add($btnOn)
    $dlg.Controls.Add($btnOff)

    $lblListHeader = New-Object System.Windows.Forms.Label
    $lblListHeader.Text = "■ 自動振分・1秒監視の進捗ログ:"
    $lblListHeader.Location = New-Object System.Drawing.Point(16, 120)
    $lblListHeader.Size = New-Object System.Drawing.Size(700, 22)
    $dlg.Controls.Add($lblListHeader)

    $lstLog = New-Object System.Windows.Forms.ListBox
    $lstLog.Location = New-Object System.Drawing.Point(16, 146)
    $lstLog.Size = New-Object System.Drawing.Size(696, 314)
    $lstLog.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lstLog.BackColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($lstLog)

    $script:AddLog = {
        param([string]$Msg)
        $ts = (Get-Date).ToString("HH:mm:ss")
        $line = "[$ts] $Msg"
        if ($lstLog.InvokeRequired) {
            [void]$dlg.BeginInvoke([System.Windows.Forms.MethodInvoker]{
                [void]$lstLog.Items.Add($line)
                if ($lstLog.Items.Count -gt 0) { $lstLog.TopIndex = $lstLog.Items.Count - 1 }
            })
        } else {
            [void]$lstLog.Items.Add($line)
            if ($lstLog.Items.Count -gt 0) { $lstLog.TopIndex = $lstLog.Items.Count - 1 }
        }
    }

    & $script:AddLog "Step3 ダイアログを起動しました（デフォルト：監視 OFF）。必要に応じて「監視 ON」または「今すぐ振分を実行」を押してください。"

    $btnRun = New-Object System.Windows.Forms.Button
    $btnRun.Text = "今すぐ振分を実行"
    $btnRun.Location = New-Object System.Drawing.Point(16, 470)
    $btnRun.Size = New-Object System.Drawing.Size(160, 36)
    $btnRun.BackColor = [System.Drawing.Color]::FromArgb(15, 118, 110)
    $btnRun.ForeColor = [System.Drawing.Color]::White
    $btnRun.FlatStyle = "Flat"
    $btnRun.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $btnRun.Add_Click({
        & $script:AddLog "手動振分を開始します..."
        try {
            $manualCache = @{}
            $res = Invoke-WorkflowStep3 -DateFolderName $DateFolderName -Config $Config -RawDateFolder $RawDateFolder -ImportDateFolder $ImportDateFolder -DevelopedDateFolder $DevelopedDateFolder -Overwrite:$chkOverwrite.Checked -FileCache $manualCache -LogCallback {
                param($msg)
                & $script:AddLog $msg
            }
            & $script:AddLog "完了: $($res.Message)"
            if ($null -ne $res -and $null -ne $res.PendingFiles -and $res.PendingFiles.Count -gt 0) {
                & $script:AddLog "■ 手動振分完了 - 未振分・保留ファイル一覧（全 $($res.PendingFiles.Count) 件）:"
                foreach ($pf in ($res.PendingFiles | Sort-Object { $_.Path })) {
                    & $script:AddLog "・$($pf.Path) （理由: $($pf.Reason)）"
                }
            } else {
                & $script:AddLog "（手動振分時の未振分・保留ファイルはありません）"
            }
        } catch {
            & $script:AddLog "[エラー] $($_.Exception.Message)"
            Show-MsgBox $_.Exception.Message "エラー" "OK" "Error"
        }
    })
    $dlg.Controls.Add($btnRun)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "閉じる"
    $btnClose.Location = New-Object System.Drawing.Point(552, 470)
    $btnClose.Size = New-Object System.Drawing.Size(160, 36)
    $btnClose.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($btnClose)

    $watchTimer = New-Object System.Windows.Forms.Timer
    $watchTimer.Interval = 1000
    $watchTimer.Add_Tick({
        if ($script:isWatchEnabled) {
            try {
                $res = Invoke-WorkflowStep3 -DateFolderName $DateFolderName -Config $Config -RawDateFolder $RawDateFolder -ImportDateFolder $ImportDateFolder -DevelopedDateFolder $DevelopedDateFolder -Overwrite:$chkOverwrite.Checked -FileCache $script:step3FileCache -LogCallback $script:AddLog
                if ($null -ne $res -and $null -ne $res.PendingFiles) {
                    foreach ($pf in $res.PendingFiles) {
                        $exists = $false
                        foreach ($existing in $script:step3PendingFiles) {
                            if ($existing.Path -ieq $pf.Path) { $exists = $true; break }
                        }
                        if (-not $exists) {
                            [void]$script:step3PendingFiles.Add($pf)
                        }
                    }
                }
            } catch {}
        }
    })
    $watchTimer.Start()

    $dlg.Add_FormClosing({
        if ($null -ne $watchTimer) { $watchTimer.Stop(); $watchTimer.Dispose() }
    })

    [void]$dlg.ShowDialog()
    return @{ Skipped = $false; Message = "Step3 GUIダイアログ終了" }
}

function Start-WorkflowStep3Watcher {
    param(
        [Parameter(Mandatory=$true)][string]$DateFolderName,
        [Parameter(Mandatory=$true)][hashtable]$Config
    )
    $devRoot = "G:\写真\現像後"
    if ($Config.ContainsKey("Paths") -and $Config.Paths -is [System.Collections.IDictionary] -and $Config.Paths.ContainsKey("DevelopedRoot")) {
        $devRoot = [string]$Config.Paths["DevelopedRoot"]
    }
    $devDateDir = Join-Path $devRoot $DateFolderName
    if (-not (Test-Path -LiteralPath $devDateDir)) { throw "監視対象フォルダが存在しません: $devDateDir" }
    $fsw = New-Object System.IO.FileSystemWatcher
    $fsw.Path = $devDateDir
    $fsw.IncludeSubdirectories = $false
    $fsw.EnableRaisingEvents = $true
    Register-ObjectEvent -InputObject $fsw -EventName Created -Action {
        Start-Sleep -Milliseconds 500
        try { Invoke-WorkflowStep3 -DateFolderName $Event.MessageData.DateName -Config $Event.MessageData.Cfg | Out-Null } catch {}
    } -MessageData @{ DateName = $DateFolderName; Cfg = $Config } | Out-Null
    if (Get-Command Write-PhotoLog -ErrorAction SilentlyContinue) {
        Write-PhotoLog -Message "Step3監視モード開始: $devDateDir" -ModuleName "WorkflowStep3" -Level "INFO" | Out-Null
    }
    return $fsw
}
