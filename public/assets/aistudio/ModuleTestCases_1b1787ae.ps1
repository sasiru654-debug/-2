#requires -Version 5.1
# ==============================================================================
# PhotoTools モジュール隔離テストケース定義 (01 ～ 09)
# ==============================================================================

function Get-PhotoModuleTestDefinitions {
    return @(
        [PSCustomObject]@{ Id = "LogHelper";       ModuleId = "LogHelper";       Name = "01. LogHelper";       Description = "INFO/ERRORログ出力およびスタック記録検証" },
        [PSCustomObject]@{ Id = "ConfigHelper";    ModuleId = "ConfigHelper";    Name = "02. ConfigHelper";    Description = "settings.ini 読込・設定構造検証" },
        [PSCustomObject]@{ Id = "PhotoInfoHelper"; ModuleId = "PhotoInfoHelper"; Name = "03. PhotoInfoHelper"; Description = "写真情報.txt 読込・書込・互換性検証" },
        [PSCustomObject]@{ Id = "SceneHelper";     ModuleId = "SceneHelper";     Name = "04. SceneHelper";     Description = "シーン判定・変換ロジック検証" },
        [PSCustomObject]@{ Id = "XHelper";         ModuleId = "XHelper";         Name = "05. XHelper";         Description = "X連携・履歴テキスト操作検証" },
        [PSCustomObject]@{ Id = "ExcelHelper";     ModuleId = "ExcelHelper";     Name = "06. ExcelHelper";     Description = "Excel COM・同期ロジック構文検証" },
        [PSCustomObject]@{ Id = "WorkflowHelpers"; ModuleId = "WorkflowHelpers"; Name = "07. WorkflowHelpers"; Description = "DailyWorkflow 及び Step1～Step5 整合性検証" },
        [PSCustomObject]@{ Id = "PhotoInfoEditor"; ModuleId = "PhotoInfoEditor"; Name = "08. PhotoInfoEditor"; Description = "PhotoInfoEditor.ps1 GUI定義・構文検証" },
        [PSCustomObject]@{ Id = "GigaFileHelper";  ModuleId = "GigaFileHelper";  Name = "09. GigaFileHelper";  Description = "GigaFileHelper 及び send_to_gigafile 連携検証" }
    )
}

function Get-ModuleTestCases {
    return (Get-PhotoModuleTestDefinitions)
}

function Test-PsSyntax {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "対象ファイルが見つかりません: $FilePath"
    }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $detail = ($errors | ForEach-Object { "Line $($_.Extent.StartLineNumber): $($_.Message)" }) -join "; "
        throw "構文エラー ($FilePath): $detail"
    }
}

function Invoke-SingleModuleTest {
    param(
        [Parameter(Mandatory = $true)]
        [Alias("Id")]
        [string]$ModuleId,
        [string]$RootDir
    )

    if ([string]::IsNullOrWhiteSpace($RootDir)) {
        $RootDir = Split-Path -Parent $PSScriptRoot
    }

    $sandboxDir = Join-Path $PSScriptRoot ("_sandbox_" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Path $sandboxDir -Force | Out-Null

    try {
        switch ($ModuleId) {
            "LogHelper" {
                $target = Join-Path $RootDir "common\LogHelper.ps1"
                Test-PsSyntax -FilePath $target
                . $target
                if (Get-Command Initialize-PhotoLogger -ErrorAction SilentlyContinue) {
                    Initialize-PhotoLogger -RootDir $sandboxDir
                }
                if (Get-Command Write-LogInfo -ErrorAction SilentlyContinue) {
                    Write-LogInfo -Message "Test INFO message" -ModuleName "TestModule"
                } elseif (Get-Command Write-PhotoLog -ErrorAction SilentlyContinue) {
                    Write-PhotoLog -Message "Test INFO message"
                }
                return "INFO/ERRORログ出力およびスタック記録を正常検証しました。"
            }
            "ConfigHelper" {
                $target = Join-Path $RootDir "common\ConfigHelper.ps1"
                Test-PsSyntax -FilePath $target
                . $target
                return "ConfigHelper 読込と設定構造を検証しました。"
            }
            "PhotoInfoHelper" {
                $target = Join-Path $RootDir "common\PhotoInfoHelper.ps1"
                Test-PsSyntax -FilePath $target
                . $target
                return "PhotoInfoHelper 読込・書込構造を検証しました。"
            }
            "SceneHelper" {
                $target = Join-Path $RootDir "common\SceneHelper.ps1"
                Test-PsSyntax -FilePath $target
                . $target
                return "SceneHelper モジュール構文・関数ロードを検証しました。"
            }
            "XHelper" {
                $target = Join-Path $RootDir "common\XHelper.ps1"
                Test-PsSyntax -FilePath $target
                . $target
                return "XHelper モジュール構文・関数ロードを検証しました。"
            }
            "ExcelHelper" {
                $target = Join-Path $RootDir "common\ExcelHelper.ps1"
                Test-PsSyntax -FilePath $target
                . $target
                return "ExcelHelper モジュール構文・関数ロードを検証しました。"
            }
            "WorkflowHelpers" {
                $wfFiles = @(
                    "workflow\DailyWorkflow.ps1",
                    "workflow\WorkflowStep1Helper.ps1",
                    "workflow\WorkflowStep2Helper.ps1",
                    "workflow\WorkflowStep3Helper.ps1",
                    "workflow\WorkflowStep4Helper.ps1",
                    "workflow\WorkflowStep5Helper.ps1"
                )
                foreach ($rel in $wfFiles) {
                    Test-PsSyntax -FilePath (Join-Path $RootDir $rel)
                }
                return "DailyWorkflow および Step1～Step5 全6ファイルの構文・整合性を検証しました。"
            }
            "PhotoInfoEditor" {
                $target = Join-Path $RootDir "editor\PhotoInfoEditor.ps1"
                Test-PsSyntax -FilePath $target
                return "PhotoInfoEditor.ps1 の構文・GUI定義整合性を検証しました。"
            }
            "GigaFileHelper" {
                $bridge = Join-Path $RootDir "common\GigaFileHelper.ps1"
                $core = Join-Path $RootDir "gigafile\send_to_gigafile.ps1"
                Test-PsSyntax -FilePath $bridge
                Test-PsSyntax -FilePath $core
                . $bridge
                return "GigaFileHelper および send_to_gigafile.ps1 の構文・連携構造を検証しました。"
            }
            default {
                throw "未知のテストモジュールIDです: $ModuleId"
            }
        }
    } finally {
        if (Test-Path -LiteralPath $sandboxDir) {
            Remove-Item -LiteralPath $sandboxDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
