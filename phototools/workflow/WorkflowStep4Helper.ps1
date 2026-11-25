#requires -Version 5.1
# ==============================================================================
# WorkflowStep4Helper.ps1 - Step4: フォルダ別ファイル比較・統合リスト ＆ 現像済み取込ファイル削除 (UTF-8 BOM / CRLF)
# ==============================================================================

function Show-WorkflowStep4Dialog {
    param(
        [Parameter(Mandatory=$true)][string]$ImportDateFolder,
        [Parameter(Mandatory=$true)][hashtable]$Config,
        [string]$DevelopedDateFolder = ""
    )
    if ([string]::IsNullOrWhiteSpace($ImportDateFolder) -or -not (Test-Path -LiteralPath $ImportDateFolder)) {
        $msg = "取り込み元フォルダが存在しないため（データ削減済み等）、重複ファイル削除をスキップしました。"
        if (Get-Command Write-PhotoLog -ErrorAction SilentlyContinue) {
            Write-PhotoLog -Message $msg -ModuleName "WorkflowStep4" -Level "INFO" | Out-Null
        }
        return @{ DeletedCount = 0; Skipped = $true; Message = $msg }
    }

    $devRoot = if ($Config.ContainsKey("Paths") -and $Config.Paths -is [System.Collections.IDictionary] -and -not [string]::IsNullOrWhiteSpace([string]$Config.Paths["DevelopedRoot"])) {
        [string]$Config.Paths["DevelopedRoot"]
    } elseif ($Config.ContainsKey("DevelopedRoot")) {
        [string]$Config["DevelopedRoot"]
    } else {
        "G:\写真\現像後"
    }

    $dateName = [System.IO.Path]::GetFileName($ImportDateFolder)
    $devDir = if (-not [string]::IsNullOrWhiteSpace($DevelopedDateFolder) -and (Test-Path -LiteralPath $DevelopedDateFolder)) {
        $DevelopedDateFolder
    } else {
        Join-Path $devRoot $dateName
    }

    $imgExts = if (Get-Command ConvertTo-PhotoExtensionArray -ErrorAction SilentlyContinue) {
        ConvertTo-PhotoExtensionArray $Config.Extensions.ImageExtensions
    } else {
        @($Config.Extensions.ImageExtensions | ForEach-Object { ([string]$_).Trim().ToUpper() })
    }

    function Get-CoreImageName {
        param([string]$FileName)
        if ([string]::IsNullOrWhiteSpace($FileName)) { return "" }
        $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName).Trim()
        # Canon/Camera naming convention: first 8 characters represent the base photo (e.g. IMG_2650 vs IMG_2650_1)
        if ($base.Length -ge 8) {
            $base = $base.Substring(0, 8)
        }
        $core = $base -replace '_\d+$', '' -replace '\s+\d+$', ''
        return $core.ToUpper()
    }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Step 4: フォルダ別ファイル比較・統合リスト (現像側 vs 取込元) ＆ 現像済み取込ファイルの削除"
    $dlg.Size = New-Object System.Drawing.Size(840, 640)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5)
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 250)

    $lblHeader = New-Object System.Windows.Forms.Label
    $lblHeader.Location = New-Object System.Drawing.Point(16, 12)
    $lblHeader.Size = New-Object System.Drawing.Size(800, 24)
    $lblHeader.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $dlg.Controls.Add($lblHeader)

    $lblImpPath = New-Object System.Windows.Forms.Label
    $lblImpPath.Text = "取込元フォルダ： $ImportDateFolder"
    $lblImpPath.Location = New-Object System.Drawing.Point(16, 40)
    $lblImpPath.Size = New-Object System.Drawing.Size(650, 20)
    $lblImpPath.Font = New-Object System.Drawing.Font("Yu Gothic UI", 8.5)
    $dlg.Controls.Add($lblImpPath)

    $btnOpenImp = New-Object System.Windows.Forms.Button
    $btnOpenImp.Text = "取込元を開く"
    $btnOpenImp.Location = New-Object System.Drawing.Point(672, 36)
    $btnOpenImp.Size = New-Object System.Drawing.Size(148, 26)
    $btnOpenImp.FlatStyle = "Flat"
    $btnOpenImp.Font = New-Object System.Drawing.Font("Yu Gothic UI", 8.5)
    $btnOpenImp.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($ImportDateFolder) -and (Test-Path -LiteralPath $ImportDateFolder)) {
            Start-Process explorer.exe -ArgumentList $ImportDateFolder
        } else {
            [System.Windows.Forms.MessageBox]::Show("取込元フォルダが存在しません。", "確認", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    })
    $dlg.Controls.Add($btnOpenImp)

    $lblDevPath = New-Object System.Windows.Forms.Label
    $lblDevPath.Text = "現像側フォルダ： $devDir"
    $lblDevPath.Location = New-Object System.Drawing.Point(16, 68)
    $lblDevPath.Size = New-Object System.Drawing.Size(650, 20)
    $lblDevPath.Font = New-Object System.Drawing.Font("Yu Gothic UI", 8.5)
    $dlg.Controls.Add($lblDevPath)

    $btnOpenDev = New-Object System.Windows.Forms.Button
    $btnOpenDev.Text = "現像側を開く"
    $btnOpenDev.Location = New-Object System.Drawing.Point(672, 64)
    $btnOpenDev.Size = New-Object System.Drawing.Size(148, 26)
    $btnOpenDev.FlatStyle = "Flat"
    $btnOpenDev.Font = New-Object System.Drawing.Font("Yu Gothic UI", 8.5)
    $btnOpenDev.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($devDir)) {
            if (-not (Test-Path -LiteralPath $devDir)) {
                New-Item -ItemType Directory -Path $devDir -Force | Out-Null
            }
            Start-Process explorer.exe -ArgumentList $devDir
        }
    })
    $dlg.Controls.Add($btnOpenDev)

    $tree = New-Object System.Windows.Forms.TreeView
    $tree.Location = New-Object System.Drawing.Point(16, 98)
    $tree.Size = New-Object System.Drawing.Size(804, 430)
    $tree.CheckBoxes = $false
    $tree.FullRowSelect = $true
    $tree.ShowLines = $true
    $tree.ShowPlusMinus = $true
    $tree.ShowRootLines = $true
    $tree.BackColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($tree)

    $subDirs = @(Get-ChildItem -LiteralPath $ImportDateFolder -Directory -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)
    $hasAnyFiles = $false
    $duplicateFilePaths = New-Object System.Collections.Generic.List[string]

    $globalDevCount = 0
    $globalImpCount = 0
    $globalDupCount = 0

    $rootImpFiles = @(Get-ChildItem -LiteralPath $ImportDateFolder -File -ErrorAction SilentlyContinue | Where-Object { $imgExts -contains $_.Extension.ToUpper() })
    if (@($rootImpFiles).Count -gt 0 -or (Test-Path -LiteralPath $devDir)) {
        $relPaths = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        [void]$relPaths.Add("")
        foreach ($d in $subDirs) {
            $rel = $d.FullName.Substring($ImportDateFolder.Length).TrimStart("\")
            [void]$relPaths.Add($rel)
        }
        if (Test-Path -LiteralPath $devDir) {
            foreach ($d in @(Get-ChildItem -LiteralPath $devDir -Directory -Recurse -ErrorAction SilentlyContinue)) {
                $rel = $d.FullName.Substring($devDir.Length).TrimStart("\")
                [void]$relPaths.Add($rel)
            }
        }

        foreach ($rel in ($relPaths | Sort-Object)) {
            $impSubDir = if ([string]::IsNullOrWhiteSpace($rel)) { $ImportDateFolder } else { Join-Path $ImportDateFolder $rel }
            $devSubDir = if ([string]::IsNullOrWhiteSpace($rel)) { $devDir } else { Join-Path $devDir $rel }

            $impFiles = if (Test-Path -LiteralPath $impSubDir -PathType Container) {
                @(Get-ChildItem -LiteralPath $impSubDir -File -ErrorAction SilentlyContinue | Where-Object { $imgExts -contains $_.Extension.ToUpper() })
            } else { @() }

            $devFiles = if (Test-Path -LiteralPath $devSubDir -PathType Container) {
                @(Get-ChildItem -LiteralPath $devSubDir -File -ErrorAction SilentlyContinue | Where-Object { $imgExts -contains $_.Extension.ToUpper() })
            } else { @() }

            if (@($impFiles).Count -gt 0 -or @($devFiles).Count -gt 0) {
                $hasAnyFiles = $true
                $folderLabel = if ([string]::IsNullOrWhiteSpace($rel)) { "(日付ルート直下)" } else { $rel }

                $folderDevCount = @($devFiles).Count
                $folderImpCount = @($impFiles).Count
                $folderDupCount = 0

                $globalDevCount += $folderDevCount
                $globalImpCount += $folderImpCount

                $devCoreMap = @{}
                foreach ($df in $devFiles) {
                    $c = Get-CoreImageName $df.Name
                    if (-not $devCoreMap.ContainsKey($c)) {
                        $devCoreMap[$c] = @($df)
                    } else {
                        $devCoreMap[$c] += $df
                    }
                }

                $impCoreMap = @{}
                foreach ($ifile in $impFiles) {
                    $c = Get-CoreImageName $ifile.Name
                    if (-not $impCoreMap.ContainsKey($c)) {
                        $impCoreMap[$c] = @($ifile)
                    } else {
                        $impCoreMap[$c] += $ifile
                    }
                }

                $allCores = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($k in $devCoreMap.Keys) { [void]$allCores.Add($k) }
                foreach ($k in $impCoreMap.Keys) { [void]$allCores.Add($k) }

                $folderNode = New-Object System.Windows.Forms.TreeNode("📁 フォルダ: $folderLabel")
                $folderNode.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)

                foreach ($core in ($allCores | Sort-Object)) {
                    $devList = @()
                    if ($devCoreMap.ContainsKey($core)) {
                        $devList = @($devCoreMap[$core])
                    }
                    $impList = @()
                    if ($impCoreMap.ContainsKey($core)) {
                        $impList = @($impCoreMap[$core])
                    }

                    $devCount = @($devList).Count
                    $impCount = @($impList).Count
                    $maxLen = [Math]::Max($devCount, $impCount)
                    for ($i = 0; $i -lt $maxLen; $i++) {
                        $df = if ($i -lt $devCount) { $devList[$i] } else { $null }
                        $ifile = if ($i -lt $impCount) { $impList[$i] } else { $null }

                        $devText = if ($null -ne $df) { $df.Name } else { "なし" }
                        $impText = if ($null -ne $ifile) { $ifile.Name } else { "なし" }

                        $isDuplicate = ($null -ne $df) -and ($null -ne $ifile)
                        if ($isDuplicate) {
                            $folderDupCount++
                            $globalDupCount++
                            [void]$duplicateFilePaths.Add($ifile.FullName)
                            $nodeText = "現像側：$devText ➔ 取込元：$impText (重複・削除対象)"
                            $fNode = New-Object System.Windows.Forms.TreeNode("⚠️ $nodeText")
                            $fNode.ForeColor = [System.Drawing.Color]::FromArgb(180, 83, 9)
                        } elseif ($null -ne $df) {
                            $nodeText = "現像側：$devText ➔ 取込元：なし (現像済み)"
                            $fNode = New-Object System.Windows.Forms.TreeNode("✓ $nodeText")
                            $fNode.ForeColor = [System.Drawing.Color]::FromArgb(4, 120, 87)
                        } else {
                            $nodeText = "現像側：なし ➔ 取込元：$impText [取込のみ]"
                            $fNode = New-Object System.Windows.Forms.TreeNode("📦 $nodeText")
                            $fNode.ForeColor = [System.Drawing.Color]::FromArgb(3, 105, 161)
                        }
                        [void]$folderNode.Nodes.Add($fNode)
                    }
                }

                $folderNode.Text = "📁 フォルダ: $folderLabel (現像側: ${folderDevCount}件 / 取込元: ${folderImpCount}件 / 重複: ${folderDupCount}件)"
                [void]$tree.Nodes.Add($folderNode)
            }
        }
    }

    $lblHeader.Text = "全体集計 ➔ 現像側: ${globalDevCount}件 / 取込元: ${globalImpCount}件 / 重複(削除対象): ${globalDupCount}件"

    $tree.ExpandAll()

    if (-not $hasAnyFiles) {
        $msg = "比較対象の画像ファイルが取り込み元および現像後フォルダに見つかりませんでした。"
        if (Get-Command Write-PhotoLog -ErrorAction SilentlyContinue) {
            Write-PhotoLog -Message "$msg [$ImportDateFolder]" -ModuleName "WorkflowStep4" -Level "INFO" | Out-Null
        }
        return @{ DeletedCount = 0; Skipped = $true; Message = $msg }
    }

    $script:delCount = 0
    $btnDel = New-Object System.Windows.Forms.Button
    $dupCount = @($duplicateFilePaths).Count
    $btnDel.Text = "現像済み重複取込ファイル ($dupCount 件) を削除"
    $btnDel.Location = New-Object System.Drawing.Point(16, 538)
    $btnDel.Size = New-Object System.Drawing.Size(320, 42)
    $btnDel.BackColor = [System.Drawing.Color]::FromArgb(185, 28, 28)
    $btnDel.ForeColor = [System.Drawing.Color]::White
    $btnDel.FlatStyle = "Flat"
    $btnDel.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5, [System.Drawing.FontStyle]::Bold)
    if ($dupCount -eq 0) {
        $btnDel.Enabled = $false
        $btnDel.BackColor = [System.Drawing.Color]::FromArgb(156, 163, 175)
    }

    $btnDel.Add_Click({
        if ($dupCount -eq 0) {
            Show-MsgBox "削除対象となる現像済み重複取込ファイルはありません。" "確認" "OK" "Information" | Out-Null
            return
        }

        $ans = Show-MsgBox "現像済みの重複取込ファイル $dupCount 件を削除しますか？`n（取込元側ファイルのみが削除されます）" "削除確認" "YesNo" "Question"
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        foreach ($path in $duplicateFilePaths) {
            if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
                Remove-Item -LiteralPath $path -Force
                $script:delCount++
            }
        }

        if (Get-Command Write-PhotoLog -ErrorAction SilentlyContinue) {
            Write-PhotoLog -Message "Step4完了: 現像済み重複取込ファイル削除($($script:delCount)件) [$ImportDateFolder]" -ModuleName "WorkflowStep4" -Level "INFO" | Out-Null
        }
        Show-MsgBox "$($script:delCount) 件の現像済み重複取込ファイルを削除しました。" "完了" "OK" "Information" | Out-Null
        $dlg.Close()
    })
    $dlg.Controls.Add($btnDel)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "閉じる"
    $btnClose.Location = New-Object System.Drawing.Point(690, 538)
    $btnClose.Size = New-Object System.Drawing.Size(130, 42)
    $btnClose.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($btnClose)

    [void]$dlg.ShowDialog()
    return @{ DeletedCount = $script:delCount; Skipped = $false; Message = "重複取込ファイル削除($($script:delCount)件)" }
}
