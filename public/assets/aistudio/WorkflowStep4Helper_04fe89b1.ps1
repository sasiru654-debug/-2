# UTF-8 with BOM
function Show-WorkflowStep4Dialog {
    param(
        [Parameter(Mandatory=$true)][string]$ImportDateFolder,
        [Parameter(Mandatory=$true)][hashtable]$Config
    )
    if (-not (Test-Path -LiteralPath $ImportDateFolder)) { throw "取込先フォルダが存在しません: $ImportDateFolder" }
    $imgExts = $Config.Extensions.ImageExtensions.Split(",") | ForEach-Object { $_.Trim().ToUpper() }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Step 4: 取込先の重複JPG選択削除"
    $dlg.Size = New-Object System.Drawing.Size(500, 420)
    $dlg.StartPosition = "CenterParent"

    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.Location = New-Object System.Drawing.Point(15, 15)
    $clb.Size = New-Object System.Drawing.Size(455, 310)
    $clb.CheckOnClick = $true

    $subDirs = Get-ChildItem -LiteralPath $ImportDateFolder -Directory -Recurse
    foreach ($d in $subDirs) {
        $jpgs = @(Get-ChildItem -LiteralPath $d.FullName -File | Where-Object { $imgExts -contains $_.Extension.ToUpper() })
        if ($jpgs.Count -gt 0) {
            $rel = $d.FullName.Substring($ImportDateFolder.Length).TrimStart("\")
            [void]$clb.Items.Add("$rel ($($jpgs.Count)枚)", $true)
        }
    }
    $dlg.Controls.Add($clb)

    $script:delCount = 0
    $btnDel = New-Object System.Windows.Forms.Button
    $btnDel.Text = "チェックしたフォルダのJPGを削除"
    $btnDel.Location = New-Object System.Drawing.Point(15, 335)
    $btnDel.Size = New-Object System.Drawing.Size(260, 30)
    $btnDel.Add_Click({
        foreach ($item in $clb.CheckedItems) {
            $rel = ($item -split " \(")[0]
            $targetDir = Join-Path $ImportDateFolder $rel
            if (Test-Path -LiteralPath $targetDir) {
                Get-ChildItem -LiteralPath $targetDir -File | Where-Object { $imgExts -contains $_.Extension.ToUpper() } | ForEach-Object {
                    Remove-Item -LiteralPath $_.FullName -Force
                    $script:delCount++
                }
            }
        }
        Write-PhotoLog -Message "Step4完了: 重複JPG削除($($script:delCount)件) [$ImportDateFolder]" -Level "INFO"
        $dlg.Close()
    })
    $dlg.Controls.Add($btnDel)
    [void]$dlg.ShowDialog()
    return @{ DeletedCount = $script:delCount }
}
