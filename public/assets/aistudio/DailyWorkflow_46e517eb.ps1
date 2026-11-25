#requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

$WorkflowDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $WorkflowDir
$CommonDir = Join-Path $RootDir "common"

. (Join-Path $CommonDir "LogHelper.ps1")
. (Join-Path $CommonDir "ConfigHelper.ps1")
. (Join-Path $CommonDir "PhotoInfoHelper.ps1")
. (Join-Path $CommonDir "ExcelHelper.ps1")
. (Join-Path $CommonDir "GigaFileHelper.ps1")

. (Join-Path $WorkflowDir "WorkflowStep1Helper.ps1")
. (Join-Path $WorkflowDir "WorkflowStep2Helper.ps1")
. (Join-Path $WorkflowDir "WorkflowStep3Helper.ps1")
. (Join-Path $WorkflowDir "WorkflowStep4Helper.ps1")
. (Join-Path $WorkflowDir "WorkflowStep5Helper.ps1")

Initialize-PhotoLogger -RootDir $RootDir
$Config = Get-PhotoToolConfig -RootDir $RootDir

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "PhotoTools 日次ワークフロー (Step1〜Step5 & ギガファイル便連携)"
$Form.Size = New-Object System.Drawing.Size(860, 680)
$Form.StartPosition = "CenterScreen"
$Form.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9.5)
$Form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 250)

$LblHeader = New-Object System.Windows.Forms.Label
$LblHeader.Text = "現像後フォルダ一覧（選択してギガファイル便送信・個別編集・各ステップ実行）"
$LblHeader.Location = New-Object System.Drawing.Point(16, 14)
$LblHeader.AutoSize = $true
$Form.Controls.Add($LblHeader)

$LstFolders = New-Object System.Windows.Forms.ListBox
$LstFolders.Location = New-Object System.Drawing.Point(16, 40)
$LstFolders.Size = New-Object System.Drawing.Size(810, 180)
$LstFolders.SelectionMode = "MultiExtended"
$Form.Controls.Add($LstFolders)

function Update-DevFolderList {
    $LstFolders.Items.Clear()
    $devRoot = $Config.DevRootDir
    if (-not [string]::IsNullOrWhiteSpace($devRoot) -and (Test-Path -LiteralPath $devRoot)) {
        $dirs = Get-ChildItem -LiteralPath $devRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
        foreach ($d in $dirs) {
            [void]$LstFolders.Items.Add($d.FullName)
        }
    }
}

$BtnRefresh = New-Object System.Windows.Forms.Button
$BtnRefresh.Text = "一覧更新"
$BtnRefresh.Location = New-Object System.Drawing.Point(16, 228)
$BtnRefresh.Size = New-Object System.Drawing.Size(110, 32)
$BtnRefresh.Add_Click({ Update-DevFolderList })
$Form.Controls.Add($BtnRefresh)

$BtnGigaSend = New-Object System.Windows.Forms.Button
$BtnGigaSend.Text = "選択フォルダをギガファイル便で送る（URL自動反映）"
$BtnGigaSend.Location = New-Object System.Drawing.Point(136, 228)
$BtnGigaSend.Size = New-Object System.Drawing.Size(340, 32)
$BtnGigaSend.BackColor = [System.Drawing.Color]::FromArgb(26, 115, 232)
$BtnGigaSend.ForeColor = [System.Drawing.Color]::White
$BtnGigaSend.FlatStyle = "Flat"
$Form.Controls.Add($BtnGigaSend)

$TxtWorkflowLog = New-Object System.Windows.Forms.TextBox
$TxtWorkflowLog.Location = New-Object System.Drawing.Point(16, 360)
$TxtWorkflowLog.Size = New-Object System.Drawing.Size(810, 260)
$TxtWorkflowLog.Multiline = $true
$TxtWorkflowLog.ReadOnly = $true
$TxtWorkflowLog.ScrollBars = "Vertical"
$TxtWorkflowLog.BackColor = [System.Drawing.Color]::White
$TxtWorkflowLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$Form.Controls.Add($TxtWorkflowLog)

function Append-WfLog {
    param([string]$Msg)
    $ts = (Get-Date).ToString("HH:mm:ss")
    $TxtWorkflowLog.AppendText("[$ts] $Msg`r`n")
    Write-LogInfo -ModuleName "DailyWorkflow" -Message $Msg
}

$BtnGigaSend.Add_Click({
    $selected = @($LstFolders.SelectedItems)
    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("送信する現像後フォルダを1つ以上選択してください。", "未選択", "OK", "Warning") | Out-Null
        return
    }
    Append-WfLog "ギガファイル便連携を起動します (選択数: $($selected.Count) 件)"
    try {
        $res = Invoke-GigaFileUploadWithCallback -TargetPaths $selected -RootDir $RootDir
        if ($null -ne $res -and -not [string]::IsNullOrWhiteSpace($res.Url)) {
            Append-WfLog "共有URL取得成功: $($res.Url) (削除キー: $($res.DelKey))"
            foreach ($folderPath in $selected) {
                $info = Get-PhotoInfoData -FolderPath $folderPath
                $info.ShareUrl = $res.Url
                $memo = "[ギガファイル便] URL=$($res.Url) / PW=$($res.Password) / 削除キー=$($res.DelKey) / 期限=$($res.LifetimeDays)日"
                if ([string]::IsNullOrWhiteSpace($info.Notes)) {
                    $info.Notes = $memo
                } else {
                    $info.Notes = $info.Notes + "`r`n" + $memo
                }
                Save-PhotoInfoData -FolderPath $folderPath -Data $info
                Append-WfLog "写真情報.txt へ自動反映しました: $folderPath"
            }
        } else {
            Append-WfLog "ギガファイル便の送信はキャンセルされたか、URLが返却されませんでした。"
        }
    } catch {
        Write-LogError -ModuleName "DailyWorkflow" -Message $_.Exception.Message -ErrorRecord $_
        Append-WfLog "[ERROR] $($_.Exception.Message)"
    }
})

$StepLabels = @("Step1 仕分け作成", "Step2 RAW複製移動", "Step3 現像後振分", "Step4 重複JPG削除", "Step5 アーカイブ移動")
for ($i = 0; $i -lt $StepLabels.Count; $i++) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $StepLabels[$i]
    $btn.Location = New-Object System.Drawing.Point((16 + ($i * 164)), 275)
    $btn.Size = New-Object System.Drawing.Size(154, 36)
    $stepIdx = $i + 1
    $btn.Tag = $stepIdx
    $btn.Add_Click({
        param($sender, $e)
        $num = $sender.Tag
        Append-WfLog "Step$num を実行します..."
        try {
            switch ($num) {
                1 { Invoke-WorkflowStep1 -Config $Config }
                2 { Invoke-WorkflowStep2 -Config $Config }
                3 { Invoke-WorkflowStep3 -Config $Config }
                4 { Invoke-WorkflowStep4 -Config $Config }
                5 { Invoke-WorkflowStep5 -Config $Config }
            }
            Append-WfLog "Step$num が完了しました。"
            Update-DevFolderList
        } catch {
            Write-LogError -ModuleName "DailyWorkflow" -Message $_.Exception.Message -ErrorRecord $_
            Append-WfLog "[ERROR] Step$num 失敗: $($_.Exception.Message)"
        }
    })
    $Form.Controls.Add($btn)
}

Update-DevFolderList
[void]$Form.ShowDialog()
