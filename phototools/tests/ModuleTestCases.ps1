#requires -Version 5.1
# ==============================================================================
# ModuleTestCases.ps1 - PhotoTools Sandbox Tests (01 ～ 10) (UTF-8 BOM / CRLF)
# ==============================================================================

function Get-Tag {
    param([int[]]$Codes)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $Codes) { [void]$sb.Append([char]$c) }
    return $sb.ToString()
}

function Get-PhotoModuleTestDefinitions {
    return @(
        [PSCustomObject]@{ Id = "LogHelper";       ModuleId = "LogHelper";       Name = "01. LogHelper";       Description = "INFO/ERROR log output and path resolution" },
        [PSCustomObject]@{ Id = "ConfigHelper";    ModuleId = "ConfigHelper";    Name = "02. ConfigHelper";    Description = "settings.ini load, compat keys, period calculation" },
        [PSCustomObject]@{ Id = "PhotoInfoHelper"; ModuleId = "PhotoInfoHelper"; Name = "03. PhotoInfoHelper"; Description = "PhotoInfo.txt read/write and multi-person migration" },
        [PSCustomObject]@{ Id = "SceneHelper";     ModuleId = "SceneHelper";     Name = "04. SceneHelper";     Description = "Scene history, candidates, same-model search" },
        [PSCustomObject]@{ Id = "XHelper";         ModuleId = "XHelper";         Name = "05. XHelper";         Description = "X account normalization and dates JSON history" },
        [PSCustomObject]@{ Id = "ExcelHelper";     ModuleId = "ExcelHelper";     Name = "06. ExcelHelper";     Description = "OpenXML Excel generation and path update" },
        [PSCustomObject]@{ Id = "WorkflowHelpers"; ModuleId = "WorkflowHelpers"; Name = "07. WorkflowHelpers"; Description = "DailyWorkflow and Step1-5 sandbox verification" },
        [PSCustomObject]@{ Id = "PhotoInfoEditor"; ModuleId = "PhotoInfoEditor"; Name = "08. PhotoInfoEditor"; Description = "Folder pairing, sync, costume auto-completion" },
        [PSCustomObject]@{ Id = "GigaFileHelper";  ModuleId = "GigaFileHelper";  Name = "09. GigaFileHelper";  Description = "GigaFile upload and protocol verification" },
        [PSCustomObject]@{ Id = "PhotoToolsMaster"; ModuleId = "PhotoToolsMaster"; Name = "10. PhotoToolsMaster"; Description = "PhotoTools Master master console & integrity test" }
    )
}

function Get-ModuleTestCases {
    return (Get-PhotoModuleTestDefinitions)
}

function Test-PsSyntax {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "Target file not found: $FilePath"
    }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $detail = ($errors | ForEach-Object { "Line $($_.Extent.StartLineNumber): $($_.Message)" }) -join "; "
        throw "Syntax error ($FilePath): $detail"
    }
}

