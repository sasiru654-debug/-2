#requires -Version 5.1
# ==============================================================================
# ModuleTestCases.ps1 - PhotoTools Sandbox Tests (01 ～ 12) (UTF-8 BOM / CRLF)
# ==============================================================================

function Get-Tag {
    param([int[]]$Codes)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $Codes) { [void]$sb.Append([char]$c) }
    return $sb.ToString()
}

function Get-PhotoModuleTestDefinitions {
    return @(
        [PSCustomObject]@{ Id = "LogHelper";             ModuleId = "LogHelper";             Name = "01. LogHelper";             Description = "INFO/ERROR log output and path resolution" },
        [PSCustomObject]@{ Id = "ConfigHelper";          ModuleId = "ConfigHelper";          Name = "02. ConfigHelper";          Description = "settings.ini load, compat keys, period calculation" },
        [PSCustomObject]@{ Id = "PhotoInfoHelper";       ModuleId = "PhotoInfoHelper";       Name = "03. PhotoInfoHelper";       Description = "PhotoInfo.txt read/write, X/X_URL migration, DL password & expiry" },
        [PSCustomObject]@{ Id = "SceneHelper";           ModuleId = "SceneHelper";           Name = "04. SceneHelper";           Description = "Scene history, candidates, same-model search" },
        [PSCustomObject]@{ Id = "XHelper";               ModuleId = "XHelper";               Name = "05. XHelper";               Description = "X account normalization and dates JSON history" },
        [PSCustomObject]@{ Id = "ExcelHelper";           ModuleId = "ExcelHelper";           Name = "06. ExcelHelper";           Description = "OpenXML Excel generation and path update" },
        [PSCustomObject]@{ Id = "WorkflowHelpers";       ModuleId = "WorkflowHelpers";       Name = "07. WorkflowHelpers";       Description = "DailyWorkflow and Step1-5 sandbox verification" },
        [PSCustomObject]@{ Id = "PhotoInfoEditor";       ModuleId = "PhotoInfoEditor";       Name = "08. PhotoInfoEditor";       Description = "Folder pairing, sync, costume auto-completion" },
        [PSCustomObject]@{ Id = "GigaFileHelper";        ModuleId = "GigaFileHelper";        Name = "09. GigaFileHelper";        Description = "GigaFile upload and protocol verification" },
        [PSCustomObject]@{ Id = "PhotoToolsMaster";      ModuleId = "PhotoToolsMaster";      Name = "10. PhotoToolsMaster";      Description = "PhotoTools Master console, SettingsEditor & Updater integrity" },
        [PSCustomObject]@{ Id = "MessageTemplateHelper"; ModuleId = "MessageTemplateHelper"; Name = "11. MessageTemplateHelper"; Description = "Delivery message templates, multi-folder links & MEGA comment presets" },
        [PSCustomObject]@{ Id = "GeminiCharacterHelper"; ModuleId = "GeminiCharacterHelper"; Name = "12. GeminiCharacterHelper"; Description = "DPAPI key protection, EXIF strip, resize/mask & character format" }
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
                $info.DlPassword = "1234"
                $info.GigaFileExpiry = "2026/12/25まで"
                $info.Persons[0] = @{ Name = "Model1"; CostumeOrChar = "Costume1"; XAccount = "@model_1"; Comment = "Note1" }
                $info.Persons.Add(@{ Name = "Model2"; CostumeOrChar = "Costume2"; XAccount = "@model_2"; Comment = "Note2" })
                [void](Write-PhotoInfoTxt -FolderPath $folder -Info $info)
                $writtenRaw = [System.IO.File]::ReadAllText((Join-Path $folder "写真情報.txt"), [System.Text.Encoding]::UTF8)
                $tX = Get-Tag @(0x3010, 0x0058, 0x3011)
                $tXUrl = Get-Tag @(0x3010, 0x0058, 0x005F, 0x0055, 0x0052, 0x004C, 0x3011)
                Assert-TestTrue ($writtenRaw.Contains("$tX`@model_1")) "Expected account name in X tag"
                Assert-TestTrue ($writtenRaw.Contains("$tXUrl`https://x.com/model_1")) "Expected URL in X_URL tag"
                $readBack = Read-PhotoInfoTxt -FolderPath $folder
                Assert-TestTrue ($readBack.Persons.Count -eq 2) "Multi-person block count mismatch"
                Assert-TestTrue ($readBack.Persons[1].CostumeOrChar -eq "Costume2") "Second person costume mismatch"
                Assert-TestTrue ($readBack.Persons[0].XAccount -eq "@model_1") "XAccount readback mismatch"
                Assert-TestTrue ($readBack.Persons[0].XUrl -eq "https://x.com/model_1") "XUrl readback mismatch"
                Assert-TestTrue ($readBack.DlPassword -eq "1234") "DlPassword readback mismatch"
                Assert-TestTrue ($readBack.GigaFileExpiry -eq "2026/12/25まで") "GigaFileExpiry readback mismatch"
                Assert-TestTrue ($readBack.DateStr -eq "2026_11_15") "Date extraction mismatch"

                # Legacy auto-migration test: 【X】https://x.com/legacy_user -> 【X】@legacy_user + 【X_URL】https://x.com/legacy_user on read
                $legacyFolder = Join-Path $sandboxDir "2026_11_16\01"
                New-Item -ItemType Directory -Path $legacyFolder -Force | Out-Null
                $tNm = Get-Tag @(0x3010, 0x540D, 0x524D, 0x3011)
                $tCs = Get-Tag @(0x3010, 0x8863, 0x88C5, 0x30FB, 0x30AD, 0x30E3, 0x30E9, 0x3011)
                $tUp = Get-Tag @(0x3010, 0x6700, 0x7D42, 0x66F4, 0x65B0, 0x65E5, 0x6642, 0x3011)
                $legacyBody = "$tUp`2026/11/16 12:00:00`r`n----------------------------------------`r`n$tNm`LegacyModel`r`n$tCs`LegacyCos`r`n$tX`https://x.com/legacy_user`r`n----------------------------------------`r`n"
                [System.IO.File]::WriteAllText((Join-Path $legacyFolder "写真情報.txt"), $legacyBody, (New-Object System.Text.UTF8Encoding($true)))
                $migrated = Read-PhotoInfoTxt -FolderPath $legacyFolder
                Assert-TestTrue ($migrated.Persons[0].XAccount -eq "@legacy_user") "Legacy XAccount parse failed"
                Assert-TestTrue ($migrated.Persons[0].XUrl -eq "https://x.com/legacy_user") "Legacy XUrl parse failed"
                $migratedRaw = [System.IO.File]::ReadAllText((Join-Path $legacyFolder "写真情報.txt"), [System.Text.Encoding]::UTF8)
                Assert-TestTrue ($migratedRaw.Contains("$tX`@legacy_user")) "Legacy file was not migrated to account name in X tag"
                Assert-TestTrue ($migratedRaw.Contains("$tXUrl`https://x.com/legacy_user")) "Legacy file was not migrated to add X_URL tag"
                Assert-TestTrue ($migratedRaw.Contains("$tUp`2026/11/16 12:00:00")) "Legacy migration did not preserve original UpdatedAt"
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
                $masterScript   = Join-Path $RootDir "PhotoToolsMaster.ps1"
                $masterBatch    = Join-Path $RootDir "StartPhotoToolsMaster.bat"
                $settingsScript = Join-Path $RootDir "editor\SettingsEditor.ps1"
                $updaterScript  = Join-Path $RootDir "updater\PhotoToolsUpdater.ps1"
                Test-PsSyntax -FilePath $masterScript
                Test-PsSyntax -FilePath $settingsScript
                Test-PsSyntax -FilePath $updaterScript
                Assert-TestTrue (Test-Path -LiteralPath $masterScript) "PhotoToolsMaster.ps1 not found"
                Assert-TestTrue (Test-Path -LiteralPath $masterBatch) "StartPhotoToolsMaster.bat not found"
                Assert-TestTrue (Test-Path -LiteralPath $updaterScript) "PhotoToolsUpdater.ps1 not found"
                return "PhotoToolsMaster test passed successfully."
            }
            "MessageTemplateHelper" {
                $helperFile   = Join-Path $RootDir "common\MessageTemplateHelper.ps1"
                $composerFile = Join-Path $RootDir "editor\MessageComposerDialog.ps1"
                $settingsFile = Join-Path $RootDir "editor\SettingsEditor.ps1"
                Test-PsSyntax -FilePath $helperFile
                Test-PsSyntax -FilePath $composerFile
                Test-PsSyntax -FilePath $settingsFile
                . $helperFile

                $storePath = Join-Path $sandboxDir "message_templates.json"
                $store = Read-MessageTemplateStore -StorePath $storePath
                Assert-TestTrue (@($store.Templates).Count -eq 0) "Initial Templates list should be empty"
                Assert-TestTrue (@($store.MegaComments).Count -eq 5) "Initial MegaComments should have 5 presets"

                # Add template & verify save/reload + category default selection
                $store.Templates += @(
                    [PSCustomObject]@{ id = "tpl_ev"; name = "イベント用"; category = "イベント"; isDefault = $true; body = "{名前}様`r`n{データリンク}" },
                    [PSCustomObject]@{ id = "tpl_cm"; name = "共通"; category = "共通"; isDefault = $true; body = "{名前}さん`r`n{データリンク}`r`n{MEGAコメント}" }
                )
                [void](Save-MessageTemplateStore -StorePath $storePath -Store $store)
                $reloaded = Read-MessageTemplateStore -StorePath $storePath
                Assert-TestTrue (@($reloaded.Templates).Count -eq 2) "Saved templates reload count mismatch"
                $selEv = Select-DefaultTemplateForCategory -Store $reloaded -Category "イベント"
                Assert-TestTrue ($null -ne $selEv -and $selEv.id -eq "tpl_ev") "Category default template selection failed"

                # Solo GigaFile render: omit DL password when empty, format expiry as yyyy/MM/ddまで
                $soloEntry = @{
                    GigaFileLink = "https://10.gigafile.nu/1225-solo"
                    MegaLink     = "https://mega.nz/folder/solo"
                    DlPassword   = ""
                    ExpiryDate   = "2026/12/25"
                    Persons      = @(@{ Name = "モデルA"; CostumeOrChar = "キャラA"; XAccount = "@model_a" })
                }
                $msgGiga = Render-DeliveryMessage -TemplateBody "{名前}様`r`n{データリンク}`r`n{MEGAコメント}" -RecipientContext @{
                    Name = "モデルA"; XAccount = "@model_a"; XUrl = "https://x.com/model_a"; DateStr = "2026_11_25"; Category = "個撮"; EventName = "スタジオ"; CostumeOrChar = "キャラA"
                } -FolderEntries @($soloEntry) -LinkType "GigaFile" -MegaCommentBody "MEGA案内文"
                Assert-TestTrue ($msgGiga.Contains("https://10.gigafile.nu/1225-solo")) "Solo GigaFile URL missing"
                Assert-TestTrue (-not $msgGiga.Contains("DLパスワード")) "Empty DL password should be omitted"
                Assert-TestTrue ($msgGiga.Contains("保持期間：2026/12/25まで")) "Expiry format mismatch"
                Assert-TestTrue (-not $msgGiga.Contains("MEGA案内文")) "MEGA comment should not appear when GigaFile is selected"
                Assert-TestTrue (-not $msgGiga.Contains("個撮リンク")) "Single solo link should not include header"

                # Multi-folder combined render: solo + 2-person + 3-person with companions joined by 、
                $multi2 = @{
                    GigaFileLink = "https://10.gigafile.nu/1225-pair"
                    MegaLink     = "https://mega.nz/folder/pair"
                    DlPassword   = "7777"
                    ExpiryDate   = "2026/12/25まで"
                    Persons      = @(
                        @{ Name = "モデルA"; CostumeOrChar = "キャラA"; XAccount = "@model_a" },
                        @{ Name = "モデルB"; CostumeOrChar = "キャラB"; XAccount = "@model_b" }
                    )
                }
                $multi3 = @{
                    GigaFileLink = "https://10.gigafile.nu/1225-trio"
                    MegaLink     = "https://mega.nz/folder/trio"
                    DlPassword   = ""
                    ExpiryDate   = ""
                    Persons      = @(
                        @{ Name = "モデルA"; CostumeOrChar = "キャラA"; XAccount = "@model_a" },
                        @{ Name = "モデルB"; CostumeOrChar = "キャラB"; XAccount = "@model_b" },
                        @{ Name = "モデルC"; CostumeOrChar = "キャラC"; XAccount = "@model_c" }
                    )
                }
                $msgCombined = Render-DeliveryMessage -TemplateBody "{名前}様`r`n{データリンク}" -RecipientContext @{
                    Name = "モデルA"; XAccount = "@model_a"; XUrl = "https://x.com/model_a"; DateStr = "2026_11_25"; Category = "併せ"; EventName = "併せ撮影"; CostumeOrChar = "キャラA"
                } -FolderEntries @($soloEntry, $multi2, $multi3) -LinkType "GigaFile" -MegaCommentBody "MEGA案内文"
                Assert-TestTrue ($msgCombined.Contains("個撮リンク１")) "Solo folder header mismatch in combined mode"
                Assert-TestTrue ($msgCombined.Contains("複数リンク１`r`nモデルB（キャラB）")) "2-person companion line mismatch"
                Assert-TestTrue ($msgCombined.Contains("複数リンク２`r`nモデルB（キャラB）、モデルC（キャラC）")) "3-person companion join mismatch"
                Assert-TestTrue ($msgCombined.Contains("DLパスワード：7777")) "Non-empty DL password missing"

                # MEGA render without explicit {MEGAコメント} token -> auto-appended after {データリンク}
                $msgMegaAuto = Render-DeliveryMessage -TemplateBody "{名前}様`r`n{データリンク}" -RecipientContext @{
                    Name = "モデルA"; XAccount = "@model_a"; XUrl = "https://x.com/model_a"; DateStr = "2026_11_25"; Category = "個撮"; EventName = "スタジオ"; CostumeOrChar = "キャラA"
                } -FolderEntries @($soloEntry) -LinkType "MEGA" -MegaCommentBody "MEGA保存案内テスト"
                Assert-TestTrue ($msgMegaAuto.Contains("https://mega.nz/folder/solo")) "MEGA URL missing"
                Assert-TestTrue ($msgMegaAuto.Contains("MEGA保存案内テスト")) "MEGA comment auto-append failed"

                return "MessageTemplateHelper test passed successfully."
            }
            "GeminiCharacterHelper" {
                $aiHelper = Join-Path $RootDir "common\GeminiCharacterHelper.ps1"
                $aiDialog = Join-Path $RootDir "editor\CharacterLookupDialog.ps1"
                $settings = Join-Path $RootDir "editor\SettingsEditor.ps1"
                $editor   = Join-Path $RootDir "editor\PhotoInfoEditor.ps1"
                Test-PsSyntax -FilePath $aiHelper
                Test-PsSyntax -FilePath $aiDialog
                Test-PsSyntax -FilePath $settings
                Test-PsSyntax -FilePath $editor
                . $aiHelper

                # Settings default & round-trip
                $sPath = Join-Path $sandboxDir "ai_character_settings.json"
                $def = Get-GeminiCharacterSettings -SettingsPath $sPath
                Assert-TestTrue ($def.ModelName -eq "gemini-2.5-flash") "Default model mismatch"
                Assert-TestTrue ($def.PaidTierConfirmed -eq $false) "Default PaidTierConfirmed must be false"
                Assert-TestTrue ($def.DefaultOutputFormat -eq "CharWithSeries") "Default output format mismatch"
                $def.PaidTierConfirmed = $true
                $def.MaxImageEdgePx = 768
                [void](Save-GeminiCharacterSettings -Settings $def -SettingsPath $sPath)
                $reloaded = Get-GeminiCharacterSettings -SettingsPath $sPath
                Assert-TestTrue ($reloaded.PaidTierConfirmed -eq $true -and $reloaded.MaxImageEdgePx -eq 768) "Settings save/reload mismatch"

                # DPAPI key protection round-trip (must not store plaintext)
                $kPath = Join-Path $sandboxDir "gemini_api_key.dat"
                $sampleKey = "AIzaSyTestSandboxKeyValue123456"
                [void](Save-GeminiApiKeyProtected -PlainApiKey $sampleKey -KeyPath $kPath)
                Assert-TestTrue (Test-GeminiApiKeyStored -KeyPath $kPath) "Encrypted key file not created"
                $rawKeyText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($kPath))
                Assert-TestTrue (-not $rawKeyText.Contains($sampleKey)) "Plaintext API key leaked into dat file"
                $decrypted = Get-GeminiApiKeyDecrypted -KeyPath $kPath
                Assert-TestTrue ($decrypted -eq $sampleKey) "DPAPI decrypt round-trip mismatch"
                Assert-TestTrue (Remove-GeminiApiKeyProtected -KeyPath $kPath) "Key removal failed"
                Assert-TestTrue (-not (Test-GeminiApiKeyStored -KeyPath $kPath)) "Key still exists after removal"

                # Output format verification
                Assert-TestTrue ((Format-CharacterResultText -CharacterName "フリーレン" -SeriesName "葬送のフリーレン" -FormatType "CharWithSeries") -eq "フリーレン（葬送のフリーレン）") "CharWithSeries format mismatch"
                Assert-TestTrue ((Format-CharacterResultText -CharacterName "フリーレン" -SeriesName "葬送のフリーレン" -FormatType "CharOnly") -eq "フリーレン") "CharOnly format mismatch"
                Assert-TestTrue ((Format-CharacterResultText -CharacterName "フリーレン" -SeriesName "葬送のフリーレン" -FormatType "SeriesSlashChar") -eq "葬送のフリーレン / フリーレン") "SeriesSlashChar format mismatch"

                # Sanitized in-memory payload verification (resize + EXIF strip + Black/Mosaic mask)
                $imgPath = Join-Path $sandboxDir "sample_photo.jpg"
                $srcBmp = New-Object System.Drawing.Bitmap(1200, 800)
                $g = [System.Drawing.Graphics]::FromImage($srcBmp)
                try {
                    $g.Clear([System.Drawing.Color]::FromArgb(240, 240, 240))
                } finally {
                    $g.Dispose()
                }
                $srcBmp.Save($imgPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                $srcBmp.Dispose()

                $maskRects = @([PSCustomObject]@{ X = 0.25; Y = 0.25; W = 0.5; H = 0.5 })
                $payloadBlack = New-SanitizedImagePayload -ImagePath $imgPath -MaskRectsNormalized $maskRects -MaskStyle "Black" -MaxEdgePx 640 -JpegQuality 75
                Assert-TestTrue ($payloadBlack.Width -eq 640 -and $payloadBlack.Height -eq 427) "Resized dimensions mismatch: $($payloadBlack.Width)x$($payloadBlack.Height)"
                Assert-TestTrue ($payloadBlack.MaskCount -eq 1) "Mask count mismatch"

                # Verify output JPEG has 0 EXIF properties and masked center pixel is darkened
                $msChk = New-Object System.IO.MemoryStream(,$payloadBlack.PreviewBytes)
                $chkImg = [System.Drawing.Image]::FromStream($msChk)
                try {
                    Assert-TestTrue (@($chkImg.PropertyItems).Count -eq 0) "Sanitized JPEG should have 0 EXIF metadata items"
                    $chkBmp = New-Object System.Drawing.Bitmap($chkImg)
                    try {
                        $centerPx = $chkBmp.GetPixel(320, 213)
                        Assert-TestTrue ($centerPx.R -lt 50 -and $centerPx.G -lt 50 -and $centerPx.B -lt 50) "Black mask did not darken masked region"
                    } finally {
                        $chkBmp.Dispose()
                    }
                } finally {
                    $chkImg.Dispose()
                    $msChk.Dispose()
                }

                $payloadMosaic = New-SanitizedImagePayload -ImagePath $imgPath -MaskRectsNormalized $maskRects -MaskStyle "Mosaic" -MaxEdgePx 640 -JpegQuality 75
                Assert-TestTrue ($payloadMosaic.MaskCount -eq 1 -and -not [string]::IsNullOrWhiteSpace($payloadMosaic.Base64)) "Mosaic mask payload generation failed"

                return "GeminiCharacterHelper test passed successfully."
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