function Assert-TestTrue {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "Assertion failed: $Message"
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
                $logDir = Initialize-PhotoLogger -RootDir $sandboxDir
                Assert-TestTrue (Test-Path -LiteralPath $logDir) "Log folder was not created"
                [void](Write-PhotoLog -Message "Info test" -ModuleName "Test" -Level "INFO")
                [void](Write-PhotoError -Message "Err test" -ModuleName "Test")
                $today = Get-Date -Format "yyyyMMdd"
                Assert-TestTrue (Test-Path -LiteralPath (Join-Path $logDir "process_$today.log")) "Process log not generated"
                Assert-TestTrue (Test-Path -LiteralPath (Join-Path $logDir "error_$today.log")) "Error log not generated"
                Initialize-PhotoLogger -RootDir $RootDir | Out-Null
                return "LogHelper test passed successfully."
            }
            "ConfigHelper" {
                $target = Join-Path $RootDir "common\ConfigHelper.ps1"
                Test-PsSyntax -FilePath $target
                . $target
                $iniPath = Join-Path $sandboxDir "settings.ini"
                $iniBody = "[Paths]`r`nImportRoot=$sandboxDir\import`r`nDevelopedRoot=$sandboxDir\dev`r`nLedgerFileName=TestLedger.xlsx`r`n[Extensions]`r`nRawExtensions=.ARW,.CR3`r`n"
                [System.IO.File]::WriteAllText($iniPath, $iniBody, (New-Object System.Text.UTF8Encoding($true)))
                $cfg = Get-PhotoToolsConfig -IniPath $iniPath
                Assert-TestTrue ($cfg.Paths.ImportRoot -eq "$sandboxDir\import") "ImportRoot mismatch"
                Assert-TestTrue ($cfg.DevRootDir -eq "$sandboxDir\dev") "DevRootDir compat key resolution failed"
                Assert-TestTrue ($cfg.ExcelPath -eq "$sandboxDir\dev\TestLedger.xlsx") "ExcelPath resolution failed"
                $period = Get-ArchivePeriodSubPath -DateFolderName "2026_11_15" -Config $cfg
                Assert-TestTrue (-not [string]::IsNullOrEmpty($period.RelativePeriodPath)) "Archive period path resolution failed"
                $savedIni = Join-Path $sandboxDir "saved_settings.ini"
                [void](Save-PhotoToolsSettingsIni -IniPath $savedIni -Settings @{
                    Paths = @{ ImportRoot1 = "$sandboxDir\imp2"; DevelopedRoot = "$sandboxDir\dev2"; LedgerFileName = "Saved.xlsx" }
                    ArchivePeriod = @{ Q1_Months = "1,2,3"; Q2_Months = "4,5,6"; Q3_Months = "7,8,9"; Q4_Months = "10,11,12" }
                    Extensions = @{ RawExtensions = ".ARW,.CR3"; ImageExtensions = ".JPG,.PNG" }
                    Mega = @{ MegaCmdPath = ""; MegaRemoteRoot = "/CustomRoot"; MegaLogPath = "$sandboxDir\mega.log" }
                })
                $cfg2 = Get-PhotoToolsConfig -IniPath $savedIni
                Assert-TestTrue ($cfg2.ImportRoot1 -eq "$sandboxDir\imp2") "Saved ImportRoot1 round-trip failed"
                Assert-TestTrue ($cfg2.MegaRemoteRoot -eq "/CustomRoot") "Saved MegaRemoteRoot round-trip failed"
                return "ConfigHelper test passed successfully."
            }
            "PhotoInfoHelper" {
                $target = Join-Path $RootDir "common\PhotoInfoHelper.ps1"
                Test-PsSyntax -FilePath $target
                . $target
                $folder = Join-Path $sandboxDir "2026_11_15\01"
                New-Item -ItemType Directory -Path $folder -Force | Out-Null
                $info = New-EmptyPhotoInfo -FolderPath $folder
                $info.EventName = "TestEvent"
                $info.Persons[0] = @{ Name = "Model1"; CostumeOrChar = "Costume1"; XAccount = "@model_1"; Comment = "Note1" }
                $info.Persons.Add(@{ Name = "Model2"; CostumeOrChar = "Costume2"; XAccount = "@model_2"; Comment = "Note2" })
                [void](Write-PhotoInfoTxt -FolderPath $folder -Info $info)
                $readBack = Read-PhotoInfoTxt -FolderPath $folder
                Assert-TestTrue ($readBack.Persons.Count -eq 2) "Multi-person block count mismatch"
                Assert-TestTrue ($readBack.Persons[1].CostumeOrChar -eq "Costume2") "Second person costume mismatch"
                Assert-TestTrue ($readBack.DateStr -eq "2026_11_15") "Date extraction mismatch"
                return "PhotoInfoHelper test passed successfully."
            }
            "SceneHelper" {
                $target = Join-Path $RootDir "common\SceneHelper.ps1"
                Test-PsSyntax -FilePath $target
                . $target
                $histFile = Join-Path $sandboxDir "scene_history.json"
                Update-SceneHistoryData -HistoryPath $histFile -Category "Event" -SceneName "Scene1" -CostumeName "CostumeA" -ModelNames @("ModelA") -DateStr "2026_11_15"
                $cand = Get-SceneHistoryData -HistoryPath $histFile
                Assert-TestTrue ($cand.Scenes -contains "Scene1") "Scene history not found"
                Assert-TestTrue ($cand.Costumes -contains "CostumeA") "Costume history not found"
                $f1 = Join-Path $sandboxDir "2026_11_15\01"
                $f2 = Join-Path $sandboxDir "2026_11_15\02"
                New-Item -ItemType Directory -Path $f1 -Force | Out-Null
                New-Item -ItemType Directory -Path $f2 -Force | Out-Null
                $tNm = Get-Tag @(0x3010, 0x540D, 0x524D, 0x3011)
                $tCs = Get-Tag @(0x3010, 0x8863, 0x88C5, 0x30FB, 0x30AD, 0x30E3, 0x30E9, 0x3011)
                [System.IO.File]::WriteAllText((Join-Path $f1 "写真情報.txt"), "$tNm`ModelA`r`n$tCs`CostumeA`r`n", (New-Object System.Text.UTF8Encoding($true)))
                [System.IO.File]::WriteAllText((Join-Path $f2 "写真情報.txt"), "$tNm`ModelA`r`n$tCs`CostumeB`r`n", (New-Object System.Text.UTF8Encoding($true)))
                $same = @(Find-SameModelFoldersOnDate -CurrentFolder $f1 -DateStr "2026_11_15" -ModelName "ModelA")
                Assert-TestTrue ($same.Count -eq 2) "Same model folder search count mismatch: $($same.Count)"
                return "SceneHelper test passed successfully."
            }
            "XHelper" {
                $target = Join-Path $RootDir "common\XHelper.ps1"
                Test-PsSyntax -FilePath $target
                . $target
                Assert-TestTrue ((Normalize-XAccount "https://x.com/sample_user?s=20") -eq "@sample_user") "X account normalization failed"
                Assert-TestTrue ((Clean-XDisplayName "ModelName@Event sample / X") -eq "ModelName") "Display name cleaning failed"
                $xh = Join-Path $sandboxDir "x_history.json"
                $sampleJson = '[{"account":"@user_a","name":"DisplayA","dates":["2026_11_15"],"updatedAt":"2026-11-21 10:00:00"}]'
                [System.IO.File]::WriteAllText($xh, $sampleJson, (New-Object System.Text.UTF8Encoding($true)))
                $cfg = @{ XHistoryPath = $xh }
                $list1 = @(Read-XHistoryList -HistoryPath $xh)
                Assert-TestTrue ($list1.Count -eq 1 -and ($list1[0].dates -contains "2026_11_15")) "Dates array read failed"
                Save-XHistory -Account "@user_a" -Name "DisplayA_Updated" -Config $cfg -DateStr "2026_11_20"
                $list2 = @(Read-XHistoryList -HistoryPath $xh)
                Assert-TestTrue (($list2[0].dates -contains "2026_11_15") -and ($list2[0].dates -contains "2026_11_20")) "Dates array merge save failed"
                return "XHelper test passed successfully."
            }
            "ExcelHelper" {
                $target = Join-Path $RootDir "common\ExcelHelper.ps1"
                Test-PsSyntax -FilePath $target
                . $target
                $xlsxPath = Join-Path $sandboxDir "PhotoLedger.xlsx"
                $cfg = @{ ExcelPath = $xlsxPath }
                $rec1 = @(
                    @{ DateStr = "2026_11_15"; Category = "Event"; EventName = "Test"; CostumeOrChar = "Cos1"; Name = "Model1"; XAccount = "@m1"; MultiFolder = "Multi (2)"; RelPath = "2026_11_15\01"; FolderName = "01"; ImportFolder = "G:\eos\2026_11_15\01"; DevFolder = "G:\dev\2026_11_15\01"; PersonIndex = "1" }
                )
                Update-PhotoExcelLedger -Records $rec1 -Config $cfg
                Assert-TestTrue (Test-Path -LiteralPath $xlsxPath) "xlsx file not generated"
                $rows = @(Read-XlsxRows -XlsxPath $xlsxPath)
                Assert-TestTrue ($rows.Count -eq 2) "xlsx row count mismatch: $($rows.Count)"
                $moved = Update-PhotoLedgerPathsAfterMove -OldBasePath "G:\dev\2026_11_15" -NewBasePath "J:\archive\2026_11_15" -ColumnType "Developed" -Config $cfg
                Assert-TestTrue ($moved -eq 1) "Archive path update count mismatch: $moved"
                return "ExcelHelper test passed successfully."
            }
            "WorkflowHelpers" {
                $wfFiles = @(
                    "workflow\DailyWorkflow.ps1",
                    "workflow\SyncExcelFromTxt.ps1",
                    "workflow\WorkflowStep1Helper.ps1",
                    "workflow\WorkflowStep2Helper.ps1",
                    "workflow\WorkflowStep3Helper.ps1",
                    "workflow\WorkflowStep4Helper.ps1",
                    "workflow\WorkflowStep5Helper.ps1"
                )
                foreach ($rel in $wfFiles) {
                    Test-PsSyntax -FilePath (Join-Path $RootDir $rel)
                }
                . (Join-Path $RootDir "common\LogHelper.ps1")
                . (Join-Path $RootDir "common\ConfigHelper.ps1")
                . (Join-Path $RootDir "workflow\WorkflowStep1Helper.ps1")
                . (Join-Path $RootDir "workflow\WorkflowStep2Helper.ps1")
                . (Join-Path $RootDir "workflow\WorkflowStep3Helper.ps1")
                Initialize-PhotoLogger -RootDir $sandboxDir | Out-Null

                $impDate = Join-Path $sandboxDir "import\2026_11_15"
                New-Item -ItemType Directory -Path $impDate -Force | Out-Null
                $s1 = Invoke-WorkflowStep1 -DateFolder $impDate -Count 2
                Assert-TestTrue ($s1.CreatedCount -eq 2) "Step1 created count mismatch"
                [System.IO.File]::WriteAllText((Join-Path $impDate "01\IMG_0001.ARW"), "RAWDATA")

                $cfg = @{
                    Paths = @{
                        ImportRoot    = (Join-Path $sandboxDir "import")
                        RawSaveRoot   = (Join-Path $sandboxDir "raw")
                        DevelopedRoot = (Join-Path $sandboxDir "dev")
                    }
                    Extensions = @{
                        RawExtensions   = @(".ARW", ".CR3")
                        ImageExtensions = @(".JPG")
                    }
                }
                $s2 = Invoke-WorkflowStep2 -ImportDateFolder $impDate -Config $cfg
                Assert-TestTrue ($s2.MovedRawCount -eq 1) "Step2 RAW move count mismatch"
                [System.IO.File]::WriteAllText((Join-Path $cfg.Paths.DevelopedRoot "2026_11_15\IMG_0001.jpg"), "JPGDATA")
                $s3 = Invoke-WorkflowStep3 -DateFolderName "2026_11_15" -Config $cfg
                Assert-TestTrue ($s3.SortedCount -eq 1) "Step3 sort count mismatch"
                Assert-TestTrue (Test-Path -LiteralPath (Join-Path $cfg.Paths.DevelopedRoot "2026_11_15\01\IMG_0001.jpg")) "Step3 sorted file missing"
                return "WorkflowHelpers test passed successfully."
            }
            "PhotoInfoEditor" {
                $editorFile = Join-Path $RootDir "editor\PhotoInfoEditor.ps1"
                $logicFile  = Join-Path $RootDir "common\PhotoEditorLogic.ps1"
                Test-PsSyntax -FilePath $editorFile
                Test-PsSyntax -FilePath $logicFile
                . $logicFile
                $impRoot = Join-Path $sandboxDir "import"
                $devRoot = Join-Path $sandboxDir "dev"
                $impSub1 = Join-Path $impRoot "2026_11_15\01"
                $devSub1 = Join-Path $devRoot "2026_11_15\01"
                $devSub2 = Join-Path $devRoot "2026_11_15\02"
                New-Item -ItemType Directory -Path $impSub1 -Force | Out-Null
                New-Item -ItemType Directory -Path $devSub1 -Force | Out-Null
                New-Item -ItemType Directory -Path $devSub2 -Force | Out-Null
                $eff = Initialize-PhotoEditorEnvironment -ScriptDir (Join-Path $RootDir "editor") -ExternalConfig @{
                    ImportRoot1      = $impRoot
                    DevRoot          = $devRoot
                    ExcelPath        = (Join-Path $sandboxDir "Ledger.xlsx")
                    XHistoryPath     = (Join-Path $sandboxDir "x_hist.json")
                    SceneHistoryPath = (Join-Path $sandboxDir "s_hist.json")
                }
                $paired1 = Resolve-PairedPhotoFolders -Folder $impSub1 -EffectiveConfig $eff
                Assert-TestTrue ($paired1.DevFolder -eq $devSub1) "Folder pairing resolution failed"
                $pList = New-Object System.Collections.Generic.List[hashtable]
                $pList.Add(@{ Name = "ModelX"; CostumeOrChar = "CostumeX"; XAccount = "https://x.com/mx"; Comment = "Note" })
                [void](Save-AllPhotoInfoAndLedger -FormData @{ Category = "Event"; DateStr = "2026_11_15"; EventName = "TestEvent"; MegaLink = ""; GigaFileLink = "" } -PersonsList $pList -PairedObj $paired1 -EffectiveConfig $eff)
                Assert-TestTrue (Test-Path -LiteralPath (Join-Path $devSub1 "写真情報.txt")) "PhotoInfo.txt not saved to developed folder"

                # Date-root (1 person per day) PhotoInfo pairing & save test
                $impDateRoot = Join-Path $impRoot "2026_11_16"
                $devDateRoot = Join-Path $devRoot "2026_11_16"
                New-Item -ItemType Directory -Path $impDateRoot -Force | Out-Null
                New-Item -ItemType Directory -Path $devDateRoot -Force | Out-Null
                $pairedRoot = Resolve-PairedPhotoFolders -Folder $impDateRoot -EffectiveConfig $eff
                Assert-TestTrue ($pairedRoot.DevFolder -eq $devDateRoot) "Date-root folder pairing failed"
                Assert-TestTrue ($pairedRoot.DateStr -eq "2026_11_16") "Date-root DateStr extraction failed"
                $pRootList = New-Object System.Collections.Generic.List[hashtable]
                $pRootList.Add(@{ Name = "SoloModel"; CostumeOrChar = "SoloCostume"; XAccount = "@solo_model"; Comment = "1-day-1-person" })
                [void](Save-AllPhotoInfoAndLedger -FormData @{ Category = "Event"; DateStr = "2026_11_16"; EventName = "SoloShoot"; MegaLink = ""; GigaFileLink = "" } -PersonsList $pRootList -PairedObj $pairedRoot -EffectiveConfig $eff)
                Assert-TestTrue (Test-Path -LiteralPath (Join-Path $impDateRoot "写真情報.txt")) "Date-root PhotoInfo.txt not saved to import folder"
                Assert-TestTrue (Test-Path -LiteralPath (Join-Path $devDateRoot "写真情報.txt")) "Date-root PhotoInfo.txt not saved to developed folder"
                return "PhotoInfoEditor test passed successfully."
            }
            "GigaFileHelper" {
                $bridge = Join-Path $RootDir "common\GigaFileHelper.ps1"
                $core   = Join-Path $RootDir "gigafile\send_to_gigafile.ps1"
                $proto  = Join-Path $RootDir "common\OpenFromProtocol.ps1"
                Test-PsSyntax -FilePath $bridge
                Test-PsSyntax -FilePath $core
                Test-PsSyntax -FilePath $proto
                . $bridge
                Assert-TestTrue ($null -ne (Get-Command Invoke-GigaFileUploadForFolder -ErrorAction SilentlyContinue)) "Invoke-GigaFileUploadForFolder not defined"
                Assert-TestTrue ($null -ne (Get-Command Invoke-GigaFileUploadWithCallback -ErrorAction SilentlyContinue)) "Invoke-GigaFileUploadWithCallback not defined"
                return "GigaFileHelper test passed successfully."
            }
            "PhotoToolsMaster" {
                $masterScript = Join-Path $RootDir "PhotoToolsMaster.ps1"
                $masterBatch  = Join-Path $RootDir "StartPhotoToolsMaster.bat"
                $settingsScript = Join-Path $RootDir "editor\SettingsEditor.ps1"
                Test-PsSyntax -FilePath $masterScript
                Test-PsSyntax -FilePath $settingsScript
                Assert-TestTrue (Test-Path -LiteralPath $masterScript) "PhotoToolsMaster.ps1 not found"
                Assert-TestTrue (Test-Path -LiteralPath $masterBatch) "StartPhotoToolsMaster.bat not found"
                return "PhotoToolsMaster test passed successfully."
            }
            default {
                throw "Unknown test module ID: $ModuleId"
            }
        }
    } finally {
        if (Test-Path -LiteralPath $sandboxDir) {
            Remove-Item -LiteralPath $sandboxDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
